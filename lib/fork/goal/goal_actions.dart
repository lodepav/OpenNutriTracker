import 'package:opennutritracker/core/utils/tracked_day_lock.dart';
import 'package:opennutritracker/fork/adaptive/goal_saving.dart'
    show saveGoal;
import 'package:opennutritracker/fork/goal/goal_planner.dart';
import 'package:opennutritracker/fork/goal/goal_progress.dart';
import 'package:opennutritracker/fork/phases/phases.dart';

DateTime _date(DateTime t) => DateTime(t.year, t.month, t.day);

/// The running goal and the queue after it, as they were: what Undo puts
/// back.
typedef GoalSnapshot = ({
  PhasePlan? plan,
  List<PhasePlan> upcoming,
  Object? start,
});

/// Starting, completing and extending the profile's goal: its plan in the
/// phase store, and the pace and target weight in the profile, which the
/// formula, the check-in and Goal progress read; and the goals queued
/// after it, each [reflowed] to start the day the one before ends. Each
/// runs whole under the tracked-day lock for the profile current when
/// the actions were made, so a profile switch drops it rather than
/// splitting it between two profiles: make them as the screen acting
/// opens.
class GoalActions {
  final PhaseStore _store;
  final ProfileStamp _startedOn;

  /// Saves the pace (unless null) and the target weight (null clears
  /// it); false when a profile switch dropped it.
  final Future<bool> Function(double? kgPerWeek, double? targetKg) _saveGoal;
  final DateTime Function() _clock;

  /// Where the goal's start is kept. An injected save with no store here
  /// has no profile behind it, so keeps no start.
  final GoalStartStore? _starts;

  GoalActions({
    PhaseStore? store,
    Future<bool> Function(double? kgPerWeek, double? targetKg)? save,
    DateTime Function()? clock,
    ProfileStamp? startedOn,
    GoalStartStore? starts,
  }) : _store = store ?? PhaseStore(),
       _starts = starts ?? (save == null ? GoalStartStore() : null),
       _startedOn = startedOn ?? ProfileStamp.now(),
       _saveGoal = save ?? ((pace, target) => saveGoal(pace, target)),
       _clock = clock ?? DateTime.now;

  /// Starts [plan]; a plan starting later leaves today's pace as it is.
  /// A running goal [replacing] another is kept as completed first, unless
  /// it never began. The queued goals follow it.
  Future<bool> start(PhasePlan plan, {PhasePlan? replacing, double? nowKg}) =>
      _onProfile(() async {
        Future<bool> save() => _saveGoal(plan.paceOn(_clock()), plan.targetKg);
        // With none running, one removed may have left its start for Undo.
        final isNew = replacing != null || await _store.plan() == null;
        if (!await (isNew ? _forgettingStart(save) : save())) return false;
        if (replacing != null) await _keep(replacing, nowKg);
        await _store.save(plan);
        await _reflow(plan, await _store.upcoming(), nowKg);
        return true;
      });

  /// Keeps [plan] among the completed goals, unless it never began; the
  /// first queued goal starts today at [nowKg], else maintenance holds.
  Future<bool> complete(PhasePlan plan, double? nowKg) => _onProfile(() async {
    if (!await _forgettingStart(() => _startNext(nowKg))) return false;
    await _keep(plan, nowKg);
    return true;
  });

  /// Drops the running goal, kept nowhere; the first queued goal starts
  /// today at [nowKg], else maintenance holds. Its start stays for
  /// [restore] until the next goal starts.
  Future<bool> remove(double? nowKg) => _onProfile(() => _startNext(nowKg));

  /// Runs [plan], the goal extended; the queued goals move after it.
  Future<bool> extend(PhasePlan plan) => _onProfile(() async {
    if (!await _saveGoal(plan.paceOn(_clock()), plan.targetKg)) return false;
    await _store.save(plan);
    await _reflow(plan, await _store.upcoming(), null);
    return true;
  });

  /// Queues [plan] at [at] among the goals after the running one, last by
  /// default. With none running it starts today at [nowKg].
  Future<bool> add(PhasePlan plan, {int? at, double? nowKg}) =>
      _queue(nowKg, (q) => q.insert((at ?? q.length).clamp(0, q.length), plan));

  /// Puts [plan] in place of queued goal [index].
  Future<bool> replaceUpcoming(int index, PhasePlan plan) =>
      _queue(null, (q) => q[index] = plan);

  Future<bool> removeUpcoming(int index) =>
      _queue(null, (q) => q.removeAt(index));

  /// Moves queued goal [from] to place [to] in the queue.
  Future<bool> moveUpcoming(int from, int to) => _queue(
    null,
    (q) => q.insert(to.clamp(0, q.length - 1), q.removeAt(from)),
  );

