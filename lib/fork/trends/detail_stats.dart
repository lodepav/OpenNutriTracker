import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/tracked_day_entity.dart';
import 'package:opennutritracker/core/domain/entity/weight_log_entity.dart';
import 'package:opennutritracker/core/utils/calc/day_boundary_calc.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_service.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_store.dart';
import 'package:opennutritracker/fork/adaptive/trend_points.dart';
import 'package:opennutritracker/fork/report/nutrient_explorer.dart';
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

/// A day's highest or lowest: its energy or grams, and when.
typedef DayValue = ({double value, DateTime date});

/// How the logged days of the window went against their goals, and the
/// highest and lowest of them: the energy's, or [eaten] and [goal]'s, a
/// macro's grams.
({
  int onTarget,
  int under,
  int over,
  int logged,
  DayValue? highest,
  DayValue? lowest,
})
dayOutcomes(
  List<TrackedDayEntity> days,
  List<DateTime> dates, {
  double? Function(TrackedDayEntity) eaten = _calories,
  double? Function(TrackedDayEntity) goal = _calorieGoal,
}) {
  final window = dates.toSet();
  final logged = [
    for (final d in days)
      if (isLogged(d) && window.contains(_date(d.day)) && eaten(d) != null) d,
  ];
  var onTarget = 0, under = 0, over = 0;
  for (final d in logged) {
    final target = goal(d) ?? 0;
    if (target <= 0) continue;
    final off = eaten(d)! - target;
    if (off.abs() <= target * onTargetShare) {
      onTarget++;
    } else if (off < 0) {
      under++;
    } else {
      over++;
    }
  }
  DayValue? pick(bool Function(double, double) better) {
    if (logged.isEmpty) return null;
    final d = logged.reduce((a, b) => better(eaten(b)!, eaten(a)!) ? b : a);
    return (value: eaten(d)!, date: _date(d.day));
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

double? _calories(TrackedDayEntity d) => d.caloriesTracked;
double? _calorieGoal(TrackedDayEntity d) => d.calorieGoal;

/// Means over the logged days of a part of the week.
typedef WeekPart = ({
  int days,
  double kcal,
  double carbs,
  double fat,
  double protein,
  double? balance,
});

/// The window's logged weekdays (Monday to Friday) against its weekend
/// days, each averaged: energy, macros, and the balance where [balance]
/// has the day. Null unless both have a logged day.
({WeekPart weekdays, WeekPart weekend})? weekendSplit(
  List<TrackedDayEntity> days,
  List<DateTime> dates, {
  Map<DateTime, double> balance = const {},
}) {
  final window = dates.toSet();
  WeekPart? part(bool weekend) {
    final logged = [
      for (final d in days)
        if (isLogged(d) &&
            window.contains(_date(d.day)) &&
            (d.day.weekday >= DateTime.saturday) == weekend)
          d,
    ];
    if (logged.isEmpty) return null;
    double mean(double? Function(TrackedDayEntity) of) =>
        logged.map((d) => of(d) ?? 0).reduce((a, b) => a + b) / logged.length;
    final balances = [for (final d in logged) ?balance[_date(d.day)]];
    return (
      days: logged.length,
      kcal: mean((d) => d.caloriesTracked),
      carbs: mean((d) => d.carbsTracked),
      fat: mean((d) => d.fatTracked),
      protein: mean((d) => d.proteinTracked),
      balance: balances.isEmpty
          ? null
          : balances.reduce((a, b) => a + b) / balances.length,
    );
  }

  final weekdays = part(false), weekend = part(true);
  if (weekdays == null || weekend == null) return null;
  return (weekdays: weekdays, weekend: weekend);
}

/// The protein eaten a day for each kg of trend weight that day, over the
/// window's logged days that have a trend, and the goal's against the
/// latest trend. Null without such a day.
({double perKg, double? goalPerKg, int days})? proteinPerKg(
  List<TrackedDayEntity> days,
  List<DateTime> dates,
  Map<DateTime, double> trendByDay,
) {
  final window = dates.toSet();
  final ratios = <double>[];
  TrackedDayEntity? last;
  for (final d in days) {
    final date = _date(d.day);
    final kg = trendByDay[date];
    final grams = d.proteinTracked;
    if (!isLogged(d) || !window.contains(date) || kg == null || kg <= 0) {
      continue;
    }
    if (grams == null) continue;
    ratios.add(grams / kg);
    if (last == null || d.day.isAfter(last.day)) last = d;
  }
  if (ratios.isEmpty) return null;
  final goal = last!.proteinGoal;
  final latestKg = trendByDay[_date(last.day)]!;
  return (
    perKg: ratios.reduce((a, b) => a + b) / ratios.length,
    goalPerKg: goal == null || goal <= 0 ? null : goal / latestKg,
    days: ratios.length,
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

/// The window's logged days of energy balance: eaten and burnt a day, the
/// total eaten less burnt, and how many days ran in deficit or surplus.
/// Null with no day logged.
({
  double eaten,
  double burnt,
  double total,
  int deficit,
  int surplus,
  int logged,
})?
balanceSummary(List<ExpenditureDay> history, List<DateTime> dates) {
  final window = dates.toSet();
  final logged = [
    for (final d in history)
      if (d.intakeKcal != null && window.contains(_date(d.date))) d,
  ];
  if (logged.isEmpty) return null;
  var eaten = 0.0, burnt = 0.0, deficit = 0, surplus = 0;
  for (final d in logged) {
    eaten += d.intakeKcal!;
    burnt += d.expenditureKcal;
    final balance = d.intakeKcal! - d.expenditureKcal;
    if (balance < 0) deficit++;
    if (balance > 0) surplus++;
  }
  return (
    eaten: eaten / logged.length,
    burnt: burnt / logged.length,
    total: eaten - burnt,
    deficit: deficit,
    surplus: surplus,
    logged: logged.length,
  );
}

/// The weight change, in kg, that [days] at an average balance of
/// [meanKcal] a day would make, at [kcalPerKg] of body weight.
double balanceWeightKg(
  double meanKcal,
  int days, {
  double kcalPerKg = AdaptiveSettings.commonKcalPerKg,
}) => meanKcal * days / kcalPerKg;

/// How fully the window was logged, and how much of it the expenditure
/// estimate counts: of its days, those logged, those the estimate counts,
/// those [skipped] by the user, and those logged too lightly to count (only
/// over the days [history] covers, from the first weigh-in).
({int of, int logged, int counted, int skipped, int partial})
loggingCompleteness(
  List<TrackedDayEntity> days,
  List<ExpenditureDay> history,
  List<DateTime> dates,
  Set<DateTime> skipped,
) {
  final window = dates.toSet();
  final logged = {
    for (final d in days)
      if (isLogged(d) && window.contains(_date(d.day))) _date(d.day),
  };
  final covered = {
    for (final d in history)
      if (window.contains(_date(d.date))) _date(d.date): d.intakeKcal != null,
  };
  final left = {
    for (final d in skipped)
      if (window.contains(_date(d))) _date(d),
  };
  return (
    of: dates.length,
    logged: logged.length,
    counted: covered.values.where((c) => c).length,
    skipped: left.length,
    partial: [
      for (final d in logged)
        if (covered[d] == false && !left.contains(d)) d,
    ].length,
  );
}

/// The entries a logged day, over [intakes] counted on the logical days
/// the Diary lists them under; null with none.
double? entriesPerDay(List<IntakeEntity> intakes, {int dayStartMinutes = 0}) {
  if (intakes.isEmpty) return null;
  final days = {
    for (final i in intakes)
      DayBoundaryCalc.dayKeyOf(i.dateTime, dayStartMinutes),
  };
  return intakes.length / days.length;
}

/// How far the window's weigh-ins stray from the trend, in kg: the mean
/// distance, the largest (above the trend when positive) and its day, and
/// each day's last weigh-in less the trend that day; null without a
/// weigh-in in the window.
({
  double meanKg,
  ({double kg, DateTime on}) largest,
  Map<DateTime, double> byDay,
})?
scaleNoise(List<WeightLogEntity> entries, List<DateTime> dates) {
  final window = dates.toSet();
  final trend = {
    for (final p in trendPoints(entries)) _date(p.date): p.weightKg,
  };
  final byDay = <DateTime, double>{};
  for (final e in [...entries]..sort((a, b) => a.date.compareTo(b.date))) {
    final day = _date(e.date);
    if (!window.contains(day)) continue;
    if (trend[day] case final t?) byDay[day] = e.weightKg - t;
  }
  if (byDay.isEmpty) return null;
  final largest = byDay.entries.reduce(
    (a, b) => b.value.abs() > a.value.abs() ? b : a,
  );
  return (
    meanKg:
        byDay.values.map((v) => v.abs()).reduce((a, b) => a + b) / byDay.length,
    largest: (kg: largest.value, on: largest.key),
    byDay: byDay,
  );
}

/// The mean of [byDay]'s gaps to the trend on the mornings after the days
/// of [dates] whose [values] ran past [share] of their mean, beside the
/// mean on the other mornings, and how many mornings followed such a day;
/// null under [atLeast] of either.
({double after, double other, int days})? swingAfterHigh(
  Map<DateTime, double> byDay,
  List<DateTime> dates,
  List<double?> values, {
  double share = 1.2,
  int atLeast = 2,
}) {
  final known = values.whereType<double>().toList();
  if (known.isEmpty) return null;
  final mean = known.reduce((a, b) => a + b) / known.length;
  final after = <double>[], other = <double>[];
  for (var i = 1; i < dates.length; i++) {
    final gap = byDay[dates[i]];
    final before = values[i - 1];
    if (gap == null || before == null) continue;
    (before > mean * share ? after : other).add(gap);
  }
  if (after.length < atLeast || other.length < atLeast) return null;
  double avg(List<double> v) => v.reduce((a, b) => a + b) / v.length;
  return (after: avg(after), other: avg(other), days: after.length);
}

/// [nutrient] eaten each day of [dates], over [intakes] counted on the
/// Diary's logical days; null on a day no entry gives a figure for.
List<double?> nutrientByDay(
  List<IntakeEntity> intakes,
  List<DateTime> dates,
  ExplorerNutrient nutrient, {
  int dayStartMinutes = 0,
}) {
  final sums = <DateTime, double>{};
  for (final i in intakes) {
    final amount = nutrient.of(i);
    if (amount == null) continue;
    // A day label (a Diary or import entry's midnight) stays on its day,
    // as the Diary keeps it; a clock time moves by the boundary.
    final l = DayBoundaryCalc.dayLabelOf(i.dateTime, dayStartMinutes);
    final day = DateTime(l.year, l.month, l.day);
    sums[day] = (sums[day] ?? 0) + amount;
  }
  return [for (final d in dates) sums[d]];
}
