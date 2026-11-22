import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/body_weight_unit_entity.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/fork/adaptive/goal_plan.dart';
import 'package:opennutritracker/fork/goal/completed_goals_page.dart';
import 'package:opennutritracker/fork/goal/goal_actions.dart';
import 'package:opennutritracker/fork/goal/goal_planner.dart';
import 'package:opennutritracker/fork/goal/goal_progress.dart';
import 'package:opennutritracker/fork/goal/goal_progress_page.dart';
import 'package:opennutritracker/fork/goal/goal_reached.dart';
import 'package:opennutritracker/fork/phases/phases.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:provider/provider.dart';

final _start = DateTime(2026, 10, 5);

PhasePlan _cut() => GoalDraft(
  kind: PhaseKind.cut,
  startKg: 86.4,
  targetKg: 80,
  start: _start,
  paceKg: 0.5,
  breaks: false,
).toPlan();

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

  @override
  Future<List<PhasePlan>> upcoming() async => const [];

  @override
  Future<void> saveUpcoming(List<PhasePlan> plans) async {}
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

GoalReachedPage _reached(DateTime today, {GoalActions? actions}) =>
    GoalReachedPage(
      plan: _cut(),
      nowKg: 79.9,
      unit: BodyWeightUnit.kg,
      today: today,
      load: (_) async => GoalRun(trend: const [], first: _start),
      upcoming: () async => const [],
      actions: actions,
    );

void main() {
  group('Goal progress', () {
    final t = DateTime.now();
    final now = DateTime(t.year, t.month, t.day);

    Future<void> pumpProgress(
      WidgetTester tester, {
      required int daysIn,
      required double kgPerDay,
      PhasePlan? plan,
    }) {
      final trend = [for (var i = 0; i <= daysIn; i++) 86.4 + kgPerDay * i];
      return _pump(
        tester,
        GoalProgressPage(
          unit: BodyWeightUnit.kg,
          loadGoal: () async => (
            inputs: GoalPlanInputs(
              pastTrendKg: trend,
              trendKgPerDay: null,
              expenditureKcal: 2500,
              bodyFatPercent: 20,
              targetWeightKg: 80,
              paceKgPerWeek: -0.5,
            ),
            progress: GoalProgress(
              start: GoalStart(
                date: now.subtract(Duration(days: daysIn)),
                kg: 86.4,
                targetKg: 80,
              ),
              nowKg: trend.last,
              paceKgPerWeek: -0.5,
              trend: trend,
              today: now,
            ),
          ),
          loadCalories: () async => (goalKcal: null, meanKcal: null),
          loadPlans: () async => (
            plan: plan,
            upcoming: const <PhasePlan>[],
            history: const <GoalRecord>[],
          ),
        ),
      );
    }

    testWidgets('day one: too early to tell, no figureless tile', (
      tester,
    ) async {
      await pumpProgress(tester, daysIn: 0, kgPerDay: 0);
      expect(find.text('Too early to tell'), findsOneWidget);
      expect(find.text('On plan'), findsNothing);
      await tester.scrollUntilVisible(find.text('Calorie goal now'), 200);
      expect(find.text('Since the start'), findsNothing);
      expect(find.text('Started today'), findsNothing);
    });

    testWidgets('a month at a third of the plan\'s pace: behind plan', (
      tester,
    ) async {
      // −0.2 kg a week against the plan's −0.5: months late.
      await pumpProgress(tester, daysIn: 30, kgPerDay: -0.2 / 7);
      expect(find.text('Behind plan'), findsOneWidget);
      expect(find.text('On plan'), findsNothing);
    });

    testWidgets('a month at the plan\'s pace: on plan', (tester) async {
      await pumpProgress(tester, daysIn: 30, kgPerDay: -0.5 / 7);
      expect(find.text('On plan'), findsOneWidget);
    });

    testWidgets('diet breaks ahead do not make the plan\'s pace "ahead"', (
      tester,
    ) async {
      // A long cut whose plan ends weeks later for its breaks.
      final plan = GoalDraft(
        kind: PhaseKind.cut,
        startKg: 86.4,
        targetKg: 80,
        start: now.subtract(const Duration(days: 30)),
        paceKg: 0.5,
        breaks: true,
      ).toPlan();
      expect(plan.phases.any((p) => p.kind == PhaseKind.maintain), isTrue);
      await pumpProgress(tester, daysIn: 30, kgPerDay: -0.5 / 7, plan: plan);
      expect(find.text('On plan'), findsOneWidget);
    });
  });

  testWidgets('Goal reached counts a goal under a week in days', (
    tester,
  ) async {
    await _pump(tester, _reached(DateTime(2026, 10, 8)));
    expect(find.text('Oct 5, 2026 – Oct 8, 2026 · 3 days'), findsOneWidget);
    expect(find.text('Days'), findsOneWidget);
    expect(find.text('Weeks'), findsNothing);
  });

  testWidgets('marking it completed says so back where it was opened', (
    tester,
  ) async {
    final today = DateTime(2027, 1, 4);
    final actions = GoalActions(
      store: _MemoryPhases(_cut()),
      save: (_, _) async => true,
      clock: () => today,
    );
    await _pump(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<bool>(
                builder: (_) => _reached(today, actions: actions),
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Open'), findsOneWidget);
    expect(
      find.text('Cut to 80.0 kg completed. Maintaining now.'),
      findsOneWidget,
    );
  });

  testWidgets('completed goals with none completed: one sentence, the legend '
      'only for what is drawn', (tester) async {
    final today = DateTime(2026, 10, 29);
    await _pump(
      tester,
      CompletedGoalsPage(
        unit: BodyWeightUnit.kg,
        load: () async => (
          history: const <GoalRecord>[],
          running: _cut(),
          trend: [for (var i = 0; i < 30; i++) 86.4 - 0.05 * i],
          today: today,
        ),
      ),
    );
    expect(
      find.text('Goals you complete show here, with how long each took.'),
      findsOneWidget,
    );
    expect(find.text('Goals completed'), findsNothing);
    expect(find.text('Weeks in goals'), findsNothing);
    expect(find.text('Cut'), findsOneWidget);
    expect(find.text('Bulk'), findsNothing);
    expect(find.text('Maintenance'), findsNothing);
  });
}
