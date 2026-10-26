import 'package:opennutritracker/core/domain/entity/body_weight_unit_entity.dart';
import 'package:opennutritracker/core/domain/entity/tracked_day_entity.dart';
import 'package:opennutritracker/core/domain/entity/weight_log_entity.dart';
import 'package:opennutritracker/core/utils/calc/unit_calc.dart';
import 'package:opennutritracker/features/trends/presentation/trends_calc.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_service.dart';
import 'package:opennutritracker/fork/adaptive/trend_points.dart';

/// What a Trends tile shows, and the detail page it opens.
enum TrendMetric {
  calories,
  weight,
  expenditure,
  balance,
  carbs,
  fat,
  protein,
  fibre,
  sugars,
  sodium,
  water,
}

/// The range pills, as MacroFactor's: days back from today, 0 for "All".
const trendRanges = [
  (days: 7, label: '1W'),
  (days: 30, label: '1M'),
  (days: 90, label: '3M'),
  (days: 180, label: '6M'),
  (days: 365, label: '1Y'),
  (days: 0, label: 'All'),
];

/// One value a day over the window, oldest first; null where nothing was
/// logged, so a day left empty does not read as a day of fasting.
typedef DaySeries = List<double?>;

DateTime _date(DateTime t) => DateTime(t.year, t.month, t.day);

/// The window's [count] days, oldest first, ending [today].
List<DateTime> windowDates(DateTime today, int count) => [
  for (var i = 0; i < count; i++)
    DateTime(today.year, today.month, today.day - (count - 1 - i)),
];

/// The mean of the values present, or null without any.
double? meanOf(Iterable<double?> values) {
  final present = values.whereType<double>().toList();
  if (present.isEmpty) return null;
  return present.reduce((a, b) => a + b) / present.length;
}

/// The change a least-squares line through the values present makes over
/// the whole series, first day to last; null with fewer than two.
double? fittedChange(DaySeries series) {
  final points = [
    for (final (i, v) in series.indexed)
      if (v != null) (x: i.toDouble(), y: v),
  ];
  if (points.length < 2) return null;
  final mx = points.map((p) => p.x).reduce((a, b) => a + b) / points.length;
  final my = points.map((p) => p.y).reduce((a, b) => a + b) / points.length;
  var num = 0.0, den = 0.0;
  for (final p in points) {
    num += (p.x - mx) * (p.y - my);
    den += (p.x - mx) * (p.x - mx);
  }
  return den == 0 ? 0 : num / den * (series.length - 1);
}

/// A day counts as logged with any energy on it, as the weekly report has
/// it.
bool isLogged(TrackedDayEntity d) => d.caloriesTracked > 0;

/// The tracked days over the window by date.
Map<DateTime, TrackedDayEntity> _byDate(List<TrackedDayEntity> days) => {
  for (final d in days) _date(d.day): d,
};

/// Eaten a day, from [days], over the window's [dates]; only logged days.
DaySeries nutritionSeries(
  List<TrackedDayEntity> days,
  List<DateTime> dates,
  double? Function(TrackedDayEntity) value,
) {
  final byDate = _byDate(days);
  return [
    for (final date in dates)
      if (byDate[date] case final d? when isLogged(d)) value(d) else null,
  ];
}

/// The goal, the mean over the logged days that have one (S87: a range
/// with one logged day shows that day's goal).
double? goalOf(
  List<TrackedDayEntity> days,
  List<DateTime> dates,
  double? Function(TrackedDayEntity) goal,
) => meanOf(
  nutritionSeries(days, dates, goal).map((g) => g != null && g > 0 ? g : null),
);

/// The kcal a day that carbs, fat and protein gave, by 4, 9 and 4 kcal a
/// gram, scaled to the energy logged so a bar's top is the day's total.
({double carbs, double fat, double protein})? macroEnergy(TrackedDayEntity d) {
  final c = (d.carbsTracked ?? 0) * 4;
  final f = (d.fatTracked ?? 0) * 9;
  final p = (d.proteinTracked ?? 0) * 4;
  final sum = c + f + p;
  if (!isLogged(d) || sum <= 0) return null;
  final k = d.caloriesTracked / sum;
  return (carbs: c * k, fat: f * k, protein: p * k);
}

/// Water a day over the window; null where none was logged.
DaySeries waterSeries(Map<DateTime, int> byDay, List<DateTime> dates) => [
  for (final date in dates)
    if ((byDay[date] ?? 0) > 0) byDay[date]!.toDouble() else null,
];

/// The expenditure estimate a day over the window, from [history].
DaySeries expenditureSeries(
  List<ExpenditureDay> history,
  List<DateTime> dates,
) {
  final byDate = {for (final d in history) _date(d.date): d};
  return [for (final date in dates) byDate[date]?.expenditureKcal];
}

/// Eaten less burnt a day over the window, on the logged days.
DaySeries balanceSeries(List<ExpenditureDay> history, List<DateTime> dates) {
  final byDate = {for (final d in history) _date(d.date): d};
  return [
    for (final date in dates)
      if (byDate[date] case ExpenditureDay(
        :final intakeKcal?,
        :final expenditureKcal,
      ))
        intakeKcal - expenditureKcal
      else
        null,
  ];
}

/// The weight trend over the window, in kg: the smoothed trend carried on
/// to today, its value now, its change over the window and a week's rate,
/// as the weight card's outlook (S93) and the Goal planner read it.
class WeightTrendStats {
  /// One a day from the window's first day with a trend, oldest first.
  final DaySeries trend;
  final double? nowKg;
  final double? changeKg;
  final double? perWeekKg;

  const WeightTrendStats({
    required this.trend,
    this.nowKg,
    this.changeKg,
    this.perWeekKg,
  });

  factory WeightTrendStats.of(
    List<WeightLogEntity> entries,
    List<DateTime> dates,
  ) {
    if (dates.isEmpty) return const WeightTrendStats(trend: []);
    final today = dates.last;
    final all = trendPoints(entries, until: today);
    final byDate = {for (final p in all) _date(p.date): p.weightKg};
    final trend = [for (final d in dates) byDate[d]];
    final present = trend.whereType<double>().toList();
    if (present.isEmpty) return WeightTrendStats(trend: trend);
    // From the day before the window, as S93's outlook: a week's range
    // spans seven days of change.
    final from = DateTime(
      dates.first.year,
      dates.first.month,
      dates.first.day - 1,
    );
    final points = [
      for (final p in all)
        if (!p.date.isBefore(from) && !p.date.isAfter(today))
          (date: p.date, kg: p.weightKg),
    ];
    final rate = points.length < 2
        ? null
        : weightProjection([points.first, points.last], null)?.ratePerWeek;
    return WeightTrendStats(
      trend: trend,
      nowKg: present.last,
      changeKg: points.length < 2 ? null : points.last.kg - points.first.kg,
      perWeekKg: rate,
    );
  }
}

/// [kg] in the user's unit, decimal stones for stones.
double weightIn(BodyWeightUnit unit, double kg) => switch (unit) {
  BodyWeightUnit.kg => kg,
  BodyWeightUnit.lb => UnitCalc.kgToLbs(kg),
  BodyWeightUnit.st => UnitCalc.kgToLbs(kg) / 14,
};

/// The footer's range, "Last 7 days" or "All time".
String rangeText(int rangeDays, int windowDays) =>
    rangeDays == 0 ? 'All time' : 'Last $windowDays days';
