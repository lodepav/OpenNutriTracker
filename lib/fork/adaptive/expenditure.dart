import 'package:opennutritracker/fork/adaptive/energy.dart';
import 'package:opennutritracker/fork/adaptive/trend.dart';

/// One day as the estimator sees it: what was logged (null when the day
/// was not logged) and the weigh-in, if any.
class AdaptiveDay {
  final double? intakeKcal;
  final double? weightKg;

  const AdaptiveDay({this.intakeKcal, this.weightKg});
}

/// The weights the simulator tunes (fork/research/phase3-simulation.md).
class ExpenditureSettings {
  /// Weight of each new day in the trend.
  final double alpha;

  /// Days the change in trend is measured over (MacroFactor: 20).
  final int window;

  /// Share of the gap to the day's raw estimate taken, during the first
  /// [calibrationDays] and after.
  final double calibrationBlend;
  final double blend;
  final int calibrationDays;

  /// Days of data before the first update, so the trend has settled.
  final int warmupDays;

  const ExpenditureSettings({
    this.alpha = 0.1,
    this.window = 20,
    this.calibrationBlend = 0.2,
    this.blend = 0.05,
    this.calibrationDays = 30,
    this.warmupDays = 14,
  });
}

/// A day's intake counts only above this: a day under it is taken as not
/// logged rather than as a fast (SparkyFitness's safety net).
const minLoggedKcal = 200.0;

/// Expenditure estimated each day by energy balance (D13): mean logged
/// intake over the window less the energy of the trend's change, blended
/// into the running estimate, which starts at [priorKcal]. A day whose
/// past week has under 4 logged days or no weigh-in carries the last
/// estimate (MacroFactor's data rules). [bodyFatPercent] null uses the
/// flat 6,000 kcal/kg.
List<double> estimateExpenditure(
  List<AdaptiveDay> days, {
  required double priorKcal,
  double? bodyFatPercent,
  ExpenditureSettings settings = const ExpenditureSettings(),
}) {
  final trend = smoothedTrend(
    dailyWeights({
      for (final (i, d) in days.indexed)
        if (d.weightKg != null) i: d.weightKg!,
    }, days.length),
    alpha: settings.alpha,
  );
  bool logged(AdaptiveDay d) => (d.intakeKcal ?? 0) >= minLoggedKcal;

  var estimate = priorKcal;
  final out = <double>[];
  for (var day = 0; day < days.length; day++) {
    final week = days.sublist((day - 6).clamp(0, day), day + 1);
    final enoughData =
        day >= settings.warmupDays &&
        week.where(logged).length >= 4 &&
        week.any((d) => d.weightKg != null);
    final start = (day - settings.window).clamp(0, day);
    final from = trend[start], to = trend[day];
    if (enoughData && from != null && to != null && day > start) {
      final intakes = [
        for (final d in days.sublist(start + 1, day + 1))
          if (logged(d)) d.intakeKcal!,
      ];
      final meanIntake = intakes.reduce((a, b) => a + b) / intakes.length;
      final density = bodyFatPercent == null
          ? flatKcalPerKg
          : energyDensity(fatMassKg((from + to) / 2, bodyFatPercent));
      final stored = (to - from) * density / (day - start);
      final raw = meanIntake - stored;
      final weight = day < settings.calibrationDays
          ? settings.calibrationBlend
          : settings.blend;
      estimate += weight * (raw - estimate);
    }
    out.add(estimate);
  }
  return out;
}
