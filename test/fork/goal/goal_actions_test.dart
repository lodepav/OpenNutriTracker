import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/utils/tracked_day_lock.dart';
import 'package:opennutritracker/fork/goal/goal_actions.dart';
import 'package:opennutritracker/fork/goal/goal_planner.dart';
import 'package:opennutritracker/fork/phases/phases.dart';

final _plan = GoalDraft(
  kind: PhaseKind.cut,
  startKg: 86.4,
  targetKg: 80,
  start: DateTime(2026, 10, 5),
).toPlan();

/// The phase store in memory, logging its writes to [log].
class _LoggedPhases extends PhaseStore {
  final List<String> log;
  PhasePlan? saved;

  _LoggedPhases(this.log);

  @override
  Future<void> save(PhasePlan? plan) async {
    saved = plan;
    log.add('plan');
  }

  @override
  Future<void> addToHistory(List<GoalRecord> records) async =>
      log.add('history');

  @override
  Future<List<PhasePlan>> upcoming() async => const [];

  @override
  Future<void> saveUpcoming(List<PhasePlan> plans) async {}
}

/// The phase store in memory: the running goal, the queue, the history.
class _MemoryPhases extends PhaseStore {
  PhasePlan? saved;
  final queue = <PhasePlan>[];
  final goals = <GoalRecord>[];

  _MemoryPhases([this.saved, List<PhasePlan> queue = const []]) {
    this.queue.addAll(queue);
  }

  @override
  Future<PhasePlan?> plan() async => saved;

  @override
  Future<void> save(PhasePlan? plan) async => saved = plan;

  @override
  Future<List<PhasePlan>> upcoming() async => [...queue];

  @override
  Future<void> saveUpcoming(List<PhasePlan> plans) async => queue
    ..clear()
    ..addAll(plans);

  @override
  Future<List<GoalRecord>> history() async => goals;

  @override
  Future<void> addToHistory(List<GoalRecord> records) async =>
      goals.addAll(records);
}

final _hold = GoalDraft(
  kind: PhaseKind.maintain,
  startKg: 80,
  start: DateTime(2027, 1, 4),
  maintainWeeks: 4,
).toPlan();

final _bulk = GoalDraft(
  kind: PhaseKind.bulk,
  startKg: 80,
  targetKg: 84,
  start: DateTime(2027, 2, 1),
  paceKg: 0.25,
).toPlan();

