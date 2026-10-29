import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/body_weight_unit_entity.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/fork/adaptive/goal_plan.dart';
import 'package:opennutritracker/fork/adaptive/goal_plan_card.dart'
    show paceChanges;
import 'package:opennutritracker/fork/goal/goal_progress.dart';
import 'package:opennutritracker/fork/goal/goal_progress_page.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:provider/provider.dart';

final t = DateTime.now();
final today = DateTime(t.year, t.month, t.day);

GoalPlanInputs inputs(List<double> trend, {double? targetKg}) => GoalPlanInputs(
  pastTrendKg: trend,
  trendKgPerDay: null,
  expenditureKcal: 2500,
  bodyFatPercent: 20,
  targetWeightKg: targetKg,
  paceKgPerWeek: -0.5,
);

Future<void> pumpGoal(
  WidgetTester tester,
  GoalState goal, {
  Future<GoalState> Function()? loadGoal,
  GoalCalories calories = (goalKcal: null, meanKcal: null),
}) async {
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
        home: GoalProgressPage(
          unit: BodyWeightUnit.kg,
          loadGoal: loadGoal ?? () async => goal,
          loadCalories: () async => calories,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('no weigh-in: asks for one', (tester) async {
    await pumpGoal(tester, (inputs: null, progress: null));
    expect(find.text('Weigh in to see your progress.'), findsOneWidget);
  });

  testWidgets('no goal: offers to plan one', (tester) async {
    await pumpGoal(tester, (inputs: inputs([82]), progress: null));
    expect(find.text('No goal'), findsOneWidget);
    expect(find.text('Plan a goal'), findsOneWidget);
    expect(find.text('Pace'), findsNothing);
  });

  testWidgets('a saved goal reloads the page', (tester) async {
    GoalState goal = (inputs: inputs([82]), progress: null);
    await pumpGoal(tester, goal, loadGoal: () async => goal);
    expect(find.text('Plan a goal'), findsOneWidget);
    goal = (inputs: null, progress: null);
    paceChanges.value++;
    await tester.pumpAndSettle();
    expect(find.text('Weigh in to see your progress.'), findsOneWidget);
  });

  testWidgets('a goal: how far, behind the plan, pace, arrival, milestones', (
    tester,
  ) async {
    // 70 days in, 90 → 88: the plan had 85.
    final trend = [for (var i = 0; i <= 70; i++) 90 - 2 / 70 * i];
    final start = GoalStart(
      date: today.subtract(const Duration(days: 70)),
      kg: 90,
      targetKg: 80,
    );
    await pumpGoal(
      tester,
      (
        inputs: inputs(trend, targetKg: 80),
        progress: GoalProgress(
          start: start,
          nowKg: trend.last,
          paceKgPerWeek: -0.5,
          trend: trend,
          today: today,
        ),
      ),
      calories: (goalKcal: 2000, meanKcal: 2150),
    );

    expect(find.text('Trend now'), findsOneWidget);
    expect(
      find.bySemanticsLabel(
        RegExp('^20 percent there, 8.0 kg to go.*3.0 kg behind the plan'),
      ),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(find.text('Since the start'), 200);
    expect(find.text('Last 30 days'), findsOneWidget);
    expect(find.text('-0.20 kg a week'), findsNWidgets(2));
    await tester.scrollUntilVisible(find.text('Calorie goal now'), 200);
    expect(find.text('Since the start'), findsWidgets);
    expect(find.text('in 10 weeks'), findsOneWidget);
    expect(find.text('you averaged 2150 kcal over 30 days'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Milestones, at your last 30 days’ pace'),
      200,
    );
    await tester.scrollUntilVisible(find.text('Plan a goal'), 200);
    expect(find.textContaining('Reached'), findsWidgets);
  });

  test('a chart day is a calendar day, 23 hours apart or 25', () {
    // Local midnights either side of a daylight saving change: a day
    // short of 24 hours, and one over.
    final origin = DateTime(2026, 3, 28, 1);
    expect(chartDay(origin, DateTime(2026, 3, 29)), 1);
    expect(chartDay(DateTime(2026, 10, 24), DateTime(2026, 10, 26, 1)), 2);
    expect(chartDay(origin, origin), 0);
  });
}
