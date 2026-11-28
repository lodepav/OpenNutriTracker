import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:opennutritracker/fork/adaptive/adaptive_service.dart';
import 'package:opennutritracker/fork/trends/expenditure_detail.dart';

// The Expenditure chart's axis numbers at a large font.

/// Android's nonlinear font scaling: small text grows twice, large text
/// far less, so a constant scaled by it falls short of a label's width.
class _Nonlinear extends TextScaler {
  const _Nonlinear();

  @override
  double scale(double fontSize) =>
      fontSize < 20 ? fontSize * 2 : fontSize * 1.2;

  @override
  double get textScaleFactor => 2;
}

void main() {
  testWidgets('the axis numbers stay on one line at a large font', (
    tester,
  ) async {
    final dates = [for (var i = 0; i < 7; i++) DateTime(2026, 10, 20 + i)];
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: const _Nonlinear()),
          child: child!,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            child: ExpenditureChart(
              history: [
                for (final (i, d) in dates.indexed)
                  ExpenditureDay(
                    date: d,
                    expenditureKcal: 3000 + i * 50.0,
                    intakeKcal: 2500,
                    settled: true,
                  ),
              ],
              dates: dates,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final labels = find.text('3000');
    expect(labels, findsOneWidget);
    // labelSmall is 11 px, 22 at this scale: one line is under 40 px.
    expect(tester.getSize(labels).height, lessThan(40));
  });
  testWidgets('fitted to the estimate alone, the intake left to a touch', (
    tester,
  ) async {
    final dates = [for (var i = 0; i < 7; i++) DateTime(2026, 10, 20 + i)];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ExpenditureChart(
              history: [
                for (final (i, d) in dates.indexed)
                  ExpenditureDay(
                    date: d,
                    expenditureKcal: 3000 + i * 50.0,
                    intakeKcal: i == 3 ? 1800 : null,
                    settled: true,
                  ),
              ],
              dates: dates,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final data = tester.widget<LineChart>(find.byType(LineChart)).data;
    expect(data.lineBarsData, hasLength(1));
    expect(data.minY, greaterThanOrEqualTo(2900));
    expect(find.text('Logged'), findsNothing);

    final spot = LineBarSpot(data.lineBarsData.first, 0, const FlSpot(3, 3150));
    final items = data.lineTouchData.touchTooltipData.getTooltipItems([spot]);
    expect(items.single!.text, 'Expenditure 3150 kcal');
    expect(items.single!.children!.single.toPlainText(), '\nLogged 1800 kcal');
    final none = LineBarSpot(data.lineBarsData.first, 0, const FlSpot(2, 3100));
    expect(
      data.lineTouchData.touchTooltipData
          .getTooltipItems([none])
          .single!
          .children!
          .single
          .toPlainText(),
      '',
    );
  });

  test('a small spread gets an axis of at least the minimum span', () {
    final axis = expenditureAxis([3035, 3042, 3050], minSpan: 200);
    expect(axis.max - axis.min, greaterThanOrEqualTo(200));
    expect(axis.min, lessThanOrEqualTo(3035));
    expect(axis.max, greaterThanOrEqualTo(3050));
    // Centred on the data, at the nice step.
    expect(axis, (min: 2900.0, max: 3200.0, step: 100.0));
  });

  test('a spread over the minimum keeps its own axis', () {
    expect(expenditureAxis([3000, 3300, 3600], minSpan: 200), (
      min: 3000.0,
      max: 3600.0,
      step: 200.0,
    ));
  });

  testWidgets('a 15 kcal week does not fill the chart', (tester) async {
    final dates = [for (var i = 0; i < 7; i++) DateTime(2026, 10, 20 + i)];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ExpenditureChart(
              history: [
                for (final (i, d) in dates.indexed)
                  ExpenditureDay(
                    date: d,
                    expenditureKcal: 3035 + i * 2.5,
                    intakeKcal: 2500,
                    settled: true,
                  ),
              ],
              dates: dates,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final data = tester.widget<LineChart>(find.byType(LineChart)).data;
    expect(data.maxY - data.minY, greaterThanOrEqualTo(200));
  });

  testWidgets('a year names its years; an estimate starting late starts the '
      'line and says so', (tester) async {
    final dates = [
      for (var i = 0; i < 365; i++) DateTime(2025, 11, 29 + i),
    ];
    Future<void> pump(List<DateTime> estimated) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ExpenditureChart(
              history: [
                for (final d in estimated)
                  ExpenditureDay(
                    date: d,
                    expenditureKcal: 3000,
                    settled: true,
                  ),
              ],
              dates: dates,
            ),
          ),
        ),
      ),
    );
    await pump(dates);
    expect(find.text('Nov 2025'), findsOneWidget);
    expect(find.text('Nov 2026'), findsOneWidget);
    expect(find.byKey(const ValueKey('estimate-from')), findsNothing);

    await pump(dates.sublist(300));
    final spots = tester
        .widget<LineChart>(find.byType(LineChart))
        .data
        .lineBarsData
        .single
        .spots;
    expect(spots, hasLength(65));
    final from = DateFormat.MMMd('en_US').format(dates[300]);
    expect(find.text('Estimate from $from'), findsOneWidget);
    // Two months, one year: day and month.
    expect(find.text(from), findsOneWidget);
  });
}
