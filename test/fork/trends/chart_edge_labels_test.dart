import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/tracked_day_entity.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/fork/trends/calories_detail.dart';
import 'package:provider/provider.dart';

import '../../helpers/ux_checks.dart';
import 'trends_harness.dart';

// The 1Y calories chart at 200% on a 360 dp phone: "Nov 2025" was cut at
// the card's left edge.

void main() {
  testWidgets('at 200% on a 360 dp phone the year\'s end dates stay inside '
      'the chart', (tester) async {
    final dates = [
      for (var i = 0; i < 365; i++) DateTime(2025, 11, 29 + i),
    ];
    // Drawn at 1x first: a label measured once kept its 1x width at 2x.
    await pumpOnPhone(
      tester,
      textScale: 1,
      ChangeNotifierProvider(
        create: (_) => EnergyUnitProvider(usesKilojoules: false),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: MacroEnergyChart(
            state: loaded(
              rangeDays: dates.length,
              days: [
                for (final d in dates)
                  TrackedDayEntity(
                    day: d,
                    calorieGoal: 2500,
                    caloriesTracked: 2000,
                    carbsTracked: 250,
                    fatTracked: 44.4,
                    proteinTracked: 100,
                  ),
              ],
            ),
            dates: dates,
          ),
        ),
      ),
    );
    tester.view
      ..physicalSize = const Size(360, 800)
      ..devicePixelRatio = 1;
    await tester.pumpAndSettle();
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    await tester.pumpAndSettle();

    final chart = tester.getRect(find.byType(BarChart));
    final first = tester.getRect(find.text('Nov 2025'));
    final last = tester.getRect(find.text('Nov 2026'));
    expect(first.left, greaterThanOrEqualTo(chart.left));
    expect(last.right, lessThanOrEqualTo(chart.right));
    expect(first.right, lessThan(last.left));
    expect(cutText(tester), isEmpty);
  });
}
