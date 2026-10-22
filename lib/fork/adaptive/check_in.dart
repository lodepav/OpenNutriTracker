import 'dart:math';

import 'package:opennutritracker/fork/adaptive/energy.dart';
import 'package:opennutritracker/fork/adaptive/expenditure.dart';
import 'package:opennutritracker/fork/adaptive/trend.dart';

/// The most a check-in moves the target, kcal/day (ours, after
/// MacroFactor's "a stall worth −500 gives −200 to −300").
const maxCheckInChangeKcal = 200.0;

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
  /// before the first.
  final double previousTargetKcal;

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
  final double expenditureKcal;

  /// Expenditure plus the goal's energy, tapered, before the cap.
  final double uncappedTargetKcal;
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
    required this.uncappedTargetKcal,
    required this.proposedTargetKcal,
    required this.daysToTargetAtGoal,
    required this.daysToTargetAtTrend,
  });

  /// MacroFactor's data rule for the week: 4 logged days and a weigh-in.
  bool get enoughData => loggedDays >= 4 && weighIns >= 1;
}

CheckIn computeCheckIn(CheckInInputs inputs) {
  final days = inputs.days;
  final expenditure = estimateExpenditure(
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

  final weight = now ?? 70.0;
  final goalKcal =
      inputs.goalRateKgPerWeek *
      energyDensity(fatMassKg(weight, inputs.bodyFatPercent)) /
      7;
  final uncapped = expenditure + inputs.taper(goalKcal, weight);
  final previous = inputs.previousTargetKcal;
  final proposed = uncapped.clamp(
    previous - maxCheckInChangeKcal,
    previous + maxCheckInChangeKcal,
  );

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
    expenditureKcal: expenditure,
    uncappedTargetKcal: uncapped,
    proposedTargetKcal: proposed,
    daysToTargetAtGoal: daysAt(inputs.goalRateKgPerWeek / 7),
    daysToTargetAtTrend: daysAt(
      now == null || windowAgo == null ? null : (now - windowAgo) / 20,
    ),
  );
}
