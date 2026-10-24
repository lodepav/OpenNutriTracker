import 'dart:math';

import 'package:opennutritracker/fork/adaptive/adaptive_store.dart';
import 'package:opennutritracker/fork/adaptive/energy.dart';
import 'package:opennutritracker/fork/adaptive/expenditure.dart';
import 'package:opennutritracker/fork/adaptive/trend.dart';

/// What a check-in needs, gathered by `AdaptiveService` from upstream's
/// weight log, tracked days and profile.
class CheckInInputs {
  /// Oldest first, the last one today.
  final List<AdaptiveDay> days;

  /// Upstream's formula expenditure × (1 + 4 × goal rate), MacroFactor's
  /// prior.
  final double priorKcal;

  /// kg per week, negative to lose.
  final double goalRateKgPerWeek;
  final double bodyFatPercent;
  final double? targetWeightKg;

  /// The target the last check-in set, or upstream's formula target
  /// before the first, less the week's activity it carried.
  final double previousTargetKcal;

  /// The most the target moves, null for no limit.
  final double? maxChangeKcal;

  /// How counted activity reaches the target (D17).
  final ActivityMode activityMode;

  /// Upstream's taper towards the target weight, applied to the goal's
  /// energy as upstream applies it to its adjustment.
  final double Function(double adjustment, double currentWeightKg) taper;
  final ExpenditureSettings settings;

  const CheckInInputs({
    required this.days,
    required this.priorKcal,
    required this.goalRateKgPerWeek,
    required this.bodyFatPercent,
    required this.previousTargetKcal,
    required this.taper,
    this.targetWeightKg,
    this.settings = const ExpenditureSettings(),
    this.maxChangeKcal = AdaptiveSettings.defaultMaxCheckInChangeKcal,
    this.activityMode = ActivityMode.off,
  });
}

class CheckIn {
  /// Mean over the past week's logged days, null when none.
  final double? averageIntakeKcal;
  final int loggedDays;
  final int weighIns;

  /// The trend now and its change over the past week, null with no
  /// weigh-in yet.
  final double? trendKg;
  final double? weekChangeKg;

  /// The estimate with the past week's mean counted activity added back
  /// (D17); the whole estimate when none is counted.
  final double expenditureKcal;

  /// The past week's mean counted activity, null when none is counted.
  final double? activityKcal;

  /// Expenditure plus the goal's energy, tapered, before the cap.
  final double uncappedTargetKcal;

  /// The target to accept: in the weekly mode it carries [activityKcal],
  /// which the cap leaves out; in the daily mode it is the base each
  /// day's activity is added to.
  final double proposedTargetKcal;

  /// Days to the target weight at the chosen pace, and at the trend's own
  /// pace over the past 20 days; null when there is no target, it is
  /// reached, or the pace leads away from it.
  final int? daysToTargetAtGoal;
  final int? daysToTargetAtTrend;

  const CheckIn({
    required this.averageIntakeKcal,
    required this.loggedDays,
    required this.weighIns,
    required this.trendKg,
    required this.weekChangeKg,
    required this.expenditureKcal,
    this.activityKcal,
    required this.uncappedTargetKcal,
    required this.proposedTargetKcal,
    required this.daysToTargetAtGoal,
    required this.daysToTargetAtTrend,
  });

  /// MacroFactor's data rule for the week: 4 logged days and a weigh-in.
  bool get enoughData => loggedDays >= 4 && weighIns >= 1;

  /// What [proposedTargetKcal] carries of the week's activity: the part the
  /// next check-in's cap leaves out.
  double activityInTarget(ActivityMode mode) =>
      mode == ActivityMode.weekly ? activityKcal ?? 0 : 0;
}

CheckIn computeCheckIn(CheckInInputs inputs) {
  final days = inputs.days;
  final base = estimateExpenditure(
    days,
    priorKcal: inputs.priorKcal,
    bodyFatPercent: inputs.bodyFatPercent,
    settings: inputs.settings,
  ).last;
  final trend = smoothedTrend(
    dailyWeights({
      for (final (i, d) in days.indexed)
        if (d.weightKg != null) i: d.weightKg!,
    }, days.length),
    alpha: inputs.settings.alpha,
  );
  final week = days.sublist(max(0, days.length - 7));
  final logged = [
    for (final d in week)
      if ((d.intakeKcal ?? 0) >= minLoggedKcal) d.intakeKcal!,
  ];
  final now = trend.last;
  final weekAgo = trend.length > 7 ? trend[trend.length - 8] : null;
  final windowAgo = trend.length > 20 ? trend[trend.length - 21] : null;
  final activity = inputs.activityMode == ActivityMode.off
      ? null
      : meanActivity(week);

  final weight = now ?? 70.0;
  final goalKcal =
      inputs.goalRateKgPerWeek *
      energyDensity(fatMassKg(weight, inputs.bodyFatPercent)) /
      7;
  final baseTarget = base + inputs.taper(goalKcal, weight);
  final previous = inputs.previousTargetKcal;
  final cap = inputs.maxChangeKcal;
  final capped = cap == null
      ? baseTarget
      : baseTarget.clamp(previous - cap, previous + cap);
  final weekly = inputs.activityMode == ActivityMode.weekly ? activity ?? 0 : 0;

  int? daysAt(double? kgPerDay) {
    final target = inputs.targetWeightKg;
    if (target == null || now == null || kgPerDay == null) return null;
    final toGo = target - now;
    if (toGo.abs() < 0.1 || kgPerDay == 0 || toGo.sign != kgPerDay.sign) {
      return null;
    }
    return (toGo / kgPerDay).round();
  }

  return CheckIn(
    averageIntakeKcal: logged.isEmpty
        ? null
        : logged.reduce((a, b) => a + b) / logged.length,
    loggedDays: logged.length,
    weighIns: week.where((d) => d.weightKg != null).length,
    trendKg: now,
    weekChangeKg: now == null || weekAgo == null ? null : now - weekAgo,
    expenditureKcal: base + (activity ?? 0),
    activityKcal: activity,
    uncappedTargetKcal: baseTarget + weekly,
    proposedTargetKcal: capped + weekly,
    daysToTargetAtGoal: daysAt(inputs.goalRateKgPerWeek / 7),
    daysToTargetAtTrend: daysAt(
      now == null || windowAgo == null ? null : (now - windowAgo) / 20,
    ),
  );
}
