import 'package:opennutritracker/fork/adaptive/energy.dart';

/// What the goal planner starts from, read by `AdaptiveService.goalPlan`.
class GoalPlanInputs {
  /// The smoothed trend over the past days, oldest first, the last today.
  final List<double> pastTrendKg;

  /// kg a day over the past 20 days of the trend; null with less history.
  final double? trendKgPerDay;
  final double expenditureKcal;
  final double bodyFatPercent;
  final double? targetWeightKg;

  /// The pace saved in the profile, kg a week.
  final double paceKgPerWeek;

  const GoalPlanInputs({
    required this.pastTrendKg,
    required this.trendKgPerDay,
    required this.expenditureKcal,
    required this.bodyFatPercent,
    required this.targetWeightKg,
    required this.paceKgPerWeek,
  });

  double get nowKg => pastTrendKg.last;
}

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
        perDay * energyDensity(fatMassKg(now, inputs.bodyFatPercent)),
  );
}
