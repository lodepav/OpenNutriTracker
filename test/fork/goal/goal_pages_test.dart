import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/body_weight_unit_entity.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/features/onboarding/domain/entity/user_goal_selection_entity.dart';
import 'package:opennutritracker/fork/goal/completed_goals_page.dart';
import 'package:opennutritracker/fork/goal/goal_actions.dart';
import 'package:opennutritracker/fork/goal/goal_plan_view.dart';
import 'package:opennutritracker/fork/goal/goal_planner.dart';
import 'package:opennutritracker/fork/goal/goal_reached.dart';
import 'package:opennutritracker/fork/goal/onboarding_goal.dart';
import 'package:opennutritracker/fork/goal/phase_colors.dart';
import 'package:opennutritracker/fork/goal/planner_screen.dart';
import 'package:opennutritracker/fork/phases/phases.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:provider/provider.dart';

// Monday 5 October 2026.
final _start = DateTime(2026, 10, 5);

PhasePlan _cut({bool breaks = true}) => GoalDraft(
  kind: PhaseKind.cut,
  startKg: 86.4,
  targetKg: 80,
  start: _start,
  paceKg: 0.5,
  breaks: breaks,
).toPlan();

final _bulk = GoalRecord(
  kind: PhaseKind.bulk,
  start: DateTime(2026, 6, 1),
  end: DateTime(2026, 8, 30),
  startKg: 81.2,
  endKg: 85.9,
  targetKg: 86,
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

Future<void> _pump(WidgetTester tester, Widget home) async {
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

void main() {
  testWidgets('the plan: a grid, this week, its phases, the one now', (
    tester,
  ) async {
    await _pump(
      tester,
      Scaffold(
        body: SingleChildScrollView(
          child: GoalPlanSection(
            plan: _cut(),
            history: [_bulk],
            nowKg: 84,
            unit: BodyWeightUnit.kg,
            today: DateTime(2026, 10, 29),
            onChanged: () {},
          ),
        ),
      ),
    );
    expect(find.text('Whole plan'), findsOneWidget);
    expect(find.byType(PlanGrid), findsOneWidget);
    expect(find.text('This week'), findsOneWidget);
    expect(find.text('Next: diet break from Nov 16.'), findsOneWidget);
    expect(find.text('Cut'), findsWidgets);
    expect(find.text('Diet break'), findsNWidgets(2));
    expect(find.text('Cut to 80.0 kg'), findsOneWidget);
    expect(find.text('Now'), findsOneWidget);
    expect(find.text('Edit plan'), findsOneWidget);
    expect(find.text('1 · the last a bulk to 85.9 kg'), findsOneWidget);
    // Not reached, not over: no banner.
    expect(find.text('See how it went'), findsNothing);
  });

  testWidgets('a reached goal offers to see how it went', (tester) async {
    await _pump(
      tester,
      Scaffold(
        body: SingleChildScrollView(
          child: GoalPlanSection(
            plan: _cut(),
            history: const [],
            nowKg: 79.9,
            unit: BodyWeightUnit.kg,
            today: DateTime(2026, 12, 20),
            onChanged: () {},
          ),
        ),
      ),
    );
    expect(find.text('You reached 80.0 kg'), findsOneWidget);
    expect(find.text('See how it went'), findsOneWidget);
    expect(find.text('None yet'), findsOneWidget);
  });

  testWidgets('goal reached: completing it keeps it and holds maintenance', (
    tester,
  ) async {
    final plan = _cut(breaks: false);
    final store = _MemoryPhases(plan);
    final saved = <(double?, double?)>[];
    await _pump(
      tester,
      GoalReachedPage(
        plan: plan,
        nowKg: 79.9,
        unit: BodyWeightUnit.kg,
        today: DateTime(2027, 1, 4),
        load: (_) async => GoalRun(
          trend: [for (var i = 0; i < 91; i++) 86.4 - 6.5 * i / 90],
          first: _start,
          meanKcal: 2010,
          loggedShare: 0.92,
          onTargetShare: 0.8,
          expenditureKcal: 2560,
        ),
        actions: GoalActions(
          store: store,
          save: (pace, target) async {
            saved.add((pace, target));
            return true;
          },
          clock: () => DateTime(2027, 1, 4),
        ),
      ),
    );
    expect(find.text('Cut to 80.0 kg: done'), findsOneWidget);
    expect(find.text('-6.5 kg'), findsOneWidget);
    expect(find.text('92%'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Continue'), 200);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(saved, [(0.0, null)]);
    expect(store.saved, isNull);
    expect(store.goals.single.endKg, 79.9);
  });

  testWidgets('an ended goal extends until its target', (tester) async {
    final plan = _cut(breaks: false);
    final store = _MemoryPhases(plan);
    await _pump(
      tester,
      Scaffold(
        body: ExtendSheet(
          plan: plan,
          nowKg: 80.8,
          unit: BodyWeightUnit.kg,
          ended: true,
          today: plan.end,
          actions: GoalActions(
            store: store,
            save: (_, _) async => true,
            clock: () => plan.end,
          ),
        ),
      ),
    );
    expect(find.text('Until 80.0 kg'), findsOneWidget);
    expect(find.text('Complete at 80.8 kg'), findsOneWidget);
    await tester.tap(find.text('Extend'));
    await tester.pumpAndSettle();
    expect(store.saved!.extensions, 1);
    expect(store.saved!.phases.last.untilKg, 80);
    expect(store.goals, isEmpty);
  });

  testWidgets('extending for weeks with a diet break first', (tester) async {
    final plan = _cut(breaks: false);
    final store = _MemoryPhases(plan);
    await _pump(
      tester,
      Scaffold(
        body: ExtendSheet(
          plan: plan,
          nowKg: 80,
          unit: BodyWeightUnit.kg,
          ended: false,
          today: DateTime(2026, 12, 2),
          actions: GoalActions(
            store: store,
            save: (_, _) async => true,
            clock: () => DateTime(2026, 12, 2),
          ),
        ),
      ),
    );
    expect(find.textContaining('Until'), findsNothing);
    await tester.tap(find.text('8 weeks'));
    await tester.tap(find.text('A diet break first'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Extend'));
    await tester.pumpAndSettle();
    expect(
      [for (final p in store.saved!.phases) (p.kind, p.weeks)],
      [
        (PhaseKind.cut, 9),
        (PhaseKind.maintain, breakWeeks),
        (PhaseKind.cut, 8),
      ],
    );
  });

  testWidgets('completed goals: each from which day and weight to which', (
    tester,
  ) async {
    final today = DateTime(2026, 10, 29);
    await _pump(
      tester,
      CompletedGoalsPage(
        unit: BodyWeightUnit.kg,
        load: () async => (
          history: [
            GoalRecord(
              kind: PhaseKind.cut,
              start: DateTime(2026, 1, 5),
              end: DateTime(2026, 4, 6),
              startKg: 88,
              endKg: 81.2,
              targetKg: 81,
              extensions: 1,
            ),
            _bulk,
          ],
          running: _cut(),
          trend: [for (var i = 0; i < 300; i++) 85 + (i % 30) / 10],
          today: today,
        ),
      ),
    );
    expect(find.text('2'), findsOneWidget);
    expect(find.text('Running'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Bulk · 13 weeks'), 200);
    expect(find.text('Jun 1, 2026 – Aug 30, 2026'), findsOneWidget);
    expect(find.text('81.2 kg → 85.9 kg · target 86.0 kg'), findsOneWidget);
    expect(find.text('+4.7 kg'), findsWidgets);
    await tester.scrollUntilVisible(
      find.text('Cut · 13 weeks · extended 1×'),
      200,
    );
  });

  test('onboarding starts its plan once the profile is saved', () async {
    final store = _MemoryPhases();
    final actions = GoalActions(store: store, save: (_, _) async => true);
    await OnboardingGoal.save(actions: actions);
    expect(store.saved, isNull);
    final plan = _cut();
    OnboardingGoal.pending.value = plan;
    await OnboardingGoal.save(actions: actions);
    expect(store.saved, same(plan));
    expect(OnboardingGoal.pending.value, isNull);
  });

  testWidgets('the phase bar is drawn as tall as it is', (tester) async {
    await _pump(
      tester,
      Scaffold(
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [PhaseBar(_cut())],
        ),
      ),
    );
    final boxes = find.descendant(
      of: find.byType(PhaseBar),
      matching: find.byType(ColoredBox),
    );
    expect(boxes, findsNWidgets(5));
    expect(tester.getSize(boxes.first).height, 14);
  });

  testWidgets('a custom pace: the three, or a slider when toggled', (
    tester,
  ) async {
    await _pump(
      tester,
      GoalPlannerScreen(
        setup: const PlannerSetup(
          nowKg: 86.4,
          unit: BodyWeightUnit.kg,
          expenditureKcal: 2600,
          bodyFatPercent: 22,
        ),
        draft: GoalDraft.fresh(86.4, _start, targetKg: 80),
        onStart: (_) async => true,
      ),
    );
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Steady · 0.5 kg a week'), findsOneWidget);
    expect(find.byType(Slider), findsNothing);
    await tester.ensureVisible(find.text('Custom pace'));
    await tester.tap(find.text('Custom pace'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byType(Slider),
      100,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byType(Slider), findsOneWidget);
    // Right to the end: 1.5 kg a week, over 1% of 86.4 kg.
    await tester.drag(find.byType(Slider), const Offset(600, 0));
    await tester.pumpAndSettle();
    expect(find.text('1.5 kg a week'), findsOneWidget);
    expect(find.textContaining('Over 1% a week'), findsOneWidget);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 400));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gentle · 0.25 kg a week'));
    await tester.pumpAndSettle();
    expect(find.byType(Slider), findsNothing);
  });

  test('onboarding drops a plan whose goal was changed after', () async {
    final store = _MemoryPhases();
    OnboardingGoal.pending.value = _cut();
    await OnboardingGoal.save(
      chosen: UserGoalSelectionEntity.gainWeigh,
      actions: GoalActions(store: store, save: (_, _) async => true),
    );
    expect(store.saved, isNull);
    expect(OnboardingGoal.pending.value, isNull);
  });

  test('onboarding keeps its plan when the save was dropped', () async {
    final plan = _cut();
    OnboardingGoal.pending.value = plan;
    await OnboardingGoal.save(
      chosen: UserGoalSelectionEntity.loseWeight,
      actions: GoalActions(store: _MemoryPhases(), save: (_, _) async => false),
    );
    expect(OnboardingGoal.pending.value, same(plan));
    OnboardingGoal.pending.value = null;
  });
}
