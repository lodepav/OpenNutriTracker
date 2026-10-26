import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/tracked_day_entity.dart';
import 'package:opennutritracker/core/utils/calc/unit_calc.dart';
import 'package:opennutritracker/core/utils/locator.dart';

import 'trends_harness.dart';

// #1362: the Trends calorie chart and its tooltip must follow the energy
// unit setting, as the rest of the app does. S120: the chart is the
// Calories tile's page, its bars stacked by macro.

const _trackedKcal = 1039.0;
const _goalKcal = 2000.0;

Future<BarChartData> _pumpCaloriesChart(
  WidgetTester tester, {
  required bool usesKilojoules,
}) async {
  await pumpTrends(
    tester,
    loaded(
      days: [
        TrackedDayEntity(
          day: day(0),
          calorieGoal: _goalKcal,
          caloriesTracked: _trackedKcal,
        ),
      ],
    ),
    kj: usesKilojoules,
  );
  await openTile(tester, 'calories');
  return tester.widget<BarChart>(find.byType(BarChart)).data;
}

String _tooltipFor(BarChartData chart) {
  final group = chart.barGroups.last;
  return chart.barTouchData.touchTooltipData
      .getTooltipItem(group, group.x, group.barRods.single, 0)!
      .text;
}

void main() {
  tearDown(() async => locator.reset());

  testWidgets('kJ: today\'s bar, tooltip and goal line are in kJ', (
    tester,
  ) async {
    final chart = await _pumpCaloriesChart(tester, usesKilojoules: true);
    final today = chart.barGroups.last.barRods.single;

    expect(today.toY, closeTo(UnitCalc.kcalToKj(_trackedKcal), 0.001));
    expect(_tooltipFor(chart), startsWith('4347 kJ'));
    // [fork] S83 the average converts once
    expect(find.text('4347 kJ'), findsOneWidget);
    // [fork] S103: the page is "Energy", not "Calories", in kJ.
    expect(find.widgetWithText(AppBar, 'Energy'), findsOneWidget);
    // [/fork]
    expect(
      chart.extraLinesData.horizontalLines.single.y,
      closeTo(UnitCalc.kcalToKj(_goalKcal), 0.001),
    );
  });

  testWidgets('kcal: today\'s bar, tooltip and goal line stay in kcal', (
    tester,
  ) async {
    final chart = await _pumpCaloriesChart(tester, usesKilojoules: false);
    final today = chart.barGroups.last.barRods.single;

    expect(today.toY, _trackedKcal);
    expect(_tooltipFor(chart), startsWith('1039 kcal'));
    // [fork] S83
    expect(find.text('1039 kcal'), findsOneWidget);
    expect(find.widgetWithText(AppBar, 'Calories'), findsOneWidget);
    // [/fork]
    expect(chart.extraLinesData.horizontalLines.single.y, _goalKcal);
  });
}
