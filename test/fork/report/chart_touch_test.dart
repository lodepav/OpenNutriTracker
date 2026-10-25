import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/body_weight_unit_entity.dart';
import 'package:opennutritracker/core/domain/entity/weight_log_entity.dart';
import 'package:opennutritracker/features/profile/presentation/widgets/weight_trend_chart.dart';
import 'package:opennutritracker/generated/l10n.dart';

// Seam S96: a touch on the weight chart names each number, at one decimal,
// and draws no line down to the axis.

/// The tooltip's lines for a touch at each bar's spot [index].
List<String> _tooltip(LineChartData data, int index) => [
  for (final item in data.lineTouchData.touchTooltipData.getTooltipItems([
    for (final (i, bar) in data.lineBarsData.indexed)
      if (index < bar.spots.length) LineBarSpot(bar, i, bar.spots[index]),
  ]))
    item!.text,
];

void main() {
  testWidgets('the weight tooltip names the weigh-in and the trend', (
    tester,
  ) async {
    final now = DateTime.now();
    DateTime day(int offset) => DateTime(now.year, now.month, now.day + offset);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          S.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: S.supportedLocales,
        home: Scaffold(
          body: WeightTrendChart(
            entries: [
              for (var i = 0; i < 10; i++)
                WeightLogEntity(
                  date: day(i - 9),
                  weightKg: 96 - i * 0.13 + (i.isEven ? 0.4 : 0),
                ),
            ],
            bodyWeightUnit: BodyWeightUnit.kg,
            targetWeightKg: null,
            windowDays: 30,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final data = tester.widget<LineChart>(find.byType(LineChart)).data;

    final lines = _tooltip(data, 3);
    expect(lines, hasLength(2));
    expect(lines[0], matches(RegExp(r'^Weighed \d+\.\d kg$')));
    expect(lines[1], matches(RegExp(r'^Trend \d+\.\d kg$')));

    final indicator = data.lineTouchData.getTouchedSpotIndicator(
      data.lineBarsData.first,
      [3],
    );
    expect(indicator.single!.indicatorBelowLine.strokeWidth, 0);

    // The dashed line at full colour: at 55% it fell under 3:1 on a light
    // card.
    expect(data.lineBarsData[1].color, data.lineBarsData[0].color);
  });
}
