// ignore_for_file: avoid_print
// Closed-loop check of the adaptive target (D64, D65): a simulated user
// EATS the target each weekly check-in proposes, so the estimate feeds
// back into the intake and the weight it is estimated from. A replay of a
// logged journey can not show that: its weight is already decided. The
// truth here is on purpose not the estimator's own model: the first days'
// water follows the intake, tissue can count a flat 7,700 kcal/kg, days
// are logged in part.
//
// Runs under flutter test, as the check-in imports Flutter:
//   flutter test fork/tools/closed_loop.dart
// Results go in fork/research/phase3-simulation.md, "Closed loop".
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_store.dart';
import 'package:opennutritracker/fork/adaptive/check_in.dart';
import 'package:opennutritracker/fork/adaptive/energy.dart';
import 'package:opennutritracker/fork/adaptive/expenditure.dart';
import 'package:opennutritracker/fork/adaptive/partial_days.dart';

/// As the app's check-in reads (adaptive_service.dart).
const _historyDays = 120;

class World {
  double startKg, bodyFat, baseKcal, goalKgPerWeek;

  /// The formula prior's relative error.
  double priorError;

  /// Null: tissue follows Forbes, the estimator's own model. Else flat.
  double? truthKcalPerKg;

  /// kg of glycogen and gut water per 1,000 kcal/day of intake, 3-day lag.
  double waterPer1000;
  double loggingShare, unlogged, partial, missedWeighIn, noiseKg, cycleKg;

  /// SD of what is eaten around the target.
  double adherenceSd;

  /// A step in true expenditure.
  int? stepDay;
  double stepKcal;

  /// The pace changed on a day.
  int? goalChangeDay;
  double goalAfter;

  /// The user answers D65's question, leaving out every day pointed out.
  bool leavesOutFlagged;

  /// Days the water takes to follow the intake (its time constant).
  double waterLag;

  /// A break in logging and weighing from [breakDay] for [breakLength]
  /// days, eating [breakEat] more (a share) than the target.
  int? breakDay;
  int breakLength;
  double breakEat;

  World({
    this.startKg = 90,
    this.bodyFat = 30,
    this.baseKcal = 2700,
    this.goalKgPerWeek = -0.5,
    this.priorError = 0.1,
    this.truthKcalPerKg,
    this.waterPer1000 = 1,
    this.loggingShare = 0.9,
    this.unlogged = 0.1,
    this.partial = 0.05,
    this.missedWeighIn = 0.3,
    this.noiseKg = 0.5,
    this.cycleKg = 0,
    this.adherenceSd = 0.08,
    this.stepDay,
    this.stepKcal = 0,
    this.goalChangeDay,
    this.goalAfter = 0,
    this.leavesOutFlagged = false,
    this.waterLag = 3,
    this.breakDay,
    this.breakLength = 0,
    this.breakEat = 0,
  });

  bool away(int day) =>
      breakDay != null && day >= breakDay! && day < breakDay! + breakLength;
}

class Knobs {
  final Responsiveness resp;
  final bool cycle, flat, damping;
  final double? cap;
  final BreakAnchor anchor;
  const Knobs({
    this.anchor = BreakAnchor.afterHoldSoft,
    this.resp = Responsiveness.standard,
    this.cycle = false,
    this.flat = false,
    this.damping = true,
    this.cap = 200,
  });

  ExpenditureSettings get settings => ExpenditureSettings.of(
    resp,
    cycleWindow: cycle,
    kcalPerKg: flat ? 7700 : null,
    shiftHold: damping ? ExpenditureSettings.defaultShiftHold : null,
    breakAnchor: anchor,
  );

  String get label =>
      '${resp.name}${cycle ? ' +cycle' : ''}${flat ? ' +7700' : ''}'
      '${damping ? '' : ' undamped'}'
      '${anchor == BreakAnchor.afterHoldSoft ? '' : ' ${anchor.name}'}';
}

class Result {
  /// Estimate less truth (logged calories) at each weekly check-in, and
  /// the targets set.
  final errors = <double>[], targets = <double>[];

  /// True tissue kg a week from day 42 on.
  double pace = 0;

  /// True tissue each day, and runs of 5 or more unlogged days.
  var tissueAt = <double>[];
  var breaks = 0;
}

