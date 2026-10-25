import 'package:opennutritracker/core/domain/entity/weight_log_entity.dart';
import 'package:opennutritracker/core/utils/calc/calendar_day_calc.dart';
import 'package:opennutritracker/core/utils/calc/weight_moving_average.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_store.dart';
import 'package:opennutritracker/fork/adaptive/expenditure.dart';
import 'package:opennutritracker/fork/adaptive/trend.dart';

/// Seam S15: the smoothed trend for the weight chart, one point a day from
/// the first weigh-in to the last, computed on the whole log; null while
/// the setting keeps upstream's 7-day average.
List<WeightMovingAveragePoint>? smoothedTrendPoints(
  List<WeightLogEntity> entries,
) => AdaptiveStore.settings.value.smoothedTrend ? trendPoints(entries) : null;

/// The smoothed trend whatever the chart shows, one point a day from the
/// first weigh-in to the last, or on to [until] with the last weigh-in held
/// as the Goal planner's is; empty without weigh-ins.
List<WeightMovingAveragePoint> trendPoints(
  List<WeightLogEntity> entries, {
  DateTime? until,
}) {
  if (entries.isEmpty) return const [];
  DateTime day(DateTime t) => DateTime(t.year, t.month, t.day);
  final first = entries
      .map((e) => day(e.date))
      .reduce((a, b) => a.isBefore(b) ? a : b);
  final lastWeighIn = entries
      .map((e) => day(e.date))
      .reduce((a, b) => a.isAfter(b) ? a : b);
  final last = until != null && day(until).isAfter(lastWeighIn)
      ? day(until)
      : lastWeighIn;
  // Calendar days: across a spring-forward local midnights are 23 h apart.
  final count = CalendarDayCalc.daysBetween(first, last) + 1;
  final trend = smoothedTrend(
    dailyWeights({
      for (final e in entries)
        CalendarDayCalc.daysBetween(first, e.date): e.weightKg,
    }, count),
    alpha: const ExpenditureSettings().alpha,
  );
  return [
    for (var i = 0; i < count; i++)
      WeightMovingAveragePoint(
        date: DateTime(first.year, first.month, first.day + i),
        weightKg: trend[i]!,
        sampleCount: i + 1,
      ),
  ];
}
