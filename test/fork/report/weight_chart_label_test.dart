import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:opennutritracker/core/domain/entity/body_weight_unit_entity.dart';
import 'package:opennutritracker/core/domain/entity/weight_log_entity.dart';
import 'package:opennutritracker/features/profile/presentation/widgets/weight_trend_chart.dart';
import 'package:opennutritracker/fork/report/weight_chart_label.dart';
import 'package:opennutritracker/generated/l10n.dart';

// Seam S96: the weight chart is heard as one sentence about its data, not
// its axis labels, and its weigh-ins are dots with no line between them.

final _today = DateTime(2026, 11, 18);

Future<void> _pump(WidgetTester tester, BodyWeightUnit unit) async {
  WeightTrendChart.clock = () => _today.add(const Duration(hours: 9));
  addTearDown(() => WeightTrendChart.clock = DateTime.now);
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
            WeightLogEntity(date: DateTime(2026, 11, 12), weightKg: 87.4),
            WeightLogEntity(date: DateTime(2026, 11, 15), weightKg: 86.9),
            WeightLogEntity(date: DateTime(2026, 11, 18), weightKg: 87.1),
          ],
          bodyWeightUnit: unit,
          targetWeightKg: null,
          windowDays: 7,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('weightChartLabel', () {
    setUpAll(() => initializeDateFormatting('en'));

    test('the span, the trend and the weigh-ins, in the unit', () {
      expect(
        weightChartLabel(
          from: DateTime(2026, 11, 12),
          to: _today,
          locale: 'en',
          weighIns: [87.4, 86.9, 87.1],
          trend: [87.3, 87.2, 87.1],
          unit: 'kg',
        ),
        'Weight chart, Nov 12 to Nov 18: trend from 87.3 to 87.1 kg, '
        '3 weigh-ins, from 86.9 to 87.4 kg.',
      );
    });

    test('no trend line: the weigh-ins alone; one weight said once', () {
      expect(
        weightChartLabel(
          from: DateTime(2026, 11, 12),
          to: _today,
          locale: 'en',
          weighIns: [190, 190],
          trend: const [],
          unit: 'lbs',
        ),
        'Weight chart, Nov 12 to Nov 18: 2 weigh-ins, all 190.0 lbs.',
      );
    });
  });

  testWidgets('the chart is one label; its axis is not read out', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester, BodyWeightUnit.kg);
    // The date and weight labels are still drawn, but not heard.
    expect(find.text('Nov 12'), findsOneWidget);
    expect(find.bySemanticsLabel('Nov 12'), findsNothing);
    expect(find.bySemanticsLabel(RegExp(r'^\d+\.\d$')), findsNothing);
    expect(
      find.bySemanticsLabel(
        RegExp(
          r'^Weight chart, Nov 12 to Nov 18: trend from .* kg, '
          r'3 weigh-ins, from 86\.9 to 87\.4 kg\.$',
        ),
      ),
      findsOneWidget,
    );
    // The legend is still read.
    expect(
      find.bySemanticsLabel('Dots: weigh-ins. Bold line: trend.'),
      findsOneWidget,
    );
    semantics.dispose();
  });

  testWidgets('the label is in the page\'s unit', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester, BodyWeightUnit.lb);
    expect(
      find.bySemanticsLabel(RegExp(r'weigh-ins, from 191\.6 to 192\.7 lbs\.$')),
      findsOneWidget,
    );
    semantics.dispose();
  });

  testWidgets('weigh-ins are dots with no line between them', (tester) async {
    await _pump(tester, BodyWeightUnit.kg);
    final data = tester.widget<LineChart>(find.byType(LineChart)).data;
    final weighIns = data.lineBarsData.first;
    expect(weighIns.show, isTrue);
    expect(weighIns.barWidth, 0);
    expect(weighIns.dotData.show, isTrue);
    // The trend is still the bold line.
    expect(data.lineBarsData[1].barWidth, 3);
  });
}
