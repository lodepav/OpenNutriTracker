import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/weight_log_entity.dart';
import 'package:opennutritracker/fork/adaptive/trend.dart';
import 'package:opennutritracker/fork/adaptive/trend_points.dart';

void main() {
  group('twoSidedTrend (D70)', () {
    test('matches the Python reference to 1e-3', () {
      const weighIns = {
        0: 80.0,
        1: 80.4,
        2: 79.8,
        3: 80.2,
        5: 79.6,
        6: 79.9,
        9: 79.2,
        10: 79.5,
        11: 78.9,
        12: 79.1,
      };
      const expected = [
        80.1475, 80.0672, 79.9841, 79.9022, 79.8178, 79.7332, 79.6496, //
        79.5638, 79.4779, 79.392, 79.3075, 79.2215, 79.138,
      ];
      final trend = twoSidedTrend(weighIns, 13);
      for (var i = 0; i < 13; i++) {
        expect(trend[i], closeTo(expected[i], 1e-3), reason: 'day $i');
      }
    });

    test('a constant series gives that constant', () {
      final trend = twoSidedTrend({for (var i = 0; i < 10; i += 2) i: 75.0}, 9);
      for (final v in trend) {
        expect(v, closeTo(75, 1e-9));
      }
    });

    test('a gap is not filled with a straight line and stays between '
        'the weigh-ins around it', () {
      final trend = twoSidedTrend({
        for (var i = 0; i < 5; i++) i: 80.0,
        for (var i = 12; i < 17; i++) i: 78.0,
      }, 17);
      // Linear from 80 on day 4 to 78 on day 12 would give 79.75 on day 5.
      expect((trend[5]! - 79.75).abs(), greaterThan(0.1));
      for (var d = 5; d < 12; d++) {
        expect(trend[d], inExclusiveRange(78, 80), reason: 'day $d');
      }
    });

    test('one weigh-in gives that weight from its day on', () {
      expect(twoSidedTrend({2: 70.0}, 5), [null, null, 70.0, 70.0, 70.0]);
    });

    test('days after the last weigh-in hold the last level', () {
      final trend = twoSidedTrend({0: 80.0, 1: 79.0, 2: 78.0}, 6);
      expect(trend[2], isNot(78.0));
      expect(trend.sublist(3), everyElement(trend[2]));
    });

    test('no weigh-ins give no trend', () {
      expect(twoSidedTrend({}, 3), [null, null, null]);
    });
  });

  test('trendPoints with until beyond the last weigh-in holds its level', () {
    final points = trendPoints([
      WeightLogEntity(date: DateTime(2026, 11, 1, 7), weightKg: 80),
      WeightLogEntity(date: DateTime(2026, 11, 2, 7), weightKg: 79.5),
      WeightLogEntity(date: DateTime(2026, 11, 3, 7), weightKg: 79),
    ], until: DateTime(2026, 11, 6, 20));
    expect(points.map((p) => p.date), [
      for (var d = 1; d <= 6; d++) DateTime(2026, 11, d),
    ]);
    final atLast = points[2].weightKg;
    expect(
      atLast,
      closeTo(twoSidedTrend({0: 80, 1: 79.5, 2: 79}, 3)[2]!, 1e-12),
    );
    expect(points.sublist(3).map((p) => p.weightKg), everyElement(atLast));
  });
}