Result run(World w, Knobs k, {int days = 280, int seed = 1}) {
  final rnd = Random(seed);
  double g() {
    final u = 1 - rnd.nextDouble(), v = rnd.nextDouble();
    return sqrt(-2 * log(u)) * cos(2 * pi * v);
  }

  var tissue = w.startKg, fat = fatMassKg(w.startKg, w.bodyFat), water = 0.0;
  final shifts = {for (var i = 0; i < 3; i++) 20 + rnd.nextInt(days - 40): g()};
  final observed = <AdaptiveDay>[];
  final tissueAt = <double>[];
  final r = Result();
  var goal = w.goalKgPerWeek, target = 0.0, deficit = 0.0;
  double? previousBase;
  final prior = w.baseKcal * (1 + w.priorError) * (1 + 4 * goal / w.startKg);

  for (var day = 0; day < days; day++) {
    if (w.goalChangeDay == day) goal = w.goalAfter;
    final tdee =
        w.baseKcal -
        22 * (w.startKg - tissue) -
        0.05 * max(0.0, deficit) +
        (w.stepDay != null && day >= w.stepDay! ? w.stepKcal : 0);

    if (day % 7 == 0) {
      if (w.leavesOutFlagged) {
        final from = max(0, observed.length - _historyDays);
        for (final f in likelyPartlyLogged(observed.sublist(from))) {
          final i = from + f.day;
          observed[i] = AdaptiveDay(weightKg: observed[i].weightKg);
        }
      }
      final history = observed.length > _historyDays
          ? observed.sublist(observed.length - _historyDays)
          : observed;
      final first = history.indexWhere((d) => d.weightKg != null);
      final checkIn = computeCheckIn(
        CheckInInputs(
          days: first < 0 ? const [AdaptiveDay()] : history.sublist(first),
          priorKcal: prior,
          goalRateKgPerWeek: goal,
          bodyFatPercent: w.bodyFat,
          previousBaseKcal: previousBase,
          taper: (adjustment, _) => adjustment,
          fallbackWeightKg: w.startKg,
          settings: k.settings,
          maxChangeKcal: k.cap,
          activityMode: ActivityMode.off,
        ),
      );
      target = checkIn.proposedTargetKcal;
      previousBase = checkIn.baseKcal;
      r.targets.add(target);
      r.errors.add(checkIn.expenditureKcal - tdee * w.loggingShare);
    }

    final eaten =
        target /
        w.loggingShare *
        (1 + (w.away(day) ? w.breakEat : 0)) *
        (1 + w.adherenceSd * g());
    deficit += 0.1 * ((tdee - eaten) - deficit);
    final change = (eaten - tdee) / (w.truthKcalPerKg ?? energyDensity(fat));
    fat += fatShare(fat) * change;
    tissue += change;
    tissueAt.add(tissue);
    water +=
        (w.waterPer1000 * (eaten - w.baseKcal) / 1000 - water) / w.waterLag;
    final scale =
        tissue +
        water +
        0.0035 * tissue * sin(2 * pi * day / 7) +
        w.cycleKg * sin(2 * pi * day / 28) +
        [
          for (final MapEntry(key: at, value: size) in shifts.entries)
            if (day >= at && day < at + 4) 0.8 * size,
        ].fold(0.0, (a, b) => a + b) +
        w.noiseKg * g();
    final roll = rnd.nextDouble();
    final weighed = rnd.nextDouble() >= w.missedWeighIn && !w.away(day);
    observed.add(
      AdaptiveDay(
        intakeKcal: w.away(day) || roll < w.unlogged
            ? null
            : eaten *
                  w.loggingShare *
                  (roll < w.unlogged + w.partial ? 0.5 : 1),
        weightKg: weighed ? double.parse(scale.toStringAsFixed(1)) : null,
      ),
    );
  }
  r.pace = (tissueAt.last - tissueAt[42]) / (days - 43) * 7;
  r.tissueAt = tissueAt;
  var run = 0;
  for (final d in observed) {
    run = (d.intakeKcal ?? 0) < minLoggedKcal ? run + 1 : 0;
    if (run == breakDays) r.breaks++;
  }
  return r;
}

/// The mean over [seeds] of each check-in's error, or of its absolute.
List<double> trace(
  World Function() world,
  Knobs k, {
  int seeds = 30,
  int days = 280,
  bool absolute = false,
}) {
  final sum = List.filled((days / 7).ceil(), 0.0);
  for (var seed = 1; seed <= seeds; seed++) {
    final errors = run(world(), k, seed: seed, days: days).errors;
    for (final (i, e) in errors.indexed) {
      sum[i] += (absolute ? e.abs() : e) / seeds;
    }
  }
  return sum;
}

/// Mean bias and absolute error from day 42, the mean weekly move of the
/// target and the share of moves that turn back, and the pace.
({double bias, double error, double move, double turns, double pace}) summary(
  World Function() world,
  Knobs k, {
  int seeds = 12,
}) {
  var bias = 0.0, error = 0.0, move = 0.0, turns = 0.0, pace = 0.0;
  for (var seed = 1; seed <= seeds; seed++) {
    final r = run(world(), k, seed: seed);
    final n = r.errors.length - 6;
    var back = 0;
    for (var i = 6; i < r.errors.length; i++) {
      bias += r.errors[i] / n / seeds;
      error += r.errors[i].abs() / n / seeds;
      final now = r.targets[i] - r.targets[i - 1];
      final before = r.targets[i - 1] - r.targets[i - 2];
      move += now.abs() / n / seeds;
      if (now * before < 0 && now.abs() > 15 && before.abs() > 15) back++;
    }
    turns += back / n / seeds;
    pace += r.pace / seeds;
  }
  return (bias: bias, error: error, move: move, turns: turns, pace: pace);
}

