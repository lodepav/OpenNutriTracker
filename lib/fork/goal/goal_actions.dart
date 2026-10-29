import 'package:opennutritracker/core/utils/tracked_day_lock.dart';
import 'package:opennutritracker/fork/adaptive/goal_plan_card.dart'
    show saveGoal;
import 'package:opennutritracker/fork/goal/goal_planner.dart';
import 'package:opennutritracker/fork/phases/phases.dart';

/// Starting, completing and extending the profile's goal: its plan in the
/// phase store, and the pace and target weight in the profile, which the
/// formula, the check-in and Goal progress read. Each runs whole under
/// the tracked-day lock for the profile current when the actions were
/// made, so a profile switch drops it rather than splitting it between
/// two profiles: make them as the screen acting opens.
class GoalActions {
  final PhaseStore _store;
  final ProfileStamp _startedOn;

  /// Saves the pace (unless null) and the target weight (null clears
  /// it); false when a profile switch dropped it.
  final Future<bool> Function(double? kgPerWeek, double? targetKg) _saveGoal;
  final DateTime Function() _clock;

  GoalActions({
    PhaseStore? store,
    Future<bool> Function(double? kgPerWeek, double? targetKg)? save,
    DateTime Function()? clock,
    ProfileStamp? startedOn,
  }) : _store = store ?? PhaseStore(),
       _startedOn = startedOn ?? ProfileStamp.now(),
       _saveGoal = save ?? ((pace, target) => saveGoal(pace, target)),
       _clock = clock ?? DateTime.now;

  /// Starts [plan]; a plan starting later leaves today's pace as it is.
  /// A running goal [replacing] another is kept as completed first.
  Future<bool> start(
    PhasePlan plan, {
    PhasePlan? replacing,
    double? nowKg,
  }) => _onProfile(() async {
    if (!await _saveGoal(plan.paceOn(_clock()), plan.targetKg)) return false;
    if (replacing != null) {
      await _store.addToHistory([completedGoal(replacing, nowKg, _clock())]);
    }
    await _store.save(plan);
    return true;
  });

  /// Keeps [plan] among the completed goals and holds maintenance.
  Future<bool> complete(PhasePlan plan, double? nowKg) => _onProfile(() async {
    if (!await _saveGoal(0, null)) return false;
    await _store.addToHistory([completedGoal(plan, nowKg, _clock())]);
    await _store.save(null);
    return true;
  });

  /// Runs [plan], the goal extended.
  Future<bool> extend(PhasePlan plan) => _onProfile(() async {
    if (!await _saveGoal(plan.paceOn(_clock()), plan.targetKg)) return false;
    await _store.save(plan);
    return true;
  });

  /// [action] on the actions' profile; false when a switch overtook it.
  Future<bool> _onProfile(Future<bool> Function() action) async =>
      await withTrackedDayLockOnProfile(action, startedOn: _startedOn) ?? false;
}
