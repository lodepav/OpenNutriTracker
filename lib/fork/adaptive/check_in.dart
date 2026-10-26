import 'dart:math';

import 'package:opennutritracker/fork/adaptive/adaptive_store.dart';
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

  /// Upstream's formula expenditure alone, for the first check-in to say
  /// how the prior differs from it; null after the first.
  final double? formulaKcal;

  /// kg per week, negative to lose.
  final double goalRateKgPerWeek;
  final double bodyFatPercent;
  final double? targetWeightKg;

  /// The estimate the last check-in's target was built on (its
  /// [CheckIn.baseKcal]); null before the first.
  final double? previousBaseKcal;

  /// The activity the last check-in's target carried (weekly mode), so
  /// the check-in can say what the past week's moved; null before the
  /// first.
  final double? previousActivityKcal;

  /// The most the estimate under the target moves in a check-in, null for
  /// no limit. The goal's energy is not held back: a goal changed is
  /// meant at once (D18).
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
    this.formulaKcal,
    required this.goalRateKgPerWeek,
    required this.bodyFatPercent,
    required this.previousBaseKcal,
    this.previousActivityKcal,
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

  /// The estimate the target is built on, before activity: moved at most
  /// the cap from the last check-in's, except while it calibrates.
  final double baseKcal;

  /// The target were the estimate not capped.
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

  /// The goal the target was set for, so a changed one is due a check-in
  /// (D18).
  final double goalRateKgPerWeek;
  final double? targetWeightKg;

  /// In the weekly mode, how far the past week's activity moves the
  /// target from the last check-in's, outside the cap; null otherwise or
  /// before the first.
  final double? activityChangeKcal;

  /// [CheckInInputs.formulaKcal], while [fromProfile].
  final double? formulaKcal;

  /// The energy a kg of weight change counts as, which the goal's pace is
  /// turned into energy at.
  final double? kcalPerKg;

  /// The first check-in, and no weigh-in and log has shaped the estimate
  /// yet: it is the profile's prior, as for a new user.
  bool get fromProfile => formulaKcal != null;

  const CheckIn({
    required this.averageIntakeKcal,
    required this.loggedDays,
    required this.weighIns,
    required this.trendKg,
    required this.weekChangeKg,
    required this.expenditureKcal,
    this.activityKcal,
    required this.baseKcal,
    required this.uncappedTargetKcal,
    required this.proposedTargetKcal,
    required this.daysToTargetAtGoal,
    required this.daysToTargetAtTrend,
    this.goalRateKgPerWeek = 0,
    this.targetWeightKg,
    this.activityChangeKcal,
    this.formulaKcal,
    this.kcalPerKg,
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
  final run = estimateExpenditureRun(
    days,
    priorKcal: inputs.priorKcal,
    bodyFatPercent: inputs.bodyFatPercent,
    settings: inputs.settings,
  );
  final base = run.estimates.last;
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
  final kcalPerKg = inputs.settings.kcalPerKgAt(weight, inputs.bodyFatPercent);
  final goalKcal = inputs.goalRateKgPerWeek * kcalPerKg / 7;
  final goalEnergy = inputs.taper(goalKcal, weight);
  final previous = inputs.previousBaseKcal;
  final cap = inputs.maxChangeKcal;
  // While calibrating the estimate leaves the formula's prior fast, as it
  // should; the cap is for a settled one's odd week (D18).
  final cappedBase =
      cap == null ||
          previous == null ||
          run.updates < inputs.settings.calibrationUpdates
      ? base
      : base.clamp(previous - cap, previous + cap);
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
    baseKcal: cappedBase,
    uncappedTargetKcal: base + goalEnergy + weekly,
    proposedTargetKcal: cappedBase + goalEnergy + weekly,
    daysToTargetAtGoal: daysAt(inputs.goalRateKgPerWeek / 7),
    daysToTargetAtTrend: daysAt(
      now == null || windowAgo == null ? null : (now - windowAgo) / 20,
    ),
    goalRateKgPerWeek: inputs.goalRateKgPerWeek,
    targetWeightKg: inputs.targetWeightKg,
    activityChangeKcal:
        inputs.activityMode == ActivityMode.weekly &&
            inputs.previousActivityKcal != null
        ? weekly - inputs.previousActivityKcal!
        : null,
    formulaKcal: run.updates == 0 ? inputs.formulaKcal : null,
    kcalPerKg: kcalPerKg,
  );
}
