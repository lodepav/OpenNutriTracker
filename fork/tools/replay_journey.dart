// ignore_for_file: avoid_print
// Replays a logged journey (a MacroFactor export, turned into a journey
// JSON outside the repo) through the check-in, to see how the estimate
// and the targets react: once on the intake and weights as logged, once
// with the intake moved by how far our target differs from the one the
// user followed, and the weight by that energy ("drift").
//
// Runs under flutter test, as the check-in imports Flutter:
//   JOURNEY=/path/journey.json OUT=/path/out flutter test \
//     fork/tools/replay_journey.dart
// Personal data: keep the journey and the output out of the repo.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/user_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_gender_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_pal_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_weight_goal_entity.dart';
import 'package:opennutritracker/core/utils/calc/calorie_goal_calc.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_service.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_store.dart';
import 'package:opennutritracker/fork/adaptive/check_in.dart';
import 'package:opennutritracker/fork/adaptive/energy.dart';
import 'package:opennutritracker/fork/adaptive/expenditure.dart';

/// As the app's check-in reads (adaptive_service.dart).
const _historyDays = 120;

class _Day {
  final DateTime date;
  final double? intake;
  final double? weight;
  final double? fat;
  final bool partial;
  final double? mfTrend;
  final double? mfExpenditure;

  _Day(Map<String, dynamic> j)
    : date = DateTime.parse(j['date'] as String),
      intake = (j['intake'] as num?)?.toDouble(),
      weight = (j['weight'] as num?)?.toDouble(),
      fat = (j['fat'] as num?)?.toDouble(),
      partial = j['partial'] == true,
      mfTrend = (j['mfTrend'] as num?)?.toDouble(),
      mfExpenditure = (j['mfExpenditure'] as num?)?.toDouble();
}

class _Goal {
  final String type;
  final DateTime start;
  final DateTime? end;
  final double targetKg;
  final double ratePct;

  _Goal(Map<String, dynamic> j)
    : type = j['type'] as String,
      start = DateTime.parse(j['start'] as String),
      end = j['end'] == null ? null : DateTime.parse(j['end'] as String),
      targetKg = (j['targetKg'] as num).toDouble(),
      ratePct = (j['ratePct'] as num).toDouble();

  UserWeightGoalEntity get goal => switch (type) {
    'Weight Loss' => UserWeightGoalEntity.loseWeight,
    'Weight Gain' => UserWeightGoalEntity.gainWeight,
    _ => UserWeightGoalEntity.maintainWeight,
  };

  /// MacroFactor's rate is a share of body weight a week; maintenance's
  /// is a band, not a pace.
  double kgPerWeek(double weightKg) => switch (goal) {
    UserWeightGoalEntity.loseWeight => -ratePct / 100 * weightKg,
    UserWeightGoalEntity.gainWeight => ratePct / 100 * weightKg,
    UserWeightGoalEntity.maintainWeight => 0,
  };
}

typedef _Program = ({DateTime date, double dailyAverage, double expenditure});

/// One way of replaying.
class _Run {
  final String name;
  final Responsiveness responsiveness;
  final bool skipPartial;
  final bool measuredFat;
  final bool drift;
  final double? cap;

  /// kcal logged on the check-in morning, before it is done; null for
  /// none.
  final double? morningKcal;

  /// Check in each Monday and on a goal change, as the app does with
  /// Monday picked, instead of on the days MacroFactor updated its
  /// program.
  final bool weekly;
  final double minLoggedShare;

  const _Run(
    this.name, {
    this.responsiveness = Responsiveness.standard,
    this.skipPartial = true,
    this.measuredFat = true,
    this.drift = false,
    this.cap = AdaptiveSettings.defaultMaxCheckInChangeKcal,
    this.morningKcal,
    this.weekly = false,
    this.minLoggedShare = ExpenditureSettings.defaultMinLoggedShare,
  });
}

class _Row {
  final DateTime date;
  final String goal;
  final DateTime goalStart;
  final double pace;
  final CheckIn checkIn;
  final double previous;
  final double mfTarget;
  final double mfExpenditure;
  final double? mfTrend;
  final double? weightShift;

  _Row(
    this.date,
    this.goal,
    this.goalStart,
    this.pace,
    this.checkIn,
    this.previous,
    this.mfTarget,
    this.mfExpenditure,
    this.mfTrend,
    this.weightShift,
  );
}

DateTime _d(DateTime t) => DateTime(t.year, t.month, t.day);

