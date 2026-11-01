import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/body_weight_unit_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_gender_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_pal_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_weight_goal_entity.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_store.dart';
import 'package:opennutritracker/fork/goal/goal_actions.dart';
import 'package:opennutritracker/fork/goal/goal_card.dart';
import 'package:opennutritracker/fork/goal/goal_planner.dart';
import 'package:opennutritracker/fork/goal/goal_progress.dart';
import 'package:opennutritracker/fork/goal/planner_screen.dart';
import 'package:opennutritracker/fork/phases/phases.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:provider/provider.dart';

class _MemoryPhases extends PhaseStore {
  PhasePlan? saved;
  final queue = <PhasePlan>[];
  final goals = <GoalRecord>[];

  _MemoryPhases([this.saved]);

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

/// The adaptive box's keys in memory.
class _MemoryAdaptive extends Fake implements AdaptiveStore {
  final keys = <String, Object?>{};

  @override
  Future<Object?> readKey(String key) async => keys[key];

  @override
  Future<void> writeKey(String key, Object? value) async => keys[key] = value;
}

Future<void> _pump(WidgetTester tester, Widget home) async {
  // Tall, so a list's whole length is built and "nothing there" means it.
  tester.view.physicalSize = const Size(800, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ChangeNotifierProvider(
      create: (_) => EnergyUnitProvider(usesKilojoules: false),
      child: MaterialApp(
        localizationsDelegates: const [
          S.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: S.supportedLocales,
        home: home,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _next(WidgetTester tester) async {
  await tester.tap(find.text('Next'));
  await tester.pumpAndSettle();
}

Finder _start(String id) => find.byWidgetPredicate(
  (w) => w is Semantics && w.properties.identifier == 'goal-start-$id',
);

DateTime _dayOnly(DateTime t) => DateTime(t.year, t.month, t.day);

DateTime _inDays(int days) {
  final t = DateTime.now();
  return DateTime(t.year, t.month, t.day + days);
}

PhasePlan _cutFrom(DateTime start) => GoalDraft(
  kind: PhaseKind.cut,
  startKg: 86.4,
  targetKg: 80,
  start: start,
).toPlan();

PlannerSetup _setup({
  double nowKg = 86.4,
  double expenditure = 2600,
  PhasePlan? running,
  double? kcalFloor,
}) => PlannerSetup(
  nowKg: nowKg,
  unit: BodyWeightUnit.kg,
  expenditureKcal: expenditure,
  bodyFatPercent: 22,
  running: running,
  kcalFloor: kcalFloor,
);

void main() {
  group('F1: the kept start', () {
    testWidgets('a new goal cannot start on the running goal\'s day', (
      tester,
    ) async {
      final running = _cutFrom(_inDays(-21));
      await _pump(
        tester,
        GoalPlannerScreen(
          setup: _setup(running: running),
          draft: GoalDraft.fresh(86.4, DateTime.now(), targetKg: 80),
          onStart: (_) async => true,
        ),
      );
      expect(_start('today'), findsOneWidget);
      expect(_start('kept'), findsNothing);
    });

    testWidgets('a goal edited before it begins keeps its day on offer', (
      tester,
    ) async {
      // Far enough off to be neither today nor next Monday.
      final running = _cutFrom(_inDays(10));
      await _pump(
        tester,
        GoalPlannerScreen(
          setup: _setup(running: running),
          draft: GoalDraft.of(running, 86.4),
          editing: running,
          onStart: (_) async => true,
        ),
      );
      expect(_start('kept'), findsOneWidget);
    });
  });

  group('F2: a begun maintenance goal\'s length', () {
    final start = DateTime(2026, 10, 5);
    final hold = GoalDraft(
      kind: PhaseKind.maintain,
      startKg: 80,
      start: start,
      maintainWeeks: 8,
    ).toPlan();
    // In its third week.
    final today = DateTime(2026, 10, 20);

    test('saved unchanged, the plan stays as it is', () {
      final edited = editedPlan(
        hold,
        GoalDraft.of(hold, 80.5).copyWith(startKg: 80.5),
        today: today,
        nowKg: 80.5,
      );
      expect(edited.end, hold.end);
      expect(edited.phases.length, 1);
      expect(edited.startKg, 80);
    });

    test('the length chosen is the whole goal\'s', () {
      final edited = editedPlan(
        hold,
        GoalDraft.of(hold, 80).copyWith(maintainWeeks: 4),
        today: today,
        nowKg: 80,
      );
      expect(edited.phases.fold(0, (w, p) => w + p.weeks), 4);
      expect(edited.end, DateTime(2026, 11, 2));
    });

    test('shorter than the weeks so far: one more week', () {
      final edited = editedPlan(
        hold,
        GoalDraft.of(hold, 80).copyWith(maintainWeeks: 2),
        today: today,
        nowKg: 80,
      );
      expect(edited.phases.fold(0, (w, p) => w + p.weeks), 4);
    });

    testWidgets('the screen\'s dates and title follow the same result', (
      tester,
    ) async {
      PhasePlan? saved;
      await _pump(
        tester,
        GoalPlannerScreen(
          setup: _setup(nowKg: 80, running: hold),
          draft: GoalDraft.of(hold, 80).copyWith(startKg: 80),
          editing: hold,
          today: today,
          onStart: (plan) async {
            saved = plan;
            return true;
          },
        ),
      );
      await _next(tester);
      // Two and four weeks: three kept, then one, so the last day is Nov 1.
      expect(find.textContaining(RegExp(r'Until Nov 1\b')), findsNWidgets(2));
      // Eight weeks, unchanged.
      expect(find.textContaining('Until Nov 29'), findsOneWidget);
      for (var i = 0; i < 4; i++) {
        await _next(tester);
      }
      expect(find.text('Maintain for 8 weeks'), findsOneWidget);
      await tester.tap(find.text('Save plan'));
      await tester.pumpAndSettle();
      expect(saved, same(hold));
    });
  });

  group('F3: a goal that never began', () {
    final today = DateTime(2026, 10, 20);
    final later = GoalDraft(
      kind: PhaseKind.cut,
      startKg: 86,
      targetKg: 80,
      start: DateTime(2026, 11, 2),
    ).toPlan();
    GoalActions actions(PhaseStore store) => GoalActions(
      store: store,
      save: (_, _) async => true,
      clock: () => today,
    );

    test('completed, it leaves no record', () async {
      final store = _MemoryPhases(later);
      expect(await actions(store).complete(later, 86), isTrue);
      expect(store.goals, isEmpty);
      expect(store.saved, isNull);
    });

    test('replaced, it leaves no record', () async {
      final store = _MemoryPhases(later);
      final next = _cutFrom(today);
      expect(
        await actions(store).start(next, replacing: later, nowKg: 86),
        isTrue,
      );
      expect(store.goals, isEmpty);
      expect(store.saved, same(next));
    });

    test('begun, even today, it is kept', () async {
      final store = _MemoryPhases();
      final begun = _cutFrom(today);
      await actions(store).complete(begun, 86);
      expect(store.goals.single.start, today);
    });
  });

  testWidgets('F4: another kind over a begun goal says it starts today', (
    tester,
  ) async {
    final running = _cutFrom(DateTime(2026, 10, 5));
    PhasePlan? saved;
    final today = DateTime(2026, 11, 18);
    await _pump(
      tester,
      GoalPlannerScreen(
        setup: _setup(nowKg: 84, running: running),
        draft: GoalDraft.of(running, 84).copyWith(startKg: 84),
        editing: running,
        today: today,
        onStart: (plan) async {
          saved = plan;
          return true;
        },
      ),
    );
    await tester.tap(find.text('Maintain'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Starts today, replacing the cut.'),
      100,
      scrollable: find.byType(Scrollable).first,
    );
    expect(_start('today'), findsNothing);
    expect(_start('monday'), findsNothing);
    expect(_start('kept'), findsNothing);
    await _next(tester);
    // The length's dates run from today too.
    expect(find.textContaining(RegExp(r'Until Dec 1\b')), findsOneWidget);
    for (var i = 0; i < 4; i++) {
      await _next(tester);
    }
    await tester.tap(find.text('Save plan'));
    await tester.pumpAndSettle();
    expect(saved!.start, today);
  });

  group('F5 and F15: milestones', () {
    final today = DateTime(2026, 10, 26);
    DateTime ago(int days) =>
        DateTime(today.year, today.month, today.day - days);

    test('a milestone passed before the goal is dated from the goal', () {
      // Down past 85 then back up, before a goal begun 10 days ago at 87.
      final trend = [
        for (var i = 0; i < 20; i++) 84.0,
        for (var i = 0; i <= 10; i++) 87 - 0.25 * i,
      ];
      final p = GoalProgress(
        start: GoalStart(date: ago(10), kg: 87, targetKg: 80),
        nowKg: trend.last,
        paceKgPerWeek: -0.5,
        trend: trend,
        today: today,
      );
      final at85 = p.milestones(1).firstWhere((m) => m.kg == 85);
      expect(at85.reached, isTrue);
      // 87 - 0.25 * 8 = 85.
      expect(at85.on, ago(2));
    });

    test('the target is ticked when the page says it is reached', () {
      final p = GoalProgress(
        start: GoalStart(date: ago(10), kg: 82, targetKg: 80),
        nowKg: 80.05,
        paceKgPerWeek: -0.5,
        trend: [for (var i = 0; i <= 10; i++) 82 - 0.195 * i],
        today: today,
      );
      expect(p.reached, isTrue);
      expect(p.milestones(1).last.kg, 80);
      expect(p.milestones(1).last.reached, isTrue);
    });

    test('so when gaining', () {
      final p = GoalProgress(
        start: GoalStart(date: ago(10), kg: 60, targetKg: 62),
        nowKg: 61.95,
        paceKgPerWeek: 0.25,
        trend: [for (var i = 0; i <= 10; i++) 60 + 0.195 * i],
        today: today,
      );
      expect(p.reached, isTrue);
      expect(p.milestones(1).last.reached, isTrue);
    });
  });

  group('F6: reached goes by the goal\'s kind', () {
    final today = DateTime(2026, 11, 2);

    test('a cut edited to a target above its first start', () {
      // Began at 80, gained to 90, and the cut now aims at 85.
      final plan = PhasePlan(
        start: DateTime(2026, 10, 5),
        startKg: 80,
        targetKg: 85,
        phases: const [
          DietPhase(kind: PhaseKind.cut, kgPerWeek: -0.5, weeks: 10),
        ],
      );
      expect(goalStatus(plan, 90, today), GoalStatus.running);
      expect(goalStatus(plan, 84.5, today), GoalStatus.reached);
    });

    test('a bulk edited to a target below its first start', () {
      final plan = PhasePlan(
        start: DateTime(2026, 10, 5),
        startKg: 80,
        targetKg: 75,
        phases: const [
          DietPhase(kind: PhaseKind.bulk, kgPerWeek: 0.25, weeks: 10),
        ],
      );
      expect(goalStatus(plan, 70, today), GoalStatus.running);
      expect(goalStatus(plan, 76, today), GoalStatus.reached);
    });

    test('a maintenance plan with a target goes by its start', () {
      final plan = PhasePlan(
        start: DateTime(2026, 10, 5),
        startKg: 80,
        targetKg: 82,
        phases: const [
          DietPhase(kind: PhaseKind.maintain, kgPerWeek: 0, weeks: 10),
        ],
      );
      expect(goalStatus(plan, 81, today), GoalStatus.running);
      expect(goalStatus(plan, 83, today), GoalStatus.reached);
    });
  });

  group('F7: a goal\'s start ends with it', () {
    final today = DateTime(2026, 10, 20);
    final goal = _cutFrom(DateTime(2026, 10, 5));
    final trend = [for (var i = 0; i < 40; i++) 90 - 0.1 * i];
    late _MemoryAdaptive box;
    late GoalStartStore starts;
    late _MemoryPhases store;
    late Object? seenInSave;
    var saves = true;

    GoalActions actions() => GoalActions(
      store: store,
      starts: starts,
      clock: () => today,
      save: (_, _) async {
        seenInSave = box.keys[GoalStartStore.key];
        return saves;
      },
    );

    /// The start a new goal to the same target would get.
    Future<GoalStart> resolved() async => resolveGoalStart(
      stored: await starts.read(),
      targetKg: 80,
      paceKgPerWeek: -0.5,
      trend: trend,
      today: today,
      backdate: await box.readKey(GoalStartStore.noTargetKey) != true,
    );

    setUp(() async {
      box = _MemoryAdaptive();
      starts = GoalStartStore(box);
      store = _MemoryPhases(goal);
      seenInSave = 'not saved';
      saves = true;
      await starts.save(
        GoalStart(
          date: DateTime(2026, 10, 5),
          kg: 86.4,
          targetKg: 80,
          paceKgPerWeek: -0.5,
        ),
      );
    });

    test('completed: the next to the same target starts today', () async {
      expect(await actions().complete(goal, 84), isTrue);
      expect(seenInSave, isNull);
      final next = await resolved();
      expect(next.date, today);
      expect(next.kg, trend.last);
    });

    test('replaced: the same', () async {
      await actions().start(_cutFrom(today), replacing: goal, nowKg: 84);
      expect(seenInSave, isNull);
      expect((await resolved()).date, today);
    });

    test('replaced by a queued goal on its day: the same', () async {
      store.queue.add(_cutFrom(today));
      expect(await actions().startNextIfDue(84), isTrue);
      expect(seenInSave, isNull);
      expect((await resolved()).date, today);
    });

    test('removed for a queued goal, Undo finds the start', () async {
      store.queue.add(_cutFrom(today));
      final a = actions();
      final was = await a.snapshot();
      expect(await a.remove(84), isTrue);
      await starts.save(
        GoalStart(date: today, kg: 84, targetKg: 75, paceKgPerWeek: -0.5),
      );
      expect(await a.restore(was), isTrue);
      expect((await starts.read())!.date, DateTime(2026, 10, 5));
    });

    test('a save that fails leaves the goal its start', () async {
      saves = false;
      expect(await actions().complete(goal, 84), isFalse);
      expect((await starts.read())!.date, DateTime(2026, 10, 5));
    });

    test('edited, the goal keeps its start', () async {
      await actions().start(goal);
      expect((await starts.read())!.date, DateTime(2026, 10, 5));
    });

    test('removed, Undo finds the start; a new goal after does not', () async {
      final a = actions();
      final was = await a.snapshot();
      expect(await a.remove(84), isTrue);
      expect(await a.restore(was), isTrue);
      expect((await starts.read())!.date, DateTime(2026, 10, 5));

      expect(await a.remove(84), isTrue);
      await a.start(_cutFrom(today), nowKg: 84);
      expect((await resolved()).date, today);
    });
  });

  group('F9: the last day is shown', () {
    final plan = _cutFrom(DateTime(2026, 10, 5));

    test('the day before the end', () {
      expect(plan.end, DateTime(2027, 1, 4));
      expect(plan.lastDay, DateTime(2027, 1, 3));
    });

    testWidgets('on the goal card', (tester) async {
      await _pump(
        tester,
        Scaffold(
          body: GoalCard(unit: BodyWeightUnit.kg, load: () async => plan),
        ),
      );
      expect(find.textContaining('until Jan 3, 2027'), findsOneWidget);
    });
  });

  group('F10: the pace in calories', () {
    tearDown(() => AdaptiveStore.settings.value = const AdaptiveSettings());

    Future<void> pumpAtTarget(WidgetTester tester) async {
      await _pump(
        tester,
        GoalPlannerScreen(
          setup: _setup(),
          draft: GoalDraft.fresh(86.4, DateTime.now(), targetKg: 80),
          onStart: (_) async => true,
          store: _Settings(),
        ),
      );
    }

    testWidgets('on Adaptive: the check-in\'s kcal a kg', (tester) async {
      const settings = AdaptiveSettings(
        adaptiveTarget: true,
        flatEnergy: false,
      );
      AdaptiveStore.settings.value = settings;
      final perKg = settings.expenditure.kcalPerKgAt(86.4, 22);
      expect(perKg, isNot(AdaptiveSettings.commonKcalPerKg));
      final shift = 0.5 * perKg / 7;
      await pumpAtTarget(tester);
      await _next(tester);
      expect(
        find.textContaining('about ${shift.round()} kcal under'),
        findsOneWidget,
      );
      await _next(tester);
      await _next(tester);
      expect(
        find.text('about ${(2600 - shift).round()} kcal a day'),
        findsOneWidget,
      );
    });

    testWidgets('on Formula: 1100 a day for a kg a week, still', (
      tester,
    ) async {
      await pumpAtTarget(tester);
      await _next(tester);
      expect(find.textContaining('about 550 kcal under'), findsOneWidget);
    });
  });

  group('F11: warnings on any pace', () {
    tearDown(() => AdaptiveStore.settings.value = const AdaptiveSettings());

    Future<void> pumpPace(
      WidgetTester tester, {
      double? kcalFloor,
      double expenditure = 2600,
    }) async {
      await _pump(
        tester,
        GoalPlannerScreen(
          setup: _setup(
            nowKg: 60,
            expenditure: expenditure,
            kcalFloor: kcalFloor,
          ),
          draft: GoalDraft.fresh(60, DateTime.now(), targetKg: 55),
          onStart: (_) async => true,
        ),
      );
      await _next(tester);
    }

    testWidgets('a preset over 1% a week says so', (tester) async {
      await pumpPace(tester);
      expect(find.textContaining('Over 1% a week'), findsNothing);
      await tester.tap(find.textContaining('Fast ·'));
      await tester.pumpAndSettle();
      // 0.75 of 60 is 1.25%.
      expect(find.textContaining('Over 1% a week'), findsOneWidget);
    });

    testWidgets('a target under the floor warns and does not block', (
      tester,
    ) async {
      await pumpPace(tester, kcalFloor: 1200, expenditure: 1900);
      expect(find.textContaining('recommended as a minimum'), findsNothing);
      await tester.tap(find.textContaining('Fast ·'));
      await tester.pumpAndSettle();
      // 1900 - 825.
      expect(
        find.text(
          'About 1075 kcal a day is below the 1200 kcal a day recommended '
          'as a minimum.',
        ),
        findsOneWidget,
      );
      final next = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Next'),
      );
      expect(next.onPressed, isNotNull);
    });

    testWidgets('a fixed target is the user\'s own: no floor warning', (
      tester,
    ) async {
      AdaptiveStore.settings.value = const AdaptiveSettings(
        fixedTarget: true,
        fixedKcal: 1200,
      );
      await pumpPace(tester, kcalFloor: 1500, expenditure: 1400);
      expect(find.textContaining('recommended as a minimum'), findsNothing);
    });

    test('the setup has the user\'s floor', () {
      final user = UserEntity(
        birthday: DateTime(1990),
        heightCM: 170,
        weightKG: 60,
        gender: UserGenderEntity.female,
        goal: UserWeightGoalEntity.loseWeight,
        pal: UserPALEntity.sedentary,
      );
      expect(PlannerSetup.ofUser(user, BodyWeightUnit.kg).kcalFloor, 1200);
    });
  });

  group('F12: the longest a phase runs', () {
    final start = DateTime(2026, 10, 5);
    // 30 kg at 0.25 a week is 120 weeks.
    final far = GoalDraft(
      kind: PhaseKind.cut,
      startKg: 110,
      targetKg: 80,
      start: start,
      paceKg: 0.25,
    );

    test('the plan stops short and ends where its pace leads', () {
      expect(far.capped, isTrue);
      final plan = far.toPlan();
      expect(plan.phases.single.weeks, 52);
      expect(plan.targetKg, 80);
      expect(endKgOf(plan), closeTo(97, 1e-9));
    });

    test('so with diet breaks', () {
      final plan = far.copyWith(breaks: true).toPlan();
      expect(endKgOf(plan), closeTo(97, 1e-9));
    });

    test('a target in reach ends at the target', () {
      final near = far.copyWith(targetKg: () => 100);
      expect(near.capped, isFalse);
      expect(endKgOf(near.toPlan()), 100);
      // Exactly 52 weeks is in reach.
      final exact = far.copyWith(targetKg: () => 97);
      expect(exact.capped, isFalse);
      expect(endKgOf(exact.toPlan()), 97);
    });

    test('a goal queued after it starts where it really ends', () {
      final next = GoalDraft(
        kind: PhaseKind.maintain,
        startKg: 80,
        start: start,
      ).toPlan();
      expect(
        reflowed(far.toPlan(), [next], fromKg: 110).single.startKg,
        closeTo(97, 1e-9),
      );
    });

    test('after a goal already over, the next starts today', () {
      final over = _cutFrom(DateTime(2026, 1, 5));
      final next = GoalDraft(
        kind: PhaseKind.maintain,
        startKg: 80,
        start: over.end,
      ).toPlan();
      final today = over.end.add(const Duration(days: 21));
      expect(
        reflowed(over, [next], fromKg: 80, today: today).single.start,
        today,
      );
      expect(reflowed(over, [next], fromKg: 80).single.start, over.end);
    });

    testWidgets('the pace and plan steps say so', (tester) async {
      await _pump(
        tester,
        GoalPlannerScreen(
          setup: _setup(nowKg: 110),
          draft: far.copyWith(start: _dayOnly(DateTime.now())),
          onStart: (_) async => true,
        ),
      );
      await _next(tester);
      const text =
          'At this pace it takes over 52 weeks, the longest a phase runs: '
          'about 97.0 kg by then, not 80.0 kg.';
      expect(find.text(text), findsOneWidget);
      for (var i = 0; i < 4; i++) {
        await _next(tester);
      }
      expect(find.text(text), findsOneWidget);
    });

    testWidgets('and not when the target is in reach', (tester) async {
      await _pump(
        tester,
        GoalPlannerScreen(
          setup: _setup(nowKg: 110),
          draft: far
              .copyWith(start: _dayOnly(DateTime.now()))
              .copyWith(targetKg: () => 100),
          onStart: (_) async => true,
        ),
      );
      await _next(tester);
      expect(find.textContaining('the longest a phase runs'), findsNothing);
    });
  });
}

/// Saves to the settings in use, as the store does for the active profile.
class _Settings extends Fake implements AdaptiveStore {
  @override
  Future<void> save(AdaptiveSettings value) async =>
      AdaptiveStore.settings.value = value;
}
