import 'dart:math';

import 'package:opennutritracker/fork/adaptive/energy.dart';
import 'package:opennutritracker/fork/adaptive/expenditure.dart';

/// Synthetic users with a known expenditure, to tune and check the
/// estimator (D13, phase 3 step 1). Pure Dart, used only by tests and
/// `fork/tools/tune_adaptive.dart`; the app never imports it. Inputs and
/// their sources: fork/research/phase3-macrofactor-algorithms.md,
/// "Simulator inputs".
class SimUser {
  final String name;
  final double startWeightKg;
  final double bodyFatPercent;

  /// True expenditure at the start weight.
  final double baseKcal;

  /// What the user eats each day, before day-to-day variation.
  final double plannedIntakeKcal;

  /// Share of what is eaten that gets logged, on an ordinary day.
  final double loggingShare;

  /// Chance a day is not logged at all, and that a logged day is only
  /// partly logged (half of it).
  final double unloggedChance;
  final double partlyLoggedChance;

  /// Chance of no weigh-in on a day.
  final double missedWeighInChance;

  /// SD of day-to-day water noise on the scale.
  final double noiseKg;

  /// Amplitude of a ~28-day water swing (0 for none).
  final double cycleKg;

  /// A step change in expenditure ([stepKcal] from [stepDay] on), for
  /// responsiveness.
  final int? stepDay;
  final double stepKcal;

  const SimUser({
    required this.name,
    required this.startWeightKg,
    required this.bodyFatPercent,
    required this.baseKcal,
    required this.plannedIntakeKcal,
    this.loggingShare = 0.9,
    this.unloggedChance = 0.1,
    this.partlyLoggedChance = 0.05,
    this.missedWeighInChance = 0.3,
    this.noiseKg = 0.5,
    this.cycleKg = 0,
    this.stepDay,
    this.stepKcal = 0,
  });
}

/// One simulated run: what the app would see, and the truth.
class SimRun {
  final SimUser user;
  final List<AdaptiveDay> observed;

  /// True expenditure each day, in logged calories: what an estimator fed
  /// logged intake can at best find (a steady under-log is invisible to it
  /// and harmless to targets in the same currency).
  final List<double> truthLogged;

  const SimRun(this.user, this.observed, this.truthLogged);
}

/// Expenditure falls with weight lost, plus a small adaptive drop while in
/// deficit (research doc, "Truth model"; ours).
const _kcalPerKgLost = 22.0;
const _adaptiveShare = 0.05;

SimRun simulate(SimUser user, {int days = 180, int seed = 1}) {
  final random = Random(seed);
  double gaussian() {
    // Box-Muller.
    final u = 1 - random.nextDouble(), v = random.nextDouble();
    return sqrt(-2 * log(u)) * cos(2 * pi * v);
  }

  var weight = user.startWeightKg;
  var fat = fatMassKg(weight, user.bodyFatPercent);
  final observed = <AdaptiveDay>[];
  final truth = <double>[];
  // Two multi-day water shifts (salt, carbs), ±0.8 kg over 4 days.
  final shifts = {
    for (var i = 0; i < 2; i++) 20 + random.nextInt(days - 40): gaussian(),
  };
  for (var day = 0; day < days; day++) {
    final eaten = user.plannedIntakeKcal * (1 + 0.1 * gaussian());
    final step = user.stepDay != null && day >= user.stepDay! ? 1 : 0;
    final deficit = (user.baseKcal - eaten).clamp(0, double.infinity);
    final expenditure =
        user.baseKcal -
        _kcalPerKgLost * (user.startWeightKg - weight) -
        _adaptiveShare * deficit +
        step * user.stepKcal;
    truth.add(expenditure * user.loggingShare);

    final change = (eaten - expenditure) / energyDensity(fat);
    fat += fatShare(fat) * change;
    weight += change;

    final water =
        0.0035 * weight * sin(2 * pi * day / 7) +
        user.cycleKg * sin(2 * pi * day / 28) +
        [
          for (final MapEntry(key: at, value: size) in shifts.entries)
            if (day >= at && day < at + 4) 0.8 * size,
        ].fold(0.0, (a, b) => a + b);
    final scale = weight + water + user.noiseKg * gaussian();

    final roll = random.nextDouble();
    final logged = roll < user.unloggedChance
        ? null
        : eaten *
              user.loggingShare *
              (roll < user.unloggedChance + user.partlyLoggedChance ? 0.5 : 1);
    observed.add(
      AdaptiveDay(
        intakeKcal: logged,
        weightKg: random.nextDouble() < user.missedWeighInChance
            ? null
            : double.parse(scale.toStringAsFixed(1)),
      ),
    );
  }
  return SimRun(user, observed, truth);
}

/// MacroFactor's three measures, after the first [settleDays].
class SimScore {
  /// Mean |estimate − truth|, kcal/day.
  final double error;