/// Over the check-ins from the one after the return to 8 weeks on: mean
/// bias and |error|, the largest weekly target move, and the true pace.
void _breakRow(
  String label,
  World Function() world,
  Knobs k, {
  int seeds = 30,
}) {
  var bias = 0.0, error = 0.0, move = 0.0, pace = 0.0;
  for (var seed = 1; seed <= seeds; seed++) {
    final w = world();
    final r = run(w, k, seed: seed);
    final back = w.breakDay! + w.breakLength;
    final from = (back / 7).ceil(), to = from + 8;
    var biggest = 0.0;
    for (var i = from; i <= to; i++) {
      bias += r.errors[i] / 9 / seeds;
      error += r.errors[i].abs() / 9 / seeds;
      biggest = max(biggest, (r.targets[i] - r.targets[i - 1]).abs());
    }
    move += biggest / seeds;
    pace += (r.tissueAt[to * 7] - r.tissueAt[from * 7]) / 8 / seeds;
  }
  print(
    '${label.padRight(44)} | ${bias.round().toString().padLeft(5)} '
    '| ${error.round().toString().padLeft(4)} '
    '| ${move.round().toString().padLeft(4)} '
    '| ${pace.toStringAsFixed(2)}',
  );
}

String _weeks(List<double> v, [int from = 0, int? to]) =>
    v.sublist(from, to).map((e) => e.round().toString().padLeft(5)).join();

void _row(String label, World Function() world, Knobs k) {
  final s = summary(world, k);
  print(
    '${label.padRight(40)} | ${s.bias.round().toString().padLeft(5)} '
    '| ${s.error.round().toString().padLeft(4)} '
    '| ${s.move.round().toString().padLeft(3)} '
    '| ${(s.turns * 100).round().toString().padLeft(3)}% '
    '| ${s.pace.toStringAsFixed(2)}',
  );
}

