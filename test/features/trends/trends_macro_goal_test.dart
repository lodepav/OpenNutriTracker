import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/tracked_day_entity.dart';
import 'package:opennutritracker/core/utils/locator.dart';

import '../../fork/trends/trends_harness.dart';

// Seam S87: a macro's goal is the mean over the days that have a goal, not
// their sum over the range's days. S120 moved the Daily average card to
// the macro tiles and the Calories page's table.

TrackedDayEntity _today({double carbs = 70, double kcal = 700}) =>
    TrackedDayEntity(
      day: day(0),
      calorieGoal: 2000,
      caloriesTracked: kcal,
      carbsGoal: 259,
      carbsTracked: carbs,
      fatGoal: 48,
      fatTracked: 14,
      proteinGoal: 64,
      proteinTracked: 21,
    );

void main() {
  tearDown(() async => locator.reset());

  testWidgets('a week with one day logged: the goals as that day had them', (
    tester,
  ) async {
    // One day logged of the seven.
    await pumpTrends(tester, loaded(days: [_today()]));

    // S120: the intake is over the logged days, as the weekly report's.
    expect(tileText(tester, 'carbs'), contains('70 / 259 g'));
    expect(tileText(tester, 'fat'), contains('14 / 48 g'));
    expect(tileText(tester, 'protein'), contains('21 / 64 g'));
  });

  // Seam S114: grams round, as the weekly report's do; 69.6 g is 70 g.
  testWidgets('the daily average rounds', (tester) async {
    await pumpTrends(tester, loaded(days: [_today(carbs: 69.6)]));
    expect(tileText(tester, 'carbs'), contains('70 / 259 g'));
    await openTile(tester, 'calories');
    expect(find.text('70 g'), findsOneWidget);
  });

  // Seam S114: energy is cut to whole numbers everywhere, as energyValue
  // has it: the tile, the page's average and the tooltip.
  testWidgets('energy is cut, not rounded, in the tile and tooltip', (
    tester,
  ) async {
    await pumpTrends(tester, loaded(days: [_today(kcal: 2572.6)]));
    expect(tileText(tester, 'calories'), contains('2572 / 2000'));
    await openTile(tester, 'calories');
    expect(find.text('2572 kcal'), findsOneWidget);
    final data = tester.widget<BarChart>(find.byType(BarChart)).data;
    final group = data.barGroups.last;
    final item = data.barTouchData.touchTooltipData.getTooltipItem(
      group,
      group.x,
      group.barRods.single,
      0,
    )!;
    expect(item.text, startsWith('2572 kcal'));
  });
}
