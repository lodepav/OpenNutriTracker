import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/fork/goal/goal_actions.dart';
import 'package:opennutritracker/fork/goal/goal_planner.dart';
import 'package:opennutritracker/fork/phases/phases.dart';

// Monday 5 October 2026; the clocks change on the 25th.
final _start = DateTime(2026, 10, 5);

GoalDraft _cut({bool breaks = false}) => GoalDraft(
  kind: PhaseKind.cut,
  startKg: 86.4,
  targetKg: 80,
  start: _start,
  paceKg: 0.5,
  breaks: breaks,
);

class _MemoryPhases extends PhaseStore {
  PhasePlan? saved;
  final goals = <GoalRecord>[];

  _MemoryPhases([this.saved]);

  @override
  Future<PhasePlan?> plan() async => saved;

  @override
  Future<void> save(PhasePlan? plan) async => saved = plan;

  @override
  Future<List<GoalRecord>> history() async => goals;

  @override
  Future<void> addToHistory(List<GoalRecord> records) async =>
      goals.addAll(records);
}

void main() {
  group('GoalDraft.toPlan', () {
    test('a cut runs until the target at its pace', () {
      final plan = _cut().toPlan();
      expect(plan.phases, hasLength(1));
      expect(plan.phases.single.kgPerWeek, -0.5);
      expect(plan.phases.single.untilKg, 80);
      expect(plan.phases.single.weeks, 13);
      expect(plan.targetKg, 80);
      expect(plan.startKg, 86.4);
      expect(plan.kind, PhaseKind.cut);
    });

    test('diet breaks come after every stretch of cutting', () {
      final plan = _cut(breaks: true).toPlan();
      expect(
        [for (final p in plan.phases) (p.kind, p.weeks)],
        [
          (PhaseKind.cut, breakEveryWeeks),
          (PhaseKind.maintain, breakWeeks),
          (PhaseKind.cut, breakEveryWeeks),
          (PhaseKind.maintain, breakWeeks),
          (PhaseKind.cut, 1),
        ],
      );
      expect(plan.phases.last.untilKg, 80);
      expect(plan.kind, PhaseKind.cut);
      expect(plan.weightAt(plan.phases.length), closeTo(80, 0.01));
    });

    test('a bulk climbs and maintenance holds for its weeks', () {
      final bulk = GoalDraft(
        kind: PhaseKind.bulk,
        startKg: 80,
        targetKg: 82,
        start: _start,
        paceKg: 0.25,
      ).toPlan();
      expect(bulk.phases.single.kgPerWeek, 0.25);
      expect(bulk.phases.single.weeks, 8);

      final hold = GoalDraft(
        kind: PhaseKind.maintain,
        startKg: 80,
        start: _start,
        maintainWeeks: 12,
      ).toPlan();
      expect(hold.phases.single.kind, PhaseKind.maintain);
      expect(hold.phases.single.weeks, 12);
      expect(hold.targetKg, isNull);
      expect(hold.kind, PhaseKind.maintain);
    });

    test('a target on the wrong side is a problem', () {
      expect(_cut().problem, isNull);
      expect(_cut().copyWith(targetKg: () => 90).problem, isNotNull);
      expect(_cut().copyWith(targetKg: () => null).problem, isNotNull);
      expect(_cut().copyWith(kind: PhaseKind.bulk).problem, contains('above'));
      expect(
        _cut().copyWith(kind: PhaseKind.maintain, targetKg: () => null).problem,
        isNull,
      );
    });

    test('a running plan reads back as its draft', () {
      final draft = GoalDraft.of(_cut(breaks: true).toPlan(), 85);
      expect(draft.kind, PhaseKind.cut);
      expect(draft.paceKg, 0.5);
      expect(draft.breaks, isTrue);
      expect(draft.targetKg, 80);
      expect(draft.start, _start);
    });

    test('plan JSON keeps the target and extensions', () {
      final plan = PhasePlan.fromJson(
        extendedPlan(
          _cut().toPlan(),
          today: DateTime(2027, 1, 4),
          nowKg: 80.8,
        ).toJson(),
      );
      expect(plan.targetKg, 80);
      expect(plan.extensions, 1);
    });
  });

  group('goalStatus', () {
    final plan = _cut().toPlan();

    test('runs until the target or the end', () {
      expect(goalStatus(plan, 84, DateTime(2026, 10, 29)), GoalStatus.running);
      expect(
        goalStatus(plan, 80.05, DateTime(2026, 12, 1)),
        GoalStatus.reached,
      );
      expect(goalStatus(plan, 79.2, DateTime(2026, 12, 1)), GoalStatus.reached);
      expect(goalStatus(plan, 80.8, plan.end), GoalStatus.ended);
    });

    test('a maintenance goal ends on its last day', () {
      final hold = GoalDraft(
        kind: PhaseKind.maintain,
        startKg: 80,
        start: _start,
        maintainWeeks: 4,
      ).toPlan();
      expect(goalStatus(hold, 81, DateTime(2026, 11, 1)), GoalStatus.running);
      expect(goalStatus(hold, 81, DateTime(2026, 11, 2)), GoalStatus.ended);
    });
  });

  group('extendedPlan', () {
    test('an ended cut goes on until its target from now', () {
      final plan = _cut().toPlan();
      final extended = extendedPlan(plan, today: plan.end, nowKg: 80.8);
      expect(extended.phases, hasLength(2));
      expect(extended.phases.last.untilKg, 80);
      expect(extended.phases.last.weeks, 2);
      expect(extended.startOf(1), plan.end);
      expect(extended.extensions, 1);
    });

    test('reached early, the running phase ends this week', () {
      final plan = _cut().toPlan();
      final extended = extendedPlan(
        plan,
        today: DateTime(2026, 12, 2),
        nowKg: 80,
        untilKg: 78,
        breakFirst: true,
      );
      expect(
        [for (final p in extended.phases) (p.kind, p.weeks)],
        [
          (PhaseKind.cut, 9),
          (PhaseKind.maintain, breakWeeks),
          (PhaseKind.cut, 4),
        ],
      );
      expect(extended.targetKg, 78);
    });

    test('for more weeks, at the same pace, with no end weight', () {
      final plan = _cut().toPlan();
      final extended = extendedPlan(
        plan,
        today: plan.end,
        nowKg: 80.8,
        weeks: 3,
      );
      expect(extended.phases.last.weeks, 3);
      expect(extended.phases.last.untilKg, isNull);
      expect(extended.phases.last.kgPerWeek, -0.5);
      expect(extended.targetKg, 80);
    });

    test('a reached goal run on for weeks aims at no weight', () {
      final extended = extendedPlan(
        _cut().toPlan(),
        today: DateTime(2026, 12, 2),
        nowKg: 79.9,
        weeks: 4,
      );
      expect(extended.targetKg, isNull);
      expect(
        goalStatus(extended, 79.9, DateTime(2026, 12, 3)),
        GoalStatus.running,
      );
    });

    test('a plan over for weeks holds maintenance until now', () {
      final plan = _cut().toPlan();
      final extended = extendedPlan(
        plan,
        today: DateTime(plan.end.year, plan.end.month, plan.end.day + 15),
        nowKg: 81,
      );
      expect(extended.phases[1].kind, PhaseKind.maintain);
      expect(extended.phases[1].weeks, 2);
    });
  });

  group('editedPlan', () {
    // Cut from Oct 5, reached early on Dec 2 and extended to 78 kg after a
    // diet break.
    final extended = extendedPlan(
      _cut().toPlan(),
      today: DateTime(2026, 12, 2),
      nowKg: 80,
      untilKg: 78,
      breakFirst: true,
    );

    test('begun, the weeks so far stay and the rest follows the draft', () {
      final draft = GoalDraft.of(extended, 79.6).copyWith(paceKg: 0.25);
      final edited = editedPlan(
        extended,
        draft,
        today: DateTime(2026, 12, 23),
        nowKg: 79.6,
      );
      expect(
        [for (final p in edited.phases) (p.kind, p.weeks)],
        [
          (PhaseKind.cut, 9),
          (PhaseKind.maintain, breakWeeks),
          (PhaseKind.cut, 1),
          (PhaseKind.cut, 7),
        ],
      );
      expect(edited.phases.last.kgPerWeek, -0.25);
      expect(edited.phases.last.untilKg, 78);
      expect(edited.start, _start);
      expect(edited.startKg, 86.4);
      expect(edited.extensions, 1);
    });

    test('not begun, the draft plans it, extensions kept', () {
      final later = PhasePlan.fromJson({
        ...extended.toJson(),
        'start': DateTime(2027, 1, 4).toIso8601String(),
      });
      final edited = editedPlan(
        later,
        GoalDraft.of(later, 86),
        today: DateTime(2026, 12, 23),
        nowKg: 86,
      );
      expect(edited.start, DateTime(2027, 1, 4));
      expect(edited.extensions, 1);
    });

    test('an extended cut reads back with its pace, no regular breaks', () {
      final draft = GoalDraft.of(
        extendedPlan(
          GoalDraft(
            kind: PhaseKind.cut,
            startKg: 86.4,
            targetKg: 80,
            start: _start,
            paceKg: 0.25,
          ).toPlan(),
          today: DateTime(2026, 12, 2),
          nowKg: 84,
          breakFirst: true,
        ),
        84,
      );
      expect(draft.breaks, isFalse);
      expect(draft.paceKg, 0.25);
      expect(GoalDraft.of(_cut(breaks: true).toPlan(), 85).breaks, isTrue);
    });

    test('a plan over for more than a year holds maintenance until now', () {
      final plan = _cut().toPlan();
      final today = DateTime(plan.end.year + 2, plan.end.month, plan.end.day);
      final extended = extendedPlan(plan, today: today, nowKg: 82);
      expect(extended.phases[1].weeks, greaterThan(100));
      expect(extended.indexOn(today), 2);
    });
  });

  test('kindOn reads the plan, then the completed goals', () {
    final plan = _cut(breaks: true).toPlan();
    final history = [
      GoalRecord(
        kind: PhaseKind.bulk,
        start: DateTime(2026, 6, 1),
        end: DateTime(2026, 8, 30),
        startKg: 81.2,
        endKg: 85.9,
        targetKg: 86,
      ),
    ];
    expect(kindOn(DateTime(2026, 7, 1), plan, history), PhaseKind.bulk);
    expect(kindOn(DateTime(2026, 9, 15), plan, history), isNull);
    expect(kindOn(DateTime(2026, 10, 5), plan, history), PhaseKind.cut);
    expect(kindOn(DateTime(2026, 11, 16), plan, history), PhaseKind.maintain);
    expect(kindOn(DateTime(2027, 6, 1), plan, history), PhaseKind.maintain);
  });

  group('GoalActions', () {
    test('start saves the pace, target and plan', () async {
      final store = _MemoryPhases();
      final saved = <(double?, double?)>[];
      final actions = GoalActions(
        store: store,
        save: (pace, target) async {
          saved.add((pace, target));
          return true;
        },
        clock: () => DateTime(2026, 10, 6),
      );
      final plan = _cut().toPlan();
      expect(await actions.start(plan), isTrue);
      expect(saved, [(-0.5, 80.0)]);
      expect(store.saved, same(plan));
    });

    test('a plan starting later leaves the pace', () async {
      final saved = <(double?, double?)>[];
      await GoalActions(
        store: _MemoryPhases(),
        save: (pace, target) async {
          saved.add((pace, target));
          return true;
        },
        clock: () => DateTime(2026, 10, 1),
      ).start(_cut().toPlan());
      expect(saved, [(null, 80.0)]);
    });

    test('complete keeps the goal and holds maintenance', () async {
      final plan = _cut().toPlan();
      final store = _MemoryPhases(plan);
      final saved = <(double?, double?)>[];
      final actions = GoalActions(
        store: store,
        save: (pace, target) async {
          saved.add((pace, target));
          return true;
        },
        clock: () => DateTime(2027, 1, 2, 9),
      );
      expect(await actions.complete(plan, 80), isTrue);
      expect(saved, [(0.0, null)]);
      expect(store.saved, isNull);
      final record = store.goals.single;
      expect(record.kind, PhaseKind.cut);
      expect(record.start, _start);
      expect(record.end, DateTime(2027, 1, 2));
      expect((record.startKg, record.endKg, record.targetKg), (86.4, 80, 80));
      expect(record.weeks, 13);
      expect(GoalRecord.fromJson(record.toJson()).toJson(), record.toJson());
    });

    test('a dropped save changes nothing', () async {
      final plan = _cut().toPlan();
      final store = _MemoryPhases(plan);
      final actions = GoalActions(store: store, save: (_, _) async => false);
      expect(await actions.complete(plan, 80), isFalse);
      expect(store.saved, same(plan));
      expect(store.goals, isEmpty);
    });

    test('a new goal keeps the one it replaces', () async {
      final old = _cut().toPlan();
      final store = _MemoryPhases(old);
      await GoalActions(
        store: store,
        save: (_, _) async => true,
        clock: () => DateTime(2026, 11, 2),
      ).start(
        GoalDraft(
          kind: PhaseKind.maintain,
          startKg: 84,
          start: DateTime(2026, 11, 2),
        ).toPlan(),
        replacing: old,
        nowKg: 84,
      );
      expect(store.goals.single.end, DateTime(2026, 11, 2));
      expect(store.saved!.kind, PhaseKind.maintain);
    });
  });

  group('upcoming goals', () {
    final cut = _cut().toPlan();
    final maintain = GoalDraft(
      kind: PhaseKind.maintain,
      startKg: 70,
      start: DateTime(2020),
      paceKg: 0,
      breaks: false,
      maintainWeeks: 4,
    ).toPlan();
    final bulk = GoalDraft(
      kind: PhaseKind.bulk,
      startKg: 70,
      targetKg: 84,
      start: DateTime(2020),
      paceKg: 0.25,
      breaks: false,
    ).toPlan();

    test('each starts as the one before ends, from its weight', () {
      final queue = reflowed(
        cut,
        [maintain, bulk],
        from: DateTime(2026, 10, 29),
        fromKg: 85,
      );
      expect(queue[0].start, cut.end);
      expect(queue[0].startKg, 80);
      expect(queue[0].phases.single.weeks, 4);
      expect(queue[1].start, queue[0].end);
      expect(queue[1].startKg, 80);
      // 4 kg at 0.25 a week.
      expect(queue[1].phases.single.weeks, 16);
      expect(queue[1].targetKg, 84);
    });

    test('with none running, the first starts on the day given', () {
      final queue = reflowed(
        null,
        [bulk],
        from: DateTime(2026, 10, 29, 15),
        fromKg: 82,
      );
      expect(queue.single.start, DateTime(2026, 10, 29));
      expect(queue.single.phases.single.weeks, 8);
    });

    test("the calendar has each upcoming goal's days", () {
      final queue = reflowed(
        cut,
        [maintain, bulk],
        from: DateTime(2026, 10, 29),
        fromKg: 85,
      );
      PhaseKind? on(DateTime d) => kindOn(d, cut, [], upcoming: queue);
      expect(on(cut.end.subtract(const Duration(days: 1))), PhaseKind.cut);
      expect(on(cut.end), PhaseKind.maintain);
      expect(on(queue[1].start), PhaseKind.bulk);
      expect(on(queue[1].end), PhaseKind.maintain);
    });
  });
}