  /// The running goal and the queue now, for [restore].
  Future<GoalSnapshot> snapshot() async => (
    plan: await _store.plan(),
    upcoming: await _store.upcoming(),
    start: await _starts?.stored(),
  );

  /// Puts back the running goal (its pace and target in the profile) and
  /// the queue as [was]: Undo after a move or a removal.
  Future<bool> restore(GoalSnapshot was) => _onProfile(() async {
    final plan = was.plan;
    final pace = plan == null ? 0.0 : plan.paceOn(_clock());
    // First, so the save's sync finds the goal's start: a queued goal that
    // took over has replaced it.
    await _starts?.putBack(was.start);
    if (!await _saveGoal(pace, plan?.targetKg)) return false;
    await _store.save(plan);
    await _store.saveUpcoming(was.upcoming);
    return true;
  });

  /// The first queued goal started on the day it was planned to, the
  /// running one kept as completed at [nowKg], once today reaches that
  /// day (or none runs); false when none is due, or a profile switch
  /// dropped it.
  Future<bool> startNextIfDue(double? nowKg) => _onProfile(() async {
    final queue = await _store.upcoming();
    if (queue.isEmpty) return false;
    final plan = await _store.plan();
    final today = _date(_clock());
    if (plan != null && today.isBefore(_date(queue.first.start))) return false;
    final next = queue.first;
    final saved = await _forgettingStart(
      () => _saveGoal(next.paceOn(today), next.targetKg),
    );
    if (!saved) return false;
    // The one before ended the day the next began, though the app
    // opened later.
    if (plan != null) {
      await _store.addToHistory([
        completedGoal(plan, nowKg, _date(next.start)),
      ]);
    }
    // It begins the day it was planned to, from the weight it really begins
    // at, which the weeks to a target and the goals after it follow.
    final started = nowKg != null && next.targetKg != null
        ? restarted(next, next.start, nowKg)
        : PhasePlan(
            start: next.start,
            phases: next.phases,
            startKg: nowKg ?? next.startKg,
            targetKg: next.targetKg,
            extensions: next.extensions,
          );
    await _store.save(started);
    await _reflow(started, queue.skip(1).toList(), nowKg);
    return true;
  });

  /// [plan] among the completed goals. One still to start ran no days:
  /// its record would end before it began.
  Future<void> _keep(PhasePlan plan, double? nowKg) async {
    if (_date(plan.start).isAfter(_date(_clock()))) return;
    await _store.addToHistory([completedGoal(plan, nowKg, _clock())]);
  }

  /// [save], the goal after the one over, with that one's start forgotten
  /// first: a save starts a sync of the start, which must not find it.
  /// Back if nothing was saved.
  Future<bool> _forgettingStart(Future<bool> Function() save) async {
    final starts = _starts;
    if (starts == null) return save();
    final was = await starts.forget();
    if (await save()) return true;
    await starts.putBack(was);
    return false;
  }

  /// [change] made to the queue, reflowed after the running goal; with
  /// none running, the first starts today.
  Future<bool> _queue(double? nowKg, void Function(List<PhasePlan>) change) =>
      _onProfile(() async {
        final queue = [...await _store.upcoming()];
        change(queue);
        final plan = await _store.plan();
        if (plan == null) {
          if (queue.isEmpty) return true;
          await _store.saveUpcoming(queue);
          return _startNext(nowKg);
        }
        await _reflow(plan, queue, nowKg);
        return true;
      });

  /// The first queued goal run from today at [nowKg] (its pace and target
  /// in the profile), the rest after it; with none, maintenance.
  Future<bool> _startNext(double? nowKg) async {
    final queue = await _store.upcoming();
    if (queue.isEmpty) {
      if (!await _saveGoal(0, null)) return false;
      await _store.save(null);
      return true;
    }
    final today = _date(_clock());
    final next = restarted(
      queue.first,
      today,
      nowKg ?? queue.first.startKg ?? 0,
    );
    if (!await _saveGoal(next.paceOn(today), next.targetKg)) return false;
    await _store.save(next);
    await _reflow(next, queue.skip(1).toList(), nowKg);
    return true;
  }

  Future<void> _reflow(
    PhasePlan current,
    List<PhasePlan> queue,
    double? nowKg,
  ) => _store.saveUpcoming(
    reflowed(
      current,
      queue,
      fromKg: nowKg ?? current.startKg ?? 0,
      today: _date(_clock()),
    ),
  );

  /// [action] on the actions' profile; false when a switch overtook it.
  Future<bool> _onProfile(Future<bool> Function() action) async =>
      await withTrackedDayLockOnProfile(action, startedOn: _startedOn) ?? false;
}
