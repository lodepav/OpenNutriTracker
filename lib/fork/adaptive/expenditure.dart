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

/// Where a trend starts after a break (D27, D68): the first weigh-in a
/// week after the first one back, past the water the break's eating left,
/// its updates ramping in by the share of a full window they cover
/// ([afterHoldSoft]); or the first weigh-in back, as before D68
/// ([firstBack], kept as the closed-loop tool's baseline).
enum BreakAnchor { firstBack, afterHoldSoft }

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

  /// How far the intake's own trend may move across the window, as a share
  /// of its mean intake, before an update is taken at less than its weight
  /// ([shiftDeadband]) and at none ([shiftHold], null for no damping): the
  /// weight trend lags a change in what is eaten by about 9 days and the
  /// first days' water goes with it, so a window that holds one misreads
  /// the expenditure by up to about half the change, either way (D64).
  final double shiftDeadband;
  final double? shiftHold;

  final BreakAnchor breakAnchor;

  const ExpenditureSettings({
    this.alpha = 0.1,
    this.window = 20,
    this.calibrationBlend = 0.2,
    this.blend = 0.05,
    this.calibrationDays = 30,
    this.warmupDays = defaultWarmupDays,
    this.minLoggedShare = defaultMinLoggedShare,
    this.shiftDeadband = defaultShiftDeadband,
    this.shiftHold = defaultShiftHold,
    this.kcalPerKg,
    this.breakAnchor = BreakAnchor.afterHoldSoft,
  });

  static const defaultShiftDeadband = 0.05;
  static const defaultShiftHold = 0.15;

  /// The share of an update's weight kept when the intake's trend moved
  /// [shiftKcal] across a window of [meanIntakeKcal]: all of it up to
  /// [shiftDeadband], none from [shiftHold], linear between.
  double shiftDamping(double shiftKcal, double meanIntakeKcal) {
    final hold = shiftHold;
    if (hold == null || meanIntakeKcal <= 0) return 1;
    final share = shiftKcal.abs() / meanIntakeKcal;
    return 1 - ((share - shiftDeadband) / (hold - shiftDeadband)).clamp(0, 1);
  }

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
    double? shiftHold = defaultShiftHold,
    BreakAnchor breakAnchor = BreakAnchor.afterHoldSoft,
  }) => ExpenditureSettings(
    window: cycleWindow ? 28 : 20,
    shiftHold: shiftHold,
    breakAnchor: breakAnchor,
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

/// Unlogged days in a row, after logging began, that make a break (D27).
const breakDays = 5;

/// Expenditure estimated each day by energy balance (D13): mean logged
/// intake over the window less the energy of the trend's change, blended
/// into the running estimate, which starts at [priorKcal]. A day whose
/// past week has under 4 logged days or no weigh-in carries the last
/// estimate (MacroFactor's data rules). [bodyFatPercent] null uses the
/// flat 6,000 kcal/kg.
///
/// An update is taken at less than its weight, or not at all, while the
/// window holds a change in what is eaten
/// ([ExpenditureSettings.shiftDamping], D64).
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
/// [ExpenditureSettings.calibrationUpdates] it is still calibrating), the
/// first that did, null for none, and [BreakHold] when the last day is
/// held after a break.
({List<double> estimates, int updates, int? firstUpdate, BreakHold? breakHold})
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

  final intakeTrend = _intakeTrend(days, logged, settings.alpha);

  var estimate = priorKcal;
  // Calibration counts updates, not days: weigh-ins before logging began
  // would otherwise use it up before the first update.
  var updates = 0;
  int? firstUpdate;
  final firstActive = days.indexWhere((d) => d.activityKcal != null);
  // The window reaches back no further than logging does: before it, the
  // weight moved on food that was never logged.
  final firstLogged = days.indexWhere(logged);
  // After a break (D27) the weight came back moved on food nobody logged,
  // and its first days back swing with water. Each break's last day starts
  // a trend of its own at the first weigh-in a week after the first one
  // back ([back]): its anchor (D68). The estimate holds to the anchor, and
  // its updates ramp in from there. The intake's trend restarts at the
  // anchor too, so the damping reads only the shift since. Under
  // [BreakAnchor.firstBack] the anchor is [back], held a week from it.
  final restarts =
      <
        int,
        ({List<double?> trend, int? anchor, int? back, List<double?> intake})
      >{};
  var unlogged = 0;
  for (var i = firstLogged + 1; firstLogged >= 0 && i < days.length; i++) {
    if (!logged(days[i])) {
      unlogged++;
      continue;
    }
    if (unlogged >= breakDays) {
      final from = i - 1;
      final segment = smoothedTrend(
        dailyWeights({
          for (var j = from; j < days.length; j++)
            if (days[j].weightKg != null) j - from: days[j].weightKg!,
        }, days.length - from),
        alpha: settings.alpha,
      );
      final first = segment.indexWhere((t) => t != null);
      final back = first < 0 ? null : from + first;
      var trend = [...List<double?>.filled(from, null), ...segment];
      var anchor = back;
      if (back != null && settings.breakAnchor != BreakAnchor.firstBack) {
        final later = days.indexWhere(
          (d) => d.weightKg != null,
          back + settings.warmupDays,
        );
        anchor = later < 0 ? null : later;
        trend = later < 0
            ? List.filled(days.length, null)
            : [
                ...List<double?>.filled(later, null),
                ...smoothedTrend(
                  dailyWeights({
                    for (var j = later; j < days.length; j++)
                      if (days[j].weightKg != null)
                        j - later: days[j].weightKg!,
                  }, days.length - later),
                  alpha: settings.alpha,
                ),
              ];
      }
      restarts[from] = (
        trend: trend,
        anchor: anchor,
        back: back,
        intake: anchor == null
            ? intakeTrend
            : _intakeTrend(days, logged, settings.alpha, from: anchor),
      );
    }
    unlogged = 0;
  }
  BreakHold? hold;
  final out = <double>[];
  for (var day = 0; day < days.length; day++) {
    if (day == firstActive) {
      estimate -=
          meanActivity(days.sublist(day, min(day + 14, days.length))) ?? 0;
    }
    final restart = restarts.keys.where((r) => r < day).lastOrNull;
    final segment = restarts[restart];
    final week = days.sublist((day - 6).clamp(0, day), day + 1);
    var enoughData =
        firstLogged >= 0 &&
        day - firstLogged + 1 >= settings.warmupDays &&
        week.where(logged).length >= 4 &&
        week.any((d) => d.weightKg != null);
    var start = max(day - settings.window, firstLogged - 1).clamp(0, day);
    var dayTrend = trend;
    var dayIntake = intakeTrend;
    var ramp = 1.0;
    if (restart != null && segment != null) {
      final (anchor, back) = (segment.anchor, segment.back);
      final w = settings.warmupDays;
      // The first update is the day after the anchor, the anchor's own
      // window being empty. A week on with no weigh-in the week's own data
      // rule says what is missing.
      // shortcut: with no anchor yet, resumesIn assumes a weigh-in on
      // back + w (or tomorrow); say "at the soonest" if users read it late.
      final (held, resumesIn) = switch (settings.breakAnchor) {
        BreakAnchor.firstBack => (
          anchor == null || day - anchor < w,
          anchor == null ? null : anchor + w - day,
        ),
        BreakAnchor.afterHoldSoft => (
          anchor != null
              ? day <= anchor
              : back == null || day < back + w + 7,
          anchor != null
              ? anchor + 1 - day
              : back == null
              ? null
              : max(back + w, day + 1) + 1 - day,
        ),
      };
      if (held && day == days.length - 1) {
        hold = BreakHold(daysBack: day - restart, resumesIn: resumesIn);
      }
      enoughData = enoughData && !held;
      start = max(day - settings.window, anchor ?? day).clamp(0, day);
      dayTrend = segment.trend;
      dayIntake = segment.intake;
      // A window short of full moves the estimate by as much of an update
      // as it covers, so its noise is a full window's.
      if (settings.breakAnchor == BreakAnchor.afterHoldSoft && anchor != null) {
        ramp = ((day - anchor) / settings.window).clamp(0.0, 1.0);
      }
    }
    final from = dayTrend[start], to = dayTrend[day];
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
      final calibrating = updates < settings.calibrationUpdates;
      // Not while calibrating: leaving the formula's prior fast is worth
      // more than the misreading costs (the closed-loop runs, D64). The
      // window's first day may fall before logging began.
      final damping = calibrating
          ? 1.0
          : settings.shiftDamping(
              dayIntake[day]! - (dayIntake[start] ?? dayIntake.nonNulls.first),
              meanIntake,
            );
      if (damping > 0) {
        final weight = calibrating ? settings.calibrationBlend : settings.blend;
        estimate += ramp * damping * weight * (raw - estimate);
        firstUpdate ??= day;
        updates++;
      }
    }
    out.add(estimate);
  }
  return (
    estimates: out,
    updates: updates,
    firstUpdate: firstUpdate,
    breakHold: hold,
  );
}