void main() {
  test('a profile switch after the actions were made drops them', () async {
    final log = <String>[];
    final store = _LoggedPhases(log);
    final actions = GoalActions(
      store: store,
      save: (_, _) async {
        log.add('profile');
        return true;
      },
      clock: () => DateTime(2026, 10, 6),
    );
    await withProfileSwitchLock(() async {});

    expect(await actions.start(_plan), isFalse);
    expect(await actions.complete(_plan, 80), isFalse);
    expect(await actions.extend(_plan), isFalse);
    expect(log, isEmpty);
  });

  test('a profile switch waits for the plan and the history', () async {
    final log = <String>[];
    Future<void>? switching;
    final actions = GoalActions(
      store: _LoggedPhases(log),
      save: (_, _) async {
        log.add('profile');
        // The switch starts while the pace is being saved, from outside
        // the lock's zone, as a tap would.
        switching = Zone.root.run(
          () => withProfileSwitchLock(() async => log.add('switch')),
        );
        return true;
      },
      clock: () => DateTime(2026, 10, 6),
    );

    expect(await actions.start(_plan, replacing: _plan, nowKg: 84), isTrue);
    await switching;
    expect(log, ['profile', 'history', 'plan', 'switch']);
  });

  group('the queue', () {
    late _MemoryPhases store;
    late List<(double?, double?)> saved;
    var today = DateTime(2026, 10, 20);

    GoalActions actions() => GoalActions(
      store: store,
      save: (pace, target) async {
        saved.add((pace, target));
        return true;
      },
      clock: () => today,
    );

    List<(PhaseKind, DateTime)> queued() => [
      for (final p in store.queue) (p.kind, p.start),
    ];

    setUp(() {
      store = _MemoryPhases(_plan);
      saved = [];
      today = DateTime(2026, 10, 20);
    });

    test('a goal added runs after the one before it', () async {
      // The cut ends Jan 4; the hold is 4 weeks.
      expect(await actions().add(_bulk), isTrue);
      expect(await actions().add(_hold, at: 0), isTrue);
      expect(queued(), [
        (PhaseKind.maintain, DateTime(2027, 1, 4)),
        (PhaseKind.bulk, DateTime(2027, 2, 1)),
      ]);
      // From the weight the cut ends at.
      expect(store.queue.first.startKg, 80);
      expect(saved, isEmpty);
    });

    test('replaced, moved or removed, the rest close up', () async {
      store.queue.addAll([_hold, _bulk]);
      await actions().moveUpcoming(1, 0);
      expect(queued(), [
        (PhaseKind.bulk, DateTime(2027, 1, 4)),
        (PhaseKind.maintain, DateTime(2027, 4, 26)),
      ]);
      await actions().removeUpcoming(0);
      expect(queued(), [(PhaseKind.maintain, DateTime(2027, 1, 4))]);
      final longer = GoalDraft(
        kind: PhaseKind.maintain,
        startKg: 80,
        start: DateTime(2027, 1, 4),
        maintainWeeks: 8,
      ).toPlan();
      await actions().replaceUpcoming(0, longer);
      expect(store.queue.single.end, DateTime(2027, 3, 1));
    });

    test('completing starts the next today, from the weight now', () async {
      store.queue.addAll([_bulk, _hold]);
      expect(await actions().complete(_plan, 82), isTrue);
      final next = store.saved!;
      expect(
        (next.kind, next.start, next.startKg),
        (PhaseKind.bulk, DateTime(2026, 10, 20), 82.0),
      );
      expect(saved, [(0.25, 84.0)]);
      expect(queued(), [(PhaseKind.maintain, next.end)]);
      expect(store.goals.single.kind, PhaseKind.cut);
    });

    test('with nothing queued, completing holds maintenance', () async {
      expect(await actions().complete(_plan, 82), isTrue);
      expect(store.saved, isNull);
      expect(saved, [(0.0, null)]);
    });

    test('removing the goal keeps nothing and starts the next', () async {
      store.queue.add(_hold);
      expect(await actions().remove(82), isTrue);
      expect(store.goals, isEmpty);
      expect(store.saved!.kind, PhaseKind.maintain);
      expect(store.saved!.start, DateTime(2026, 10, 20));
      expect(store.queue, isEmpty);
    });

    test('a goal added with none running starts today', () async {
      store.saved = null;
      expect(await actions().add(_bulk, nowKg: 79), isTrue);
      expect(store.saved!.start, DateTime(2026, 10, 20));
      expect(store.saved!.startKg, 79);
      expect(store.queue, isEmpty);
      expect(saved, [(0.25, 84.0)]);
    });

    test('extending moves the queue after the goal', () async {
      store.queue.add(_hold);
      final longer = extendedPlan(_plan, today: today, nowKg: 84, weeks: 20);
      expect(await actions().extend(longer), isTrue);
      expect(store.queue.single.start, longer.end);
    });

    test('the next goal starts on its day, the one before kept', () async {
      store.queue.addAll(
        reflowed(_plan, [_hold, _bulk], fromKg: 80),
      );
      expect(await actions().startNextIfDue(81), isFalse);
      today = DateTime(2027, 1, 4, 7);
      expect(await actions().startNextIfDue(80.2), isTrue);
      expect(store.saved!.kind, PhaseKind.maintain);
      expect(store.saved!.start, DateTime(2027, 1, 4));
      expect(store.goals.single.endKg, 80.2);
      expect(queued(), [(PhaseKind.bulk, DateTime(2027, 2, 1))]);
      expect(saved, [(0.0, null)]);
    });

    test('started late, the one before still ends the day the next '
        'began', () async {
      store.queue.addAll(
        reflowed(_plan, [_hold, _bulk], fromKg: 80),
      );
      // The app first opened three days after the hold was due.
      today = DateTime(2027, 1, 7, 9);
      expect(await actions().startNextIfDue(80.4), isTrue);
      expect(store.saved!.start, DateTime(2027, 1, 4));
      expect(store.goals.single.end, DateTime(2027, 1, 4));
    });

    test('a move that leaves a goal behind its target flags it', () async {
      // A cut to 81 after a bulk to 84; moved first, it starts at the
      // running cut's 80, already under its target.
      final cut = GoalDraft(
        kind: PhaseKind.cut,
        startKg: 84,
        targetKg: 81,
        start: DateTime(2027, 5, 3),
      ).toPlan();
      store.queue.addAll(
        reflowed(_plan, [_bulk, cut], fromKg: 80),
      );
      expect(store.queue.map(queuedProblem), [null, null]);
      await actions().moveUpcoming(1, 0);
      expect(queuedProblem(store.queue.first), isNotNull);
    });

    test('a profile switch drops a queue change', () async {
      final made = actions();
      await withProfileSwitchLock(() async {});
      expect(await made.add(_bulk), isFalse);
      expect(store.queue, isEmpty);
    });
  });
}
