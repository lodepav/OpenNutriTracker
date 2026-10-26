import 'package:opennutritracker/core/domain/entity/tracked_day_entity.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_service.dart';
import 'package:opennutritracker/fork/trends/trend_stats.dart';

/// The spans the Expenditure page's table of changes reads, in days.
const expenditureChangeSpans = [3, 7, 14, 30, 90];

DateTime _date(DateTime t) => DateTime(t.year, t.month, t.day);

/// The estimate now against its value [spans] days before, each with what
/// it was then; null where the history does not reach back that far.
List<({int days, double? change, double? then})> expenditureChanges(
  List<ExpenditureDay> history, {
  List<int> spans = expenditureChangeSpans,
}) {
  if (history.isEmpty) {
    return [for (final d in spans) (days: d, change: null, then: null)];
  }
  final byDate = {for (final d in history) _date(d.date): d.expenditureKcal};
  final last = history.last;
  final now = last.expenditureKcal;
  return [
    for (final d in spans)
      if (byDate[DateTime(last.date.year, last.date.month, last.date.day - d)]
          case final then?)
        (days: d, change: now - then, then: then)
      else
        (days: d, change: null, then: null),
  ];
}

/// How the last [days] of the estimate add up, over the days logged in
/// them: eaten a day, what the weight change made up (positive when weight
/// was lost, so burnt is eaten plus it), and burnt a day. Null with no day
/// logged.
({double eaten, double fromWeight, double burnt, int logged, int of})?
expenditureBreakdown(List<ExpenditureDay> history, {int days = 30}) {
  final span = history.length > days
      ? history.sublist(history.length - days)
      : history;
  final logged = [
    for (final d in span)
      if (d.intakeKcal != null) d,
  ];
  if (logged.isEmpty) return null;
  final eaten =
      logged.map((d) => d.intakeKcal!).reduce((a, b) => a + b) / logged.length;
  final burnt =
      logged.map((d) => d.expenditureKcal).reduce((a, b) => a + b) /
      logged.length;
  return (
    eaten: eaten,
    fromWeight: burnt - eaten,
    burnt: burnt,
    logged: logged.length,
    of: span.length,
  );
}

/// The share a day's energy may stray from its goal and count as on
/// target.
const onTargetShare = 0.10;

/// How the logged days of the window went against their goals, and the
/// highest and lowest of them.
({
  int onTarget,
  int under,
  int over,
  int logged,
  ({double kcal, DateTime date})? highest,
  ({double kcal, DateTime date})? lowest,
})
dayOutcomes(List<TrackedDayEntity> days, List<DateTime> dates) {
  final window = dates.toSet();
  final logged = [
    for (final d in days)
      if (isLogged(d) && window.contains(_date(d.day))) d,
  ];
  var onTarget = 0, under = 0, over = 0;
  for (final d in logged) {
    final goal = d.calorieGoal;
    if (goal <= 0) continue;
    final off = d.caloriesTracked - goal;
    if (off.abs() <= goal * onTargetShare) {
      onTarget++;
    } else if (off < 0) {
      under++;
    } else {
      over++;
    }
  }
  ({double kcal, DateTime date})? pick(bool Function(double, double) better) {
    if (logged.isEmpty) return null;
    final d = logged.reduce(
      (a, b) => better(b.caloriesTracked, a.caloriesTracked) ? b : a,
    );
    return (kcal: d.caloriesTracked, date: _date(d.day));
  }

  return (
    onTarget: onTarget,
    under: under,
    over: over,
    logged: logged.length,
    highest: pick((a, b) => a > b),
    lowest: pick((a, b) => a < b),
  );
}

/// The mean energy of the logged [days] by weekday (1 for Monday), and
/// over them all; null without a logged day.
({Map<int, double> byWeekday, double mean})? weekdayMeans(
  List<TrackedDayEntity> days,
) {
  final logged = days.where(isLogged).toList();
  if (logged.isEmpty) return null;
  final sums = <int, (double, int)>{};
  for (final d in logged) {
    final (sum, n) = sums[d.day.weekday] ?? (0.0, 0);
    sums[d.day.weekday] = (sum + d.caloriesTracked, n + 1);
  }
  return (
    byWeekday: {
      for (final MapEntry(:key, :value) in sums.entries)
        key: value.$1 / value.$2,
    },
    mean:
        logged.map((d) => d.caloriesTracked).reduce((a, b) => a + b) /
        logged.length,
  );
}

/// The weekday furthest from [means]' overall mean, and by how much, once
/// it is at least [atLeast] kcal off; null when none is.
({int weekday, double off})? standoutWeekday(
  ({Map<int, double> byWeekday, double mean}) means, {
  double atLeast = 150,
}) {
  ({int weekday, double off})? best;
  for (final MapEntry(:key, :value) in means.byWeekday.entries) {
    final off = value - means.mean;
    if (off.abs() >= atLeast && (best == null || off.abs() > best.off.abs())) {
      best = (weekday: key, off: off);
    }
  }
  return best;
}

/// The share of the window's energy each macro gave, by 4, 9 and 4 kcal a
/// gram, and the share its mean goal would; null without macros logged.
({
  ({double carbs, double fat, double protein}) eaten,
  ({double carbs, double fat, double protein})? goal,
})?
macroShares(List<TrackedDayEntity> days, List<DateTime> dates) {
  double sum(double? Function(TrackedDayEntity) grams) => nutritionSeries(
    days,
    dates,
    grams,
  ).whereType<double>().fold(0.0, (a, b) => a + b);
  final c = sum((d) => d.carbsTracked) * 4;
  final f = sum((d) => d.fatTracked) * 9;
  final p = sum((d) => d.proteinTracked) * 4;
  final total = c + f + p;
  if (total <= 0) return null;
  final gc = (goalOf(days, dates, (d) => d.carbsGoal) ?? 0) * 4;
  final gf = (goalOf(days, dates, (d) => d.fatGoal) ?? 0) * 9;
  final gp = (goalOf(days, dates, (d) => d.proteinGoal) ?? 0) * 4;
  final goalTotal = gc + gf + gp;
  return (
    eaten: (carbs: c / total, fat: f / total, protein: p / total),
    goal: goalTotal <= 0
        ? null
        : (carbs: gc / goalTotal, fat: gf / goalTotal, protein: gp / goalTotal),
  );
}