List<_Row> _replay(
  _Run run,
  List<_Day> days,
  List<_Goal> goals,
  List<_Program> program,
  Map<String, dynamic> profile,
) {
  final byDate = {for (final d in days) _d(d.date): d};
  final first = days.first.date;
  final last = days.last.date;
  _Program? mfOn(DateTime day) =>
      program.lastWhere((p) => !p.date.isAfter(day), orElse: () => program[0]);
  _Goal goalOn(DateTime day) =>
      goals.lastWhere((g) => !g.start.isAfter(day), orElse: () => goals.first);

  // Drift: the intake and weight the user would have had following our
  // targets, built day by day as the targets are set.
  final intake = <DateTime, double?>{};
  final weight = <DateTime, double?>{};
  var shiftKcal = 0.0;
  double? ourTarget;
  double? ourBase;
  final firstIntake = days.firstWhere((d) => d.intake != null).date;
  final goalDays = {for (final g in goals) g.start};

  final rows = <_Row>[];
  final checkInDays = {for (final p in program) p.date};
  for (
    var day = first;
    !day.isAfter(last);
    day = DateTime(day.year, day.month, day.day + 1)
  ) {
    final d = byDate[day];
    final fatNow = _recentFat(days, day);
    final mf = mfOn(day)!;
    var logged = d?.intake;
    if (run.skipPartial && (d?.partial ?? false)) logged = null;
    if (run.drift && ourTarget != null && d?.intake != null) {
      final extra = ourTarget - mf.dailyAverage;
      intake[day] = d!.intake! + extra;
      shiftKcal += extra;
    } else {
      intake[day] = d?.intake;
    }
    if (logged == null) intake[day] = null;
    final density = energyDensity(
      fatMassKg(d?.weight ?? d?.mfTrend ?? 90, fatNow ?? 15),
    );
    weight[day] = d?.weight == null ? null : d!.weight! + shiftKcal / density;

    final due = run.weekly
        ? day.weekday == DateTime.monday ||
              goalDays.contains(day) ||
              ourTarget == null && !day.isBefore(firstIntake)
        : checkInDays.contains(day);
    if (!due) continue;
    final goal = goalOn(day);
    final latestWeight = [
      for (var back = 0; back < 30; back++)
        weight[DateTime(day.year, day.month, day.day - back)],
    ].firstWhere((w) => w != null, orElse: () => 90)!;
    final user = UserEntity(
      birthday: DateTime.parse(profile['birthday'] as String),
      heightCM: (profile['heightCm'] as num).toDouble(),
      weightKG: latestWeight,
      gender: profile['sex'] == 'Female'
          ? UserGenderEntity.female
          : UserGenderEntity.male,
      goal: goal.goal,
      pal: UserPALEntity.active,
      weeklyWeightGoalKg: goal.kgPerWeek(latestWeight),
      targetWeightKg: goal.targetKg,
    );
    final start = DateTime(day.year, day.month, day.day - (_historyDays - 1));
    final firstWeighIn =
        [
          for (
            var t = start;
            !t.isAfter(day);
            t = DateTime(t.year, t.month, t.day + 1)
          )
            if (weight[t] != null) t,
        ].firstOrNull ??
        day;
    final history = [
      for (
        var t = firstWeighIn;
        !t.isAfter(day);
        t = DateTime(t.year, t.month, t.day + 1)
      )
        AdaptiveDay(
          // The check-in is done in the morning: the day's food is not in
          // yet, or only breakfast.
          intakeKcal: t == day ? run.morningKcal : intake[t],
          weightKg: weight[t],
        ),
    ];
    final rate = goalRateKgPerWeek(user);
    final previous = ourTarget ?? CalorieGoalCalc.getTotalKcalGoal(user, 0);
    final checkIn = computeCheckIn(
      CheckInInputs(
        days: history,
        priorKcal:
            CalorieGoalCalc.getTdee(user) * (1 + 4 * rate / user.weightKG),
        goalRateKgPerWeek: rate,
        bodyFatPercent: run.measuredFat && fatNow != null
            ? fatNow
            : bodyFatPercent(user),
        targetWeightKg: user.targetWeightKg,
        previousBaseKcal: ourBase,
        maxChangeKcal: run.cap,
        taper: (adjustment, w) => CalorieGoalCalc.applyTargetWeightTaper(
          baseAdjustment: adjustment,
          currentWeightKg: w,
          targetWeightKg: user.targetWeightKg,
          goal: user.goal,
          taperEnabled: user.caloriesTaperEnabled,
        ),
        settings: ExpenditureSettings.of(
          run.responsiveness,
          minLoggedShare: run.minLoggedShare,
        ),
      ),
    );
    ourTarget = checkIn.proposedTargetKcal;
    ourBase = checkIn.baseKcal;
    rows.add(
      _Row(
        day,
        goal.type,
        goal.start,
        rate,
        checkIn,
        previous,
        mf.dailyAverage,
        mf.expenditure,
        d?.mfTrend,
        run.drift ? shiftKcal / density : null,
      ),
    );
  }
  return rows;
}

/// Days from each goal's start until the target is within 50 kcal of
/// where the new goal puts it, over the goal changes the replay sees.
List<int> _lags(List<_Row> rows) {
  final out = <int>[];
  for (var i = 1; i < rows.length; i++) {
    if (rows[i].goalStart == rows[i - 1].goalStart) continue;
    final from = rows[i].goalStart;
    for (
      var k = i;
      k < rows.length && rows[k].goalStart == rows[i].goalStart;
      k++
    ) {
      final c = rows[k].checkIn;
      if ((c.proposedTargetKcal - c.uncappedTargetKcal).abs() < 50) {
        out.add(rows[k].date.difference(from).inDays);
        break;
      }
    }
  }
  return out;
}

