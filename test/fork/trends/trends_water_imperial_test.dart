import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/tracked_day_entity.dart';
import 'package:opennutritracker/core/utils/calc/unit_calc.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/fork/display/display_prefs.dart';

import '../../helpers/test_l10n.dart';
import 'trends_harness.dart';

// #1306: water follows the food units, ml or fl oz. S120: the water card is
// the Water tile's page, and the tile says the unit too; S190: the average
// is over the days logged.

const _todayMl = 200;
const _goalMl = 2000;

Future<void> _pump(WidgetTester tester, {required bool imperial}) async {
  await pumpTrends(
    tester,
    loaded(
      days: [
        TrackedDayEntity(day: day(0), calorieGoal: 2000, caloriesTracked: 1500),
      ],
      waterByDay: {day(0): _todayMl},
      waterGoalMl: _goalMl,
      imperial: imperial,
    ),
  );
}

LineChart _waterChart(WidgetTester tester, double todayY) => tester
    .widgetList<LineChart>(find.byType(LineChart))
    .firstWhere(
      (c) => (c.data.lineBarsData.first.spots.last.y - todayY).abs() < 0.001,
    );

void main() {
  // Water is off until switched on.
  setUp(() => DisplayPrefs.showWater.value = true);
  tearDown(() async {
    DisplayPrefs.showWater.value = false;
    await locator.reset();
  });

  testWidgets('imperial: the tile, header, points and goal line are in fl oz', (
    tester,
  ) async {
    await _pump(tester, imperial: true);
    await showTile(tester, 'water');
    expect(tileText(tester, 'water'), contains('/ 68 fl oz'));

    await openTile(tester, 'water');
    // 200 ml = 6.8 fl oz, goal 2000 ml = 67.6 fl oz.
    expect(find.text(l10nEn.waterChipLabelFlOz(7, 68)), findsOneWidget);
    final chart = _waterChart(tester, UnitCalc.mlToFlOz(_todayMl.toDouble()));
    expect(
      chart.data.extraLinesData.horizontalLines.single.y,
      closeTo(UnitCalc.mlToFlOz(_goalMl.toDouble()), 0.001),
    );
  });

  testWidgets('metric: the tile, header, points and goal line stay in ml', (
    tester,
  ) async {
    await _pump(tester, imperial: false);
    await showTile(tester, 'water');
    expect(tileText(tester, 'water'), contains('/ 2000 ml'));

    await openTile(tester, 'water');
    expect(find.text(l10nEn.waterChipLabel(200, _goalMl)), findsOneWidget);
    final chart = _waterChart(tester, _todayMl.toDouble());
    expect(chart.data.extraLinesData.horizontalLines.single.y, _goalMl);
  });
}
