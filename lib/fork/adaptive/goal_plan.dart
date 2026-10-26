import 'package:opennutritracker/fork/adaptive/energy.dart';

/// What the goal planner starts from, read by `AdaptiveService.goalPlan`.
class GoalPlanInputs {
  /// The smoothed trend over the past days, oldest first, the last today.
  final List<double> pastTrendKg;

  /// kg a day over the past 30 days of the trend; null with less history.
  final double? trendKgPerDay;
  final double expenditureKcal;
  final double bodyFatPercent;
  final double? targetWeightKg;

  /// The pace saved in the profile, kg a week.
  final double paceKgPerWeek;

  /// A flat kcal per kg of change in place of body composition's (D19).
  final double? kcalPerKg;

  const GoalPlanInputs({
    required this.pastTrendKg,
    required this.trendKgPerDay,
    required this.expenditureKcal,
    required this.bodyFatPercent,
    required this.targetWeightKg,
    required this.paceKgPerWeek,
    this.kcalPerKg,
  });

  double get nowKg => pastTrendKg.last;
}

/// The spans MacroFactor's weight insights compare, in days.
const trendChangeDays = [7, 14, 30];

/// How far the trend moved over each of [trendChangeDays], in kg, from
/// [pastTrendKg] (oldest first, the last today); a span longer than the
/// history is left out.
Map<int, double> trendChanges(List<double> pastTrendKg) => {
  for (final days in trendChangeDays)
    if (pastTrendKg.length > days)
      days: pastTrendKg.last - pastTrendKg[pastTrendKg.length - 1 - days],
};

/// The plan at one pace.
class GoalPlan {
  /// From today on, one a day, at the pace until the target, then held.
  final List<double> projectedKg;

  /// Days to the target, possibly past the curve's [maxPlanDays]; null
  /// with no target, at it, or moving away.
  final int? daysToTarget;

  /// Expenditure plus the pace's energy, before the check-in's cap and
  /// upstream's taper.
  final double dailyTargetKcal;

  const GoalPlan({
    required this.projectedKg,
    required this.daysToTarget,
    required this.dailyTargetKcal,
  });
}

/// Days the projection runs when the target is out of reach.
const maxPlanDays = 365;

/// Days to [targetKg] from [nowKg] at [kgPerDay]; null when there is no
/// target, it is within 0.1 kg, or the pace leads away from it.
int? daysToTarget(double nowKg, double? targetKg, double kgPerDay) {
  if (targetKg == null) return null;
  final toGo = targetKg - nowKg;
  if (toGo.abs() < 0.1 || kgPerDay == 0 || toGo.sign != kgPerDay.sign) {
    return null;
  }
  return (toGo / kgPerDay).ceil();
}

/// The weight curve and daily target at [paceKgPerWeek].
GoalPlan planAt(GoalPlanInputs inputs, double paceKgPerWeek) {
  final perDay = paceKgPerWeek / 7;
  final now = inputs.nowKg;
  final days = daysToTarget(now, inputs.targetWeightKg, perDay);
  final length = days == null
      ? (inputs.targetWeightKg == null ? 182 : maxPlanDays)
      : (days + 14).clamp(28, maxPlanDays);
  final projected = [
    for (var d = 0; d <= length; d++)
      days != null && d >= days ? inputs.targetWeightKg! : now + perDay * d,
  ];
  return GoalPlan(
    projectedKg: projected,
    daysToTarget: days,
    dailyTargetKcal:
        inputs.expenditureKcal +
        perDay *
            (inputs.kcalPerKg ??
                energyDensity(fatMassKg(now, inputs.bodyFatPercent))),
  );
}

/// The milestone steps offered, in the unit's own numbers: kg for kg, lb
/// for lb and st. The planner stores the chosen one's place, 0 for none.
const milestoneStepsKg = [1, 2, 5];
const milestoneStepsLb = [2, 5, 10];

/// Round weights every [step] (in a unit [perKg] times a kg) strictly
/// between [nowKg] and [targetKg], nearest first, at most [max], in kg.
List<double> milestonesKg(
  double nowKg,
  double targetKg,
  num step, {
  double perKg = 1,
  int max = 5,
}) {
  final now = nowKg * perKg, target = targetKg * perKg;
  final down = target < now;
  var m = down
      ? (now / step).floor() * step.toDouble()
      : (now / step).ceil() * step.toDouble();
  // Not the weight already reached: within the 0.1 kg [daysToTarget]
  // counts as there, in the unit's own numbers.
  final near = 0.1 * perKg;
  if ((m - now).abs() < near) m += down ? -step : step;
  return [
    for (
      var i = 0;
      i < max && (down ? m > target + near : m < target - near);
      i++, m += down ? -step : step
    )
      m / perKg,
  ];
}
