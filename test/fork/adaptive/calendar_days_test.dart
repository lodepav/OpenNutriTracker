import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/weight_log_entity.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_service.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_store.dart';
import 'package:opennutritracker/fork/adaptive/trend_points.dart';

// Europe's clocks go forward on 29 March 2026: in a zone that changes,
// local midnights a week apart across it are 167 hours apart. Where the
// zone does not change these pass either way.
void main() {
  test('a week across the clock change is a week', () {
    expect(
      checkInDueOn(DateTime(2026, 3, 30), DateTime(2026, 3, 23), null),
      isTrue,
    );
    expect(
      checkInDueOn(DateTime(2026, 3, 29), DateTime(2026, 3, 23), null),
      isFalse,
    );
  });

  test('the smoothed trend keeps one point a day across it', () {
    AdaptiveStore.settings.value = const AdaptiveSettings(smoothedTrend: true);
    addTearDown(() => AdaptiveStore.settings.value = const AdaptiveSettings());
    final entries = [
      for (var d = 26; d <= 31; d++)
        WeightLogEntity(date: DateTime(2026, 3, d), weightKg: 80.0 + d - 26),
    ];
    final points = smoothedTrendPoints(entries)!;
    expect(points.map((p) => p.date.day), [26, 27, 28, 29, 30, 31]);
    // Each day's weigh-in is its own: none is lost to a neighbour's index.
    expect(
      points.last.weightKg,
      greaterThan(points[points.length - 2].weightKg),
    );
  });
}