  /// Mean |day-to-day change| of the estimate, kcal/day per day.
  final double stability;

  /// Days after a step until the estimate has moved 80% of it; null for a
  /// user without a step, or one never followed.
  final int? responseDays;

  const SimScore(this.error, this.stability, this.responseDays);
}

SimScore score(SimRun run, List<double> estimate, {int settleDays = 30}) {
  var error = 0.0, moved = 0.0;
  for (var d = settleDays; d < estimate.length; d++) {
    error += (estimate[d] - run.truthLogged[d]).abs();
    moved += (estimate[d] - estimate[d - 1]).abs();
  }
  final n = estimate.length - settleDays;
  int? response;
  final step = run.user.stepDay;
  if (step != null) {
    final before = estimate[step - 1];
    final target = run.user.stepKcal * run.user.loggingShare * 0.8;
    for (var d = step; d < estimate.length; d++) {
      if ((estimate[d] - before) * target.sign >= target.abs()) {
        response = d - step;
        break;
      }
    }
  }
  return SimScore(error / n, moved / n, response);
}

/// The users every tuning run is scored on: losing, maintaining and
/// gaining; lean and heavy; careful and sloppy loggers; a step up and a
/// step down in activity; two with a menstrual water swing.
const simUsers = [
  SimUser(
    name: 'losing, heavy',
    startWeightKg: 105,
    bodyFatPercent: 35,
    baseKcal: 2900,
    plannedIntakeKcal: 2200,
  ),
  SimUser(
    name: 'losing, lean',
    startWeightKg: 72,
    bodyFatPercent: 18,
    baseKcal: 2500,
    plannedIntakeKcal: 2100,
  ),
  SimUser(
    name: 'maintaining',
    startWeightKg: 80,
    bodyFatPercent: 22,
    baseKcal: 2600,
    plannedIntakeKcal: 2600,
  ),
  SimUser(
    name: 'gaining',
    startWeightKg: 68,
    bodyFatPercent: 15,
    baseKcal: 2700,
    plannedIntakeKcal: 3000,
  ),
  SimUser(
    name: 'sloppy logger',
    startWeightKg: 90,
    bodyFatPercent: 30,
    baseKcal: 2700,
    plannedIntakeKcal: 2200,
    loggingShare: 0.75,
    unloggedChance: 0.3,
    partlyLoggedChance: 0.15,
    missedWeighInChance: 0.6,
    noiseKg: 0.8,
  ),
  SimUser(
    name: 'more active from day 90',
    startWeightKg: 85,
    bodyFatPercent: 25,
    baseKcal: 2600,
    plannedIntakeKcal: 2300,
    stepDay: 90,
    stepKcal: 300,
  ),
  SimUser(
    name: 'less active from day 90',
    startWeightKg: 78,
    bodyFatPercent: 24,
    baseKcal: 2700,
    plannedIntakeKcal: 2400,
    stepDay: 90,
    stepKcal: -300,
  ),
  SimUser(
    name: 'cycle, losing',
    startWeightKg: 75,
    bodyFatPercent: 32,
    baseKcal: 2200,
    plannedIntakeKcal: 1750,
    cycleKg: 0.8,
  ),
  SimUser(
    name: 'cycle, maintaining',
    startWeightKg: 62,
    bodyFatPercent: 27,
    baseKcal: 2000,
    plannedIntakeKcal: 2000,
    cycleKg: 1.0,
  ),
];

/// The prior the app would start from: the true base expenditure off by
/// [priorError] (upstream's formula is a population estimate), times the
/// logging share it cannot know about.
double simPrior(SimUser user, {double priorError = 0.1}) =>
    user.baseKcal * (1 + priorError);

typedef SimSummary = ({double error, double stability, double? responseDays});

/// Every user in [users], each over [seeds], with [settings]; the mean of
/// each score. [forbes] false uses the flat 6,000 kcal/kg.
SimSummary scoreAll(
  ExpenditureSettings settings, {
  List<SimUser> users = simUsers,
  int seeds = 5,
  double priorError = 0.1,
  bool forbes = true,
}) {
  var error = 0.0, stability = 0.0, response = 0.0;
  var runs = 0, responses = 0;
  for (final user in users) {
    for (var seed = 1; seed <= seeds; seed++) {
      final run = simulate(user, seed: seed);
      final estimate = estimateExpenditure(
        run.observed,
        priorKcal: simPrior(user, priorError: priorError),
        bodyFatPercent: forbes ? user.bodyFatPercent : null,
        settings: settings,
      );
      final s = score(run, estimate);
      error += s.error;
      stability += s.stability;
      runs++;
      if (s.responseDays case final days?) {
        response += days;
        responses++;
      }
    }
  }
  return (
    error: error / runs,
    stability: stability / runs,
    responseDays: responses == 0 ? null : response / responses,
  );
}
