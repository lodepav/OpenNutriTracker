import 'package:opennutritracker/fork/adaptive/expenditure.dart';

/// Logged days that look only partly logged (D65). A day logged at half
/// counts as a day of eating half, which pulls the estimate down and never
/// up: one such day in twenty reads the expenditure about 60 kcal low, and
/// a target that follows it loses weight the user never asked to lose
/// (fork/research/phase3-simulation.md, "Closed loop"). The estimator can
/// not tell such a day from a light one, so these are only pointed out:
/// the user leaves one out or says it is whole.

/// A day under this share of the usual intake looks partly logged.
const partialDayShare = 0.6;

/// The usual intake is the median of the other logged days within this
/// many days either side, and needs this many of them.
const partialDaySpanDays = 14;
const partialDayMinLogged = 7;

/// With more than this share of the days around it as low, a low day is a
/// habit (a fasting day, say) rather than a slip, and is not pointed out.
const partialDayHabitShare = 0.2;

/// The days of [days] that look partly logged, by index, each with the
/// usual intake around it. A day not logged (under [minLoggedKcal]) is
/// already left out and is none of them.
List<({int day, double usualKcal})> likelyPartlyLogged(List<AdaptiveDay> days) {
  bool logged(int i) => (days[i].intakeKcal ?? 0) >= minLoggedKcal;
  final out = <({int day, double usualKcal})>[];
  for (var i = 0; i < days.length; i++) {
    if (!logged(i)) continue;
    final around = [
      for (
        var j = (i - partialDaySpanDays).clamp(0, days.length);
        j < days.length && j <= i + partialDaySpanDays;
        j++
      )
        if (j != i && logged(j)) days[j].intakeKcal!,
    ]..sort();
    if (around.length < partialDayMinLogged) continue;
    final usual = around.length.isOdd
        ? around[around.length ~/ 2]
        : (around[around.length ~/ 2 - 1] + around[around.length ~/ 2]) / 2;
    final low = partialDayShare * usual;
    if (days[i].intakeKcal! >= low) continue;
    final asLow = around.where((kcal) => kcal < low).length;
    if (asLow > partialDayHabitShare * around.length) continue;
    out.add((day: i, usualKcal: usual));
  }
  return out;
}
