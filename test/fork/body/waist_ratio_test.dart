import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/user_gender_entity.dart';
import 'package:opennutritracker/fork/body/measurement_store.dart';
import 'package:opennutritracker/fork/body/waist_ratio.dart';

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

    await tester.ensureVisible(find.text('What is waist to height?'));
    await tester.tap(find.text('What is waist to height?'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOne);
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
}