/// The trend of the logged intake, smoothed as the weight's is so the two
/// lag alike; it starts at the mean of the first week's logged days (one
/// day is too noisy a start), carries over unlogged days and is null
/// before logging began, or before [from].
List<double?> _intakeTrend(
  List<AdaptiveDay> days,
  bool Function(AdaptiveDay) logged,
  double alpha, {
  int from = 0,
}) {
  final first = days.indexWhere(logged, from);
  if (first < 0) return List.filled(days.length, null);
  final week = [
    for (final d in days.skip(first).take(7))
      if (logged(d)) d.intakeKcal!,
  ];
  double? trend;
  return [
    for (final (i, d) in days.indexed)
      trend = i < first
          ? null
          : trend == null
          ? week.reduce((a, b) => a + b) / week.length
          : logged(d)
          ? trend + alpha * (d.intakeKcal! - trend)
          : trend,
  ];
}

/// The estimate held after a break in logging (D27, D68): to the first
/// weigh-in a week after the first one back.
class BreakHold {
  /// Days since the break's last unlogged day: 1 on the first day back.
  final int daysBack;

  /// Days until the estimate moves again; null until a weigh-in back.
  final int? resumesIn;

  const BreakHold({required this.daysBack, this.resumesIn});
}

/// Mean counted activity of the [days] that have it; null when none do.
double? meanActivity(Iterable<AdaptiveDay> days) {
  final known = [
    for (final d in days)
      if (d.activityKcal != null) d.activityKcal!,
  ];
  return known.isEmpty ? null : known.reduce((a, b) => a + b) / known.length;
}
