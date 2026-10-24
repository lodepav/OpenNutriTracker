import 'dart:math';

import 'package:opennutritracker/fork/adaptive/energy.dart';
import 'package:opennutritracker/fork/adaptive/trend.dart';

/// One day as the estimator sees it: what was logged (null when the day
/// was not logged, or was left out), the weigh-in, if any, and the
/// activity counted on it (null when not known, or not counted).
class AdaptiveDay {
  final double? intakeKcal;
  final double? weightKg;
  final double? activityKcal;

  const AdaptiveDay({this.intakeKcal, this.weightKg, this.activityKcal});
}

/// How fast the estimate follows a change, against how much it wobbles
/// (D17; fork/research/phase3-simulation.md, "Responsiveness").
enum Responsiveness {
  steady('Steady'),
  standard('Standard'),
  responsive('Responsive');

  final String label;

  const Responsiveness(this.label);
}

/// The weights the simulator tunes (fork/research/phase3-simulation.md).
class ExpenditureSettings {
  /// Weight of each new day in the trend.
  final double alpha;

  /// Days the change in trend is measured over (MacroFactor: 20).
  final int window;

  /// Share of the gap to the day's raw estimate taken, during the first
  /// [calibrationUpdates] and after.
  final double calibrationBlend;
  final double blend;
  final int calibrationDays;

  /// Days from the first logged day to the first update, so the window
  /// has enough of them.
  final int warmupDays;

  /// kcal per kg of weight change; null follows body composition
  /// (Forbes via Hall), a flat 7,700 is how most apps count (D19).
  final double? kcalPerKg;

  /// Share of the window's days that must be logged for an update: the
  /// weight's change spans the whole window, the intake only its logged
  /// days, so after a gap a change while not logging would be priced at
  /// the logged days' intake (D18).
  final double minLoggedShare;

  const ExpenditureSettings({
    this.alpha = 0.1,
    this.window = 20,
    this.calibrationBlend = 0.2,
    this.blend = 0.05,
    this.calibrationDays = 30,
    this.warmupDays = defaultWarmupDays,
    this.minLoggedShare = defaultMinLoggedShare,
    this.kcalPerKg,
  });

  static const defaultMinLoggedShare = 0.6;
  static const defaultWarmupDays = 7;

  /// kcal in a kg of weight change at [weightKg]; [bodyFatPercent] null
  /// uses the flat 6,000 kcal/kg.
  double kcalPerKgAt(double weightKg, double? bodyFatPercent) =>
      kcalPerKg ??
      (bodyFatPercent == null
          ? flatKcalPerKg
          : energyDensity(fatMassKg(weightKg, bodyFatPercent)));

  /// Updates taken at [calibrationBlend]: as many as a user logging from
  /// the first weigh-in gets before day [calibrationDays].
  int get calibrationUpdates => calibrationDays - warmupDays;

  /// The preset's weights: only the blend moves, which the sweep found
  /// trades response for wobble at the least cost in error. [cycleWindow]
  /// reads 28 days, a whole cycle.
  factory ExpenditureSettings.of(
    Responsiveness responsiveness, {
    bool cycleWindow = false,
    double minLoggedShare = defaultMinLoggedShare,
    int warmupDays = defaultWarmupDays,
    double? kcalPerKg,
  }) => ExpenditureSettings(
    window: cycleWindow ? 28 : 20,
    minLoggedShare: minLoggedShare,
    warmupDays: warmupDays,
    kcalPerKg: kcalPerKg,
    blend: switch (responsiveness) {
      Responsiveness.steady => 0.03,
      Responsiveness.standard => 0.05,
      Responsiveness.responsive => 0.1,
    },
  );
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
///
/// With activity counted (D17) the window's mean counted activity is
/// taken off too, so the estimate is the base that activity is added
/// back to; without, it is the whole expenditure. The estimate before
/// activity is first counted holds that activity, so its first two weeks'
/// mean is taken off once, on the day it starts: the prior on day 0, the
/// running estimate when steps are switched on later. Once that day
/// leaves the history, the prior holds the subtraction instead, and the
/// estimates shift a little as the history slides.
List<double> estimateExpenditure(
  List<AdaptiveDay> days, {
  required double priorKcal,
  double? bodyFatPercent,
  ExpenditureSettings settings = const ExpenditureSettings(),
}) => estimateExpenditureRun(
  days,
  priorKcal: priorKcal,
  bodyFatPercent: bodyFatPercent,
  settings: settings,
).estimates;

/// [estimateExpenditure], with how many days updated the estimate (under
/// [ExpenditureSettings.calibrationUpdates] it is still calibrating) and
/// the first that did, null for none.
({List<double> estimates, int updates, int? firstUpdate})
estimateExpenditureRun(
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
  // Calibration counts updates, not days: weigh-ins before logging began
  // would otherwise use it up before the first update.
  var updates = 0;
  int? firstUpdate;
  final firstActive = days.indexWhere((d) => d.activityKcal != null);
  // The window reaches back no further than logging does: before it, the
  // weight moved on food that was never logged.
  final firstLogged = days.indexWhere(logged);
  final out = <double>[];
  for (var day = 0; day < days.length; day++) {
    if (day == firstActive) {
      estimate -=
          meanActivity(days.sublist(day, min(day + 14, days.length))) ?? 0;
    }
    final week = days.sublist((day - 6).clamp(0, day), day + 1);
    final enoughData =
        firstLogged >= 0 &&
        day - firstLogged + 1 >= settings.warmupDays &&
        week.where(logged).length >= 4 &&
        week.any((d) => d.weightKg != null);
    final start = max(day - settings.window, firstLogged - 1).clamp(0, day);
    final from = trend[start], to = trend[day];
    final window = days.sublist(start + 1, day + 1);
    final intakes = [
      for (final d in window)
        if (logged(d)) d.intakeKcal!,
    ];
    if (enoughData &&
        from != null &&
        to != null &&
        day > start &&
        intakes.length >= settings.minLoggedShare * window.length) {
      final meanIntake = intakes.reduce((a, b) => a + b) / intakes.length;
      final density = settings.kcalPerKgAt((from + to) / 2, bodyFatPercent);
      final stored = (to - from) * density / (day - start);
      final raw = meanIntake - stored - (meanActivity(window) ?? 0);
      final weight = updates < settings.calibrationUpdates
          ? settings.calibrationBlend
          : settings.blend;
      estimate += weight * (raw - estimate);
      firstUpdate ??= day;
      updates++;
    }
    out.add(estimate);
  }
  return (estimates: out, updates: updates, firstUpdate: firstUpdate);
}

/// Mean counted activity of the [days] that have it; null when none do.
double? meanActivity(Iterable<AdaptiveDay> days) {
  final known = [
    for (final d in days)
      if (d.activityKcal != null) d.activityKcal!,
  ];
  return known.isEmpty ? null : known.reduce((a, b) => a + b) / known.length;
}