void main() {
  test('closed loop', () {
    const standard = Knobs(), undamped = Knobs(damping: false);

    print('\n## Settings (bias | error | weekly move | turns back | pace)');
    for (final resp in Responsiveness.values) {
      for (final flat in [false, true]) {
        final k = Knobs(resp: resp, flat: flat);
        _row(k.label, World.new, k);
      }
    }
    _row(undamped.label, World.new, undamped);
    _row(
      'truth 7,700 kcal/kg, standard',
      () => World(truthKcalPerKg: 7700),
      standard,
    );
    _row(
      'truth 7,700 kcal/kg, standard +7700',
      () => World(truthKcalPerKg: 7700),
      const Knobs(flat: true),
    );
    for (final k in [
      standard,
      const Knobs(resp: Responsiveness.responsive),
      const Knobs(cycle: true),
    ]) {
      _row(
        '1 kg cycle, ${k.label}',
        () =>
            World(cycleKg: 1, startKg: 68, baseKcal: 2100, goalKgPerWeek: -0.3),
        k,
      );
    }

    print('\n## Cold start, mean |estimate - truth| by week (weeks 0-15)');
    for (final water in [0.0, 1.0, 2.0]) {
      for (final prior in [0.2, -0.2]) {
        for (final k in [undamped, standard]) {
          print(
            'water $water prior ${(prior * 100).round().toString().padLeft(3)}% '
            '${k.damping ? 'damped  ' : 'undamped'}: '
            '${_weeks(trace(() => World(waterPer1000: water, priorError: prior), k, days: 112, absolute: true))}',
          );
        }
      }
    }

    print(
      '\n## Pace 0 to -0.75 kg/week at day 140, estimate - truth, weeks 18-32',
    );
    for (final water in [0.0, 1.0, 2.0]) {
      for (final k in [
        undamped,
        standard,
        const Knobs(resp: Responsiveness.responsive, damping: false),
        const Knobs(resp: Responsiveness.responsive),
      ]) {
        print(
          'water $water ${k.label.padRight(20)}: '
          '${_weeks(trace(() => World(goalKgPerWeek: 0, goalChangeDay: 140, goalAfter: -0.75, waterPer1000: water, priorError: 0), k), 18, 33)}',
        );
      }
    }

    print(
      '\n## Expenditure steps 300 kcal at day 140 (maintenance, no noise), weeks 19-34',
    );
    World clean(double step) => World(
      goalKgPerWeek: 0,
      priorError: 0,
      unlogged: 0,
      partial: 0,
      missedWeighIn: 0,
      noiseKg: 0,
      adherenceSd: 0,
      loggingShare: 1,
      stepDay: 140,
      stepKcal: step,
    );
    for (final step in [-300.0, 300.0]) {
      for (final resp in Responsiveness.values) {
        for (final damping in [false, true]) {
          final k = Knobs(resp: resp, damping: damping);
          print(
            'step ${step.round().toString().padLeft(4)} ${k.label.padRight(20)}: '
            '${_weeks(trace(() => clean(step), k, seeds: 1), 19, 35)}',
          );
        }
      }
    }

    print(
      '\n## Days logged at half, maintenance (bias | error | move | turns | pace)',
    );
    World maintaining(double partial, bool leavesOut, [double sd = 0.08]) =>
        World(
          goalKgPerWeek: 0,
          startKg: 80,
          bodyFat: 22,
          baseKcal: 2600,
          priorError: 0,
          partial: partial,
          adherenceSd: sd,
          leavesOutFlagged: leavesOut,
        );
    for (final partial in [0.0, 0.05, 0.1, 0.2]) {
      for (final leavesOut in [false, true]) {
        _row(
          '${(partial * 100).round()}% at half${leavesOut ? ', flagged days left out' : ''}',
          () => maintaining(partial, leavesOut),
          standard,
        );
      }
    }
    print(
      '   ...no half days, intake varying 25% a day: what leaving out costs',
    );
    for (final leavesOut in [false, true]) {
      _row(
        'SD 25%${leavesOut ? ', flagged days left out' : ''}',
        () => maintaining(0, leavesOut, 0.25),
        standard,
      );
    }

    final anchors = [for (final a in BreakAnchor.values) Knobs(anchor: a)];
    print('\n## Break anchors, no break (bias | error | move | turns | pace)');
    for (final (label, world) in <(String, World Function())>[
      ('default', World.new),
      ('truth 7,700', () => World(truthKcalPerKg: 7700)),
      ('water 2', () => World(waterPer1000: 2)),
      ('20% at half, flagged left out', () => maintaining(0.2, true)),
      ('SD 25%, flagged left out', () => maintaining(0, true, 0.25)),
    ]) {
      for (final k in anchors) {
        _row('$label, ${k.anchor.name}', world, k);
      }
    }
    print('   ...runs of 5+ unlogged days a run (12 seeds, mean)');
    for (final (label, world) in <(String, World Function())>[
      ('default', World.new),
      ('20% at half, flagged left out', () => maintaining(0.2, true)),
      ('SD 25%, flagged left out', () => maintaining(0, true, 0.25)),
    ]) {
      var n = 0;
      for (var seed = 1; seed <= 12; seed++) {
        n += run(world(), standard, seed: seed).breaks;
      }
      print('$label: ${(n / 12).toStringAsFixed(2)}');
    }

    // Break from day 147; the return's weigh-in carries the break's water.
    final breaks = <(String, World Function())>[
      (
        '14d 0% water 2.0 lag 7, maintenance',
        () => World(
          breakDay: 147,
          breakLength: 14,
          waterPer1000: 2,
          waterLag: 7,
          goalKgPerWeek: 0,
        ),
      ),
      for (final (length, eat, water, lag) in [
        (14, 0.0, 2.0, 7.0),
        (14, 0.2, 1.0, 3.0),
        (14, 0.2, 2.0, 7.0),
        (21, 0.2, 2.0, 7.0),
        (10, 0.25, 2.0, 7.0),
        (14, -0.2, 2.0, 7.0),
        (21, -0.2, 2.0, 7.0),
      ])
        (
          '${length}d ${eat > 0 ? '+' : ''}${(eat * 100).round()}% water $water lag ${lag.round()}',
          () => World(
            breakDay: 147,
            breakLength: length,
            breakEat: eat,
            waterPer1000: water,
            waterLag: lag,
          ),
        ),
    ];
    print(
      '\n## Breaks, check-ins from the return to 8 weeks on, 30 seeds '
      '(bias | error | max weekly move | pace)',
    );
    for (final (label, world) in breaks) {
      for (final k in anchors) {
        _breakRow('$label, ${k.anchor.name}', world, k);
      }
    }
    print('\n## Breaks, whole run (bias | error | move | turns | pace)');
    for (final (label, world) in breaks) {
      for (final k in anchors) {
        _row('$label, ${k.anchor.name}', world, k);
      }
    }
    print('\n## Breaks, estimate - truth by week, weeks 19-32');
    for (final (label, world) in breaks) {
      for (final k in anchors) {
        print(
          '${'$label, ${k.anchor.name}'.padRight(44)}: '
          '${_weeks(trace(world, k), 19, 33)}',
        );
      }
    }
  });
}
