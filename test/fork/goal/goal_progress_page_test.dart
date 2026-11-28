import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:opennutritracker/core/domain/entity/body_weight_unit_entity.dart';
import 'package:opennutritracker/core/presentation/widgets/app_card.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/fork/adaptive/goal_plan.dart';
import 'package:opennutritracker/fork/adaptive/goal_saving.dart'
    show paceChanges;
import 'package:opennutritracker/fork/goal/goal_progress.dart';
import 'package:opennutritracker/fork/goal/goal_progress_page.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:provider/provider.dart';

import '../../helpers/ux_checks.dart';

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
  BodyWeightUnit unit = BodyWeightUnit.kg,
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
          unit: unit,
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
        RegExp(
          '^Goal, 8.0 kg to go, About .* at your 30-day pace\\. '
          '.*Behind plan',
        ),
      ),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(find.text('Since the start'), 200);
    expect(find.text('Last 30 days'), findsOneWidget);
    expect(find.text('−0.2 kg a week'), findsNWidgets(2));
    await tester.scrollUntilVisible(find.text('Calorie goal now'), 200);
    expect(find.text('Since the start'), findsWidgets);
    expect(find.text('in 10 weeks'), findsOneWidget);
    expect(find.text('you averaged 2150 kcal over 30 days'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Milestones, at your last 30 days’ pace'),
      200,
    );
    // A milestone's weight keeps its unit on its line (G4-12).
    expect(find.textContaining(RegExp('\\d\u00A0kg')), findsWidgets);
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

  testWidgets('the page at 200% text: nothing cut, the targets and contrast', (
    tester,
  ) async {
    await checkScreen(
      tester,
      GoalProgressPage(
        unit: BodyWeightUnit.kg,
        loadGoal: () async => (inputs: inputs([82]), progress: null),
        loadCalories: () async => (goalKcal: null, meanKcal: null),
      ),
    );
  });

  // G4-19: one label, "lb" as the phase rows write it, not upstream's "lbs".
  testWidgets('a pound profile reads lb and one pace format', (tester) async {
    final trend = [for (var i = 0; i <= 70; i++) 90 - 2 / 70 * i];
    await pumpGoal(tester, (
      inputs: inputs(trend, targetKg: 80),
      progress: GoalProgress(
        start: GoalStart(
          date: today.subtract(const Duration(days: 70)),
          kg: 90,
          targetKg: 80,
        ),
        nowKg: trend.last,
        paceKgPerWeek: -0.5,
        trend: trend,
        today: today,
      ),
    ), unit: BodyWeightUnit.lb);
    expect(find.textContaining('lbs', findRichText: true), findsNothing);
    expect(
      find.textContaining(RegExp(r'\blb\b'), findRichText: true),
      findsWidgets,
    );
    await tester.scrollUntilVisible(find.text('Your plan'), 200);
    expect(find.text('−1.1 lb a week'), findsOneWidget);
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('at ${scale}x the chart keys each line, dates its end and '
        'no two dates touch', (tester) async {
      // 30 days in at -0.2 kg a week against a plan of -0.5: the recent
      // pace reaches the target months after the plan, inside a year.
      final trend = [for (var i = 0; i <= 30; i++) 87.4 - 0.2 / 7 * i];
      final start = today.subtract(const Duration(days: 30));
      await pumpOnPhone(
        tester,
        ChangeNotifierProvider(
          create: (_) => EnergyUnitProvider(usesKilojoules: false),
          child: GoalProgressPage(
            unit: BodyWeightUnit.kg,
            loadGoal: () async => (
              inputs: inputs(trend, targetKg: 80),
              progress: GoalProgress(
                start: GoalStart(date: start, kg: 87.4, targetKg: 80),
                nowKg: trend.last,
                paceKgPerWeek: -0.5,
                trend: trend,
                today: today,
              ),
            ),
            loadCalories: () async => (goalKcal: null, meanKcal: null),
          ),
        ),
        textScale: scale,
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('At your recent pace'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      for (final key in ['Your trend', 'Plan', 'At your recent pace']) {
        expect(find.text(key), findsOneWidget);
      }
      expect(find.text('Target'), findsWidgets);
      final chart = tester.widget<LineChart>(find.byType(LineChart)).data;
      // The target is muted, as goal lines are; the projection the accent.
      final target = chart.extraLinesData.horizontalLines.single;
      final projection = chart.lineBarsData[1];
      expect(target.color, isNot(projection.color));
      expect(target.color, chart.lineBarsData[0].color);

      final lastDay = [
        for (final bar in chart.lineBarsData.take(2))
          for (final s in bar.spots) s.x,
      ].reduce((a, b) => a > b ? a : b).round();
      final dates = find.descendant(
        of: find.byType(LineChart),
        matching: find.byWidgetPredicate(
          (w) =>
              w is Text &&
              RegExp(r'^[A-Z][a-z]{2} \d+$').hasMatch(w.data ?? ''),
        ),
      );
      final shown = [
        for (final e in dates.evaluate())
          ((e.widget as Text).data!, tester.getRect(find.byWidget(e.widget))),
      ]..sort((a, b) => a.$2.left.compareTo(b.$2.left));
      expect(lastDay, lessThan(chart.maxX));
      expect(shown.length, greaterThanOrEqualTo(2));
      expect(
        shown.last.$1,
        DateFormat.MMMd('en').format(DateUtils.addDaysToDate(start, lastDay)),
      );
      for (var i = 1; i < shown.length; i++) {
        expect(
          shown[i].$2.left,
          greaterThan(shown[i - 1].$2.right),
          reason: '${shown.map((s) => (s.$1, s.$2.left, s.$2.right))}',
        );
      }
      final card = tester.getRect(
        find
            .ancestor(
              of: find.byType(LineChart),
              matching: find.byType(AppCard),
            )
            .first,
      );
      expect(shown.last.$2.right, lessThanOrEqualTo(card.right));
    });
  }
}