/// The scale's body fat % within the past 90 days, as the app reads a
/// measured one.
double? _recentFat(List<_Day> days, DateTime day) {
  final from = DateTime(day.year, day.month, day.day - 89);
  return days
      .lastWhere(
        (d) => d.fat != null && !d.date.isBefore(from) && !d.date.isAfter(day),
        orElse: () => _Day({'date': '1900-01-01'}),
      )
      .fat;
}

String _f(double? v, [int digits = 0]) =>
    v == null ? '' : v.toStringAsFixed(digits);

void _write(String out, _Run run, List<_Row> rows) {
  final csv = StringBuffer(
    'date,goal,pace_kg_wk,our_expenditure,mf_expenditure,uncapped,'
    'proposed,previous,change,mf_target,our_trend,mf_trend,logged_days,'
    'weigh_ins,weight_shift_kg\n',
  );
  for (final r in rows) {
    final c = r.checkIn;
    csv.writeln(
      [
        r.date.toIso8601String().substring(0, 10),
        r.goal,
        _f(r.pace, 2),
        _f(c.expenditureKcal),
        _f(r.mfExpenditure),
        _f(c.uncappedTargetKcal),
        _f(c.proposedTargetKcal),
        _f(r.previous),
        _f(c.proposedTargetKcal - r.previous),
        _f(r.mfTarget),
        _f(c.trendKg, 2),
        _f(r.mfTrend, 2),
        c.loggedDays,
        c.weighIns,
        _f(r.weightShift, 2),
      ].join(','),
    );
  }
  File('$out/${run.name}.csv').writeAsStringSync(csv.toString());

  double mean(Iterable<double> v) => v.reduce((a, b) => a + b) / v.length;
  double rms(Iterable<double> v) => sqrt(mean(v.map((x) => x * x)));
  final settled = rows.skip(4).toList();
  final expGap = [
    for (final r in settled) r.checkIn.expenditureKcal - r.mfExpenditure,
  ];
  final targetGap = [
    for (final r in settled) r.checkIn.proposedTargetKcal - r.mfTarget,
  ];
  final weekMoves = [
    for (var i = 1; i < settled.length; i++)
      settled[i].checkIn.expenditureKcal -
          settled[i - 1].checkIn.expenditureKcal,
  ];
  final capped = rows
      .where(
        (r) =>
            (r.checkIn.uncappedTargetKcal - r.checkIn.proposedTargetKcal)
                .abs() >
            1,
      )
      .length;
  print(
    '${run.name.padRight(22)} '
    'exp-MF mean ${_f(mean(expGap)).padLeft(5)} rms ${_f(rms(expGap)).padLeft(4)} | '
    'target-MF mean ${_f(mean(targetGap)).padLeft(5)} rms ${_f(rms(targetGap)).padLeft(4)} | '
    'weekly exp move rms ${_f(rms(weekMoves)).padLeft(3)} max ${_f(weekMoves.map((m) => m.abs()).reduce(max)).padLeft(3)} | '
    'capped $capped/${rows.length} | '
    'goal-change lag ${_lags(rows).join(' ')}'
    '${run.drift ? ' | weight shift end ${_f(rows.last.weightShift, 1)} kg' : ''}',
  );
}

void main() {
  test('replay', () {
    final path = Platform.environment['JOURNEY']!;
    final out = Platform.environment['OUT']!;
    Directory(out).createSync(recursive: true);
    final json =
        jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
    final days = [
      for (final d in json['days'] as List) _Day(d as Map<String, dynamic>),
    ];
    final goals = [
      for (final g in json['goals'] as List) _Goal(g as Map<String, dynamic>),
    ];
    final program = <_Program>[
      for (final p in json['program'] as List)
        (
          date: DateTime.parse((p as Map)['date'] as String),
          dailyAverage: (p['dailyAverage'] as num).toDouble(),
          expenditure: (p['expenditure'] as num).toDouble(),
        ),
    ];
    final profile = json['profile'] as Map<String, dynamic>;
    for (final run in const [
      _Run('standard'),
      _Run('steady', responsiveness: Responsiveness.steady),
      _Run('responsive', responsiveness: Responsiveness.responsive),
      _Run('no-skip', skipPartial: false),
      _Run('deurenberg', measuredFat: false),
      _Run('no-cap', cap: null),
      _Run('no-coverage', minLoggedShare: 0),
      _Run('breakfast-500', morningKcal: 500),
      _Run('drift', drift: true),
      _Run('weekly', weekly: true),
      _Run(
        'weekly-responsive',
        weekly: true,
        responsiveness: Responsiveness.responsive,
      ),
      _Run('weekly-drift', weekly: true, drift: true),
    ]) {
      _write(out, run, _replay(run, days, goals, program, profile));
    }
  });
}
