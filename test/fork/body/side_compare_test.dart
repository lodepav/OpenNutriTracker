import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:opennutritracker/fork/body/measurement_store.dart';
import 'package:opennutritracker/fork/body/side_compare.dart';

DateTime _day(int offset) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day + offset);
}

Measurement _m(int day, BodyMetric metric, double cm) => Measurement(
  id: '$day-${metric.name}',
  date: _day(day),
  metric: metric,
  value: cm,
);

void main() {
  tearDown(() => SidePartPref.current.value = SidePart.arms);

  test('pairs: only the days both sides were measured, oldest first', () {
    final pairs = sidePairs([
      _m(-9, BodyMetric.leftArm, 35),
      _m(-5, BodyMetric.leftArm, 35.5),
      _m(-5, BodyMetric.rightArm, 36),
      _m(-5, BodyMetric.leftThigh, 58),
      _m(-2, BodyMetric.rightArm, 36.2),
      _m(-1, BodyMetric.rightArm, 36.4),
      _m(-1, BodyMetric.leftArm, 36.4),
    ], SidePart.arms);
    expect([for (final p in pairs) p.date], [_day(-5), _day(-1)]);
    expect(
      [for (final p in pairs) (p.left, p.right)],
      [(35.5, 36.0), (36.4, 36.4)],
    );
  });

  test('the difference says which side is bigger, or that both are equal', () {
    const cm = SideUnits(false);
    SidePair pair(double l, double r) => (date: _day(0), left: l, right: r);
    expect(cm.difference(pair(35, 35.8)), 'Right bigger by 0.8 cm');
    expect(cm.difference(pair(36.3, 35.8)), 'Left bigger by 0.5 cm');
    expect(cm.difference(pair(35.02, 35)), 'Both equal');
    expect(
      const SideUnits(true).difference(pair(35, 37.54)),
      'Right bigger by 1.0 in',
    );

    expect(sideTileText(const [], cm), isNull);
    expect(sideTileText([pair(36, 35)], cm), (
      value: '1.0',
      suffix: 'cm · left bigger',
    ));
    expect(sideTileText([pair(36, 35), pair(36, 36)], cm), (
      value: 'Equal',
      suffix: null,
    ));
  });

  testWidgets('the page: both sides, their difference, the days; thighs', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SideComparePage(
          imperial: false,
          rangeDays: 30,
          load: () async => [
            _m(-10, BodyMetric.leftArm, 35),
            _m(-10, BodyMetric.rightArm, 35.6),
            _m(-1, BodyMetric.leftArm, 35.4),
            _m(-1, BodyMetric.rightArm, 36.4),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Arms: left and right'), findsOne);
    // The stats: each side's latest and the difference.
    Finder stat(String v) =>
        find.textContaining(RegExp('^$v\\s?cm\$'), findRichText: true);
    expect(stat('35.4'), findsOne);
    expect(stat('36.4'), findsOne);
    expect(stat('1.0'), findsOne);
    expect(find.textContaining('Right bigger by 1.0 cm, '), findsOne);
    expect(find.textContaining('Right bigger by 0.6 cm'), findsOne);
    // A line a side, a point a measurement.
    final bars = tester.widget<LineChart>(find.byType(LineChart)).data;
    expect(
      [for (final b in bars.lineBarsData) b.spots.map((s) => s.y)],
      [
        [35.0, 35.4],
        [35.6, 36.4],
      ],
    );

    await tester.tap(find.text('Thighs'));
    await tester.pumpAndSettle();
    expect(SidePartPref.current.value, SidePart.thighs);
    expect(find.text('Thighs: left and right'), findsOne);
    expect(find.textContaining('Measure your left and right thighs'), findsOne);
    expect(find.text('No thighs measured yet.'), findsOne);
  });

  testWidgets('none in the range charts them all, and says so', (tester) async {
    SidePartPref.current.value = SidePart.arms;
    await tester.pumpWidget(
      MaterialApp(
        home: SideComparePage(
          imperial: false,
          rangeDays: 30,
          load: () async => [
            _m(-60, BodyMetric.leftArm, 35),
            _m(-60, BodyMetric.rightArm, 37),
            _m(-43, BodyMetric.leftArm, 36),
            _m(-43, BodyMetric.rightArm, 37),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    final bars = tester.widget<LineChart>(find.byType(LineChart)).data;
    expect(
      [for (final b in bars.lineBarsData) b.spots.map((s) => s.y)],
      [
        [35.0, 36.0],
        [37.0, 37.0],
      ],
    );
    expect(
      find.text(
        'None in the last 30 days; all since '
        '${DateFormat.yMMM().format(_day(-60))}.',
      ),
      findsOne,
    );
  });
}
