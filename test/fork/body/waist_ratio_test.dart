import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:opennutritracker/core/domain/entity/weight_log_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_gender_entity.dart';
import 'package:opennutritracker/fork/body/measurement_store.dart';
import 'package:opennutritracker/fork/body/waist_ratio.dart';

import '../../helpers/ux_checks.dart';
import 'axis_labels.dart';

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
  test('each waist day against the height, and the hips that day', () {
    final points = waistPoints([
      _m(-20, BodyMetric.hips, 100),
      _m(-10, BodyMetric.waist, 90),
      _m(-2, BodyMetric.waist, 86),
      _m(-2, BodyMetric.hips, 98),
      _m(-1, BodyMetric.chest, 100),
    ], 180);
    expect([for (final p in points) p.date], [_day(-10), _day(-2)]);
    expect(points.first.ratio, 0.5);
    expect(points.first.hipRatio, isNull);
    expect(points.last.ratio, closeTo(0.478, 0.001));
    expect(points.last.hipRatio, closeTo(0.878, 0.001));

    expect(waistPoints([_m(-1, BodyMetric.waist, 80)], 0), isEmpty);
  });

  test("NICE's bands, WHO's hip cut-offs, the tile's figures", () {
    expect(waistBand(0.45), 'no increased risk');
    expect(waistBand(0.5), 'increased risk');
    expect(waistBand(0.59), 'increased risk');
    expect(waistBand(0.6), 'high risk');

    expect(hipCutOff(UserGenderEntity.male), 0.90);
    expect(hipCutOff(UserGenderEntity.female), 0.85);
    expect(hipCutOff(UserGenderEntity.nonBinary), isNull);

    expect(waistTileText(const []), isNull);
    expect(waistTileText(waistPoints([_m(0, BodyMetric.waist, 92)], 170)), (
      value: '0.54',
      suffix: 'increased risk',
    ));
  });

  testWidgets('the page: ratio, waist and hips, the band, the days', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        home: WaistRatioPage(
          imperial: true,
          rangeDays: 30,
          frame: () async => (heightCm: 180.0, gender: UserGenderEntity.female),
          load: () async => [
            _m(-12, BodyMetric.waist, 91.44),
            _m(-1, BodyMetric.waist, 86),
            _m(-1, BodyMetric.hips, 98),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Waist to height'), findsWidgets);
    expect(find.textContaining('0.48'), findsWidgets);
    expect(find.textContaining('No increased risk,'), findsOne);
    expect(find.text('WHO: over 0.85 raises the risk'), findsOne);
    // inches for imperial; the older day has no hips
    expect(find.textContaining('waist 36.0 in'), findsOne);
    // The chart's ends in words, and what its dashed line is.
    String d(int offset) => DateFormat.MMMd().format(_day(offset));
    expect(find.text('0.51 on ${d(-12)} \u2192 0.48 on ${d(-1)}'), findsOne);
    expect(find.text('0.5 risk line'), findsOne);
    // Units in words for a screen reader.
    expect(
      find.bySemanticsLabel(
        'Waist to height 0.48, Waist 33.9 inches, Waist to hips 0.88',
      ),
      findsOne,
    );
    await tester.scrollUntilVisible(find.textContaining('waist 36.0 in'), 200);
    expect(
      find.bySemanticsLabel(
        '${DateFormat.yMMMd().format(_day(-12))}, 0.51, waist 36.0 inches',
      ),
      findsOne,
    );
    semantics.dispose();

    await tester.ensureVisible(find.text('What is waist to height?'));
    await tester.tap(find.text('What is waist to height?'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOne);
  });

  group('waistAgainstWeight', () {
    WaistPoint point(int day, double cm) =>
        (date: _day(day), waistCm: cm, ratio: cm / 180, hipRatio: null);

    test('first to last measurement, the trend those days', () {
      final w = waistAgainstWeight(
        [point(-30, 92), point(-20, 91), point(-2, 90)],
        {
          _day(-40): 85,
          // The nearest trend day at or before the first measurement.
          _day(-33): 82.4,
          _day(-2): 81,
          _day(0): 80,
        },
      )!;
      expect(w.from, _day(-30));
      expect(w.to, _day(-2));
      expect(w.waistCm, -2);
      expect(w.trendKg, closeTo(-1.4, 1e-9));
    });

    test('one measurement, or no trend near either end: nothing', () {
      final trend = {for (var d = -40; d <= 0; d++) _day(d): 80.0};
      expect(waistAgainstWeight([point(-2, 90)], trend), isNull);
      expect(waistAgainstWeight([point(-30, 92), point(-2, 90)], {}), isNull);
      // The trend starts after the first measurement.
      expect(
        waistAgainstWeight(
          [point(-30, 92), point(-2, 90)],
          {_day(-29): 80, _day(-2): 79},
        ),
        isNull,
      );
      // Over a week before the last one is too far.
      expect(
        waistAgainstWeight(
          [point(-30, 92), point(-2, 90)],
          {_day(-30): 80, _day(-10): 79},
        ),
        isNull,
      );
    });
  });

  testWidgets('the waist against the trend weight over the range', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: WaistRatioPage(
          imperial: false,
          rangeDays: 30,
          frame: () async => (heightCm: 180.0, gender: UserGenderEntity.male),
          load: () async => [
            _m(-20, BodyMetric.waist, 92),
            _m(-1, BodyMetric.waist, 90),
          ],
          weights: () async => [
            WeightLogEntity(date: _day(-25), weightKg: 82),
            WeightLogEntity(date: _day(-1), weightKg: 82),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    // A steady weight: its trend has not moved.
    expect(
      find.text(
        'Waist \u22122.0 cm · trend weight 0.0 kg, '
        '${DateFormat.MMMd().format(_day(-20))} to '
        '${DateFormat.MMMd().format(_day(-1))}',
      ),
      findsOne,
    );
  });

  testWidgets('one waist measurement: no change shown', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: WaistRatioPage(
          imperial: false,
          rangeDays: 30,
          frame: () async => (heightCm: 180.0, gender: UserGenderEntity.male),
          load: () async => [_m(-1, BodyMetric.waist, 90)],
          weights: () async => [WeightLogEntity(date: _day(-25), weightKg: 82)],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('trend weight'), findsNothing);
  });

  testWidgets('no height: it asks for one', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: WaistRatioPage(
          imperial: false,
          rangeDays: 30,
          frame: () async => null,
          load: () async => [_m(-1, BodyMetric.waist, 86)],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Set your height in your profile'), findsOne);
  });

  testWidgets('the page at 200% text: nothing cut, the targets and contrast', (
    tester,
  ) async {
    await checkScreen(
      tester,
      WaistRatioPage(
        imperial: false,
        rangeDays: 30,
        frame: () async => (heightCm: 180.0, gender: UserGenderEntity.female),
        load: () async => [
          _m(-12, BodyMetric.waist, 91.44),
          _m(-1, BodyMetric.waist, 86),
          _m(-1, BodyMetric.hips, 98),
        ],
      ),
    );
  });

  testWidgets('at 200% text the axis numbers stay whole and apart', (
    tester,
  ) async {
    await pumpOnPhone(
      tester,
      WaistRatioPage(
        imperial: false,
        rangeDays: 30,
        frame: () async => (heightCm: 178.0, gender: UserGenderEntity.male),
        load: () async => [
          _m(-6, BodyMetric.waist, 92),
          _m(-1, BodyMetric.waist, 90.5),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expectAxisReadable(tester);
  });
}
