import 'dart:async';

import 'package:logging/logging.dart';
import 'package:opennutritracker/core/utils/calc/calendar_day_calc.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_service.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_store.dart';
import 'package:opennutritracker/fork/adaptive/goal_plan.dart';
import 'package:opennutritracker/fork/adaptive/goal_plan_card.dart'
    show paceChanges;

/// Where a goal began: the day its target was set and the trend weight
/// then. A target set before the fork kept one starts at the first day of
/// the trend it has. The plan runs at [paceKgPerWeek] from [planDate] and
/// [planKg]: the start, or the day the pace last changed.
class GoalStart {
  final DateTime date;
  final double kg;
  final double targetKg;

  /// The pace the plan runs at; null in a start kept before it was.
  final double? paceKgPerWeek;
  final DateTime? _planDate;
  final double? _planKg;

  const GoalStart({
    required this.date,
    required this.kg,
    required this.targetKg,
    this.paceKgPerWeek,
    DateTime? planDate,
    double? planKg,
  }) : _planDate = planDate,
       _planKg = planKg;

  DateTime get planDate => _planDate ?? date;
  double get planKg => _planKg ?? kg;

  /// The plan moved to [day] and [atKg] at [pace].
  GoalStart replanned(DateTime day, double atKg, double pace) => GoalStart(
    date: date,
    kg: kg,
    targetKg: targetKg,
    paceKgPerWeek: pace,
    planDate: day,
    planKg: atKg,
  );

  Map<String, dynamic> toJson() => {
    'date': date.toIso8601String(),
    'kg': kg,
    'targetKg': targetKg,
    'paceKgPerWeek': ?paceKgPerWeek,
    'planDate': ?_planDate?.toIso8601String(),
    'planKg': ?_planKg,
  };

  static GoalStart fromJson(Map<dynamic, dynamic> json) => GoalStart(
    date: DateTime.parse(json['date'] as String),
    kg: (json['kg'] as num).toDouble(),
    targetKg: (json['targetKg'] as num).toDouble(),
    paceKgPerWeek: (json['paceKgPerWeek'] as num?)?.toDouble(),
    planDate: switch (json['planDate']) {
      final String d => DateTime.parse(d),
      _ => null,
    },
    planKg: (json['planKg'] as num?)?.toDouble(),
  );
}

/// The start for [targetKg] at [paceKgPerWeek]: [stored] while it is the
/// same target and pace; with none stored, the first day of [trend]
/// (oldest first, the last [today]); a changed target starts today, and a
/// changed pace starts the plan today from the trend then. A start kept
/// before the pace was takes the pace from [paceSince], the day the
/// check-ins first show it, when that is after the start and in [trend].
GoalStart resolveGoalStart({
  required GoalStart? stored,
  required double targetKg,
  required double paceKgPerWeek,
  required List<double> trend,
  required DateTime today,
  DateTime? paceSince,
}) {
  if (stored != null && (stored.targetKg - targetKg).abs() < 0.05) {
    final pace = stored.paceKgPerWeek;
    if (pace != null && (pace - paceKgPerWeek).abs() < 0.001) return stored;
    if (pace != null) return stored.replanned(today, trend.last, paceKgPerWeek);
    final i = paceSince == null
        ? -1
        : trend.length - 1 - CalendarDayCalc.daysBetween(paceSince, today);
    return paceSince != null && paceSince.isAfter(stored.date) && i >= 0
        ? stored.replanned(paceSince, trend[i], paceKgPerWeek)
        : stored.replanned(stored.planDate, stored.planKg, paceKgPerWeek);
  }
  if (stored == null) {
    return GoalStart(
      date: DateTime(today.year, today.month, today.day - (trend.length - 1)),
      kg: trend.first,
      targetKg: targetKg,
      paceKgPerWeek: paceKgPerWeek,
    );
  }
  return GoalStart(
    date: today,
    kg: trend.last,
    targetKg: targetKg,
    paceKgPerWeek: paceKgPerWeek,
  );
}

/// The first day of the latest run of [checkIns] (oldest first) at
/// [paceKgPerWeek]; null when none records a pace, or every one is at it.
DateTime? paceSetOn(List<CheckInRecord> checkIns, double paceKgPerWeek) {
  DateTime? since;
  for (final c in checkIns.reversed) {
    final rate = c.goalRateKgPerWeek;
    if (rate == null) break;
    if ((rate - paceKgPerWeek).abs() >= 0.001) return since;
    since = c.date;
  }
  return null;
}

/// The way left from [nowKg] to [targetKg], 0 once there or past it as
/// [goal]'s kept start runs; without a start for that target, the way
/// either side is left.
double goalLeftKg(double targetKg, double nowKg, GoalProgress? goal) {
  final way = goal != null && (goal.targetKg - targetKg).abs() < 0.05
      ? goal.totalKg
      : 0;
  return (targetKg - nowKg) * way < 0 ? 0 : (targetKg - nowKg).abs();
}

/// How far a goal has come, from [start] to [nowKg], against the plan of
/// [paceKgPerWeek] from the start.
class GoalProgress {
  final GoalStart start;
  final double nowKg;

  /// The profile's pace, kg a week, signed.
  final double paceKgPerWeek;

  /// The trend, one a day, oldest first, the last [today].
  final List<double> trend;
  final DateTime today;

  const GoalProgress({
    required this.start,
    required this.nowKg,
    required this.paceKgPerWeek,
    required this.trend,
    required this.today,
  });

  double get targetKg => start.targetKg;

  /// The whole way, signed: negative to lose.
  double get totalKg => targetKg - start.kg;

  /// Still to go, signed as [totalKg]; 0 once there or past.
  double get toGoKg {
    final left = targetKg - nowKg;
    return left.sign == totalKg.sign && left.abs() >= 0.1 ? left : 0;
  }

  bool get reached => toGoKg == 0;

  /// Share of the way come, 0 to 1.
  double get fraction =>
      totalKg.abs() < 0.1 ? 1 : ((nowKg - start.kg) / totalKg).clamp(0.0, 1.0);

  int get daysIn => CalendarDayCalc.daysBetween(start.date, today);

  /// True when the plan restarted after the start, with a new pace.
  bool get replanned => start.planDate.isAfter(start.date);

  /// Where the plan has the trend [days] after its own start
  /// ([GoalStart.planDate]), not past the target.
  double planKgAfter(int days) {
    final kg = start.planKg + paceKgPerWeek / 7 * days;
    return totalKg < 0
        ? (kg < targetKg ? targetKg : kg)
        : (kg > targetKg ? targetKg : kg);
  }

  /// Where the plan has the trend today.
  double get planKgToday =>
      planKgAfter(CalendarDayCalc.daysBetween(start.planDate, today));

  /// Share of the way the plan has come by today.
  double get planFraction => totalKg.abs() < 0.1
      ? 1
      : ((planKgToday - start.kg) / totalKg).clamp(0.0, 1.0);

  /// How far the trend is behind the plan today, kg; negative ahead.
  double get behindKg => (nowKg - planKgToday) * -totalKg.sign;

  /// The trend's pace over its last [days] (fewer with less history,
  /// none under a week), kg a week, with the days it spans.
  ({double kgPerWeek, int days})? recentPace([int days = 30]) {
    final span = trend.length - 1 < days ? trend.length - 1 : days;
    if (span < 7) return null;
    return (
      kgPerWeek: (trend.last - trend[trend.length - 1 - span]) / span * 7,
      days: span,
    );
  }

  /// The pace since the start; none under a week in.
  double? get sinceStartKgPerWeek =>
      daysIn < 7 ? null : (nowKg - start.kg) / daysIn * 7;

  /// The day the target is reached at [kgPerWeek] from today; null when
  /// that leads away from it, or there.
  DateTime? arrivalAt(double? kgPerWeek) {
    if (kgPerWeek == null) return null;
    final days = daysToTarget(nowKg, targetKg, kgPerWeek / 7);
    return days == null
        ? null
        : DateTime(today.year, today.month, today.day + days);
  }

  /// The milestones from the start to the target every [step] (in a unit
  /// [perKg] times a kg), each with the day the trend reached it (null
  /// before [trend]'s first day) or, not yet, when [kgPerWeek] gets there.
  List<({double kg, bool reached, DateTime? on})> milestones(
    num step, {
    double perKg = 1,
    double? kgPerWeek,
  }) {
    final firstDay = DateTime(
      today.year,
      today.month,
      today.day - (trend.length - 1),
    );
    final down = totalKg < 0;
    bool past(double kg, double m) => down ? kg <= m : kg >= m;
    return [
      for (final m in [
        ...milestonesKg(start.kg, targetKg, step, perKg: perKg, max: 50),
        targetKg,
      ])
        if (past(nowKg, m))
          (kg: m, reached: true, on: _reachedOn(m, firstDay, past))
        else
          (
            kg: m,
            reached: false,
            on: kgPerWeek == null
                ? null
                : _dayAt(daysToTarget(nowKg, m, kgPerWeek / 7)),
          ),
    ];
  }

  DateTime? _reachedOn(
    double m,
    DateTime firstDay,
    bool Function(double, double) past,
  ) {
    for (final (i, kg) in trend.indexed) {
      if (past(kg, m)) {
        return i == 0
            ? null
            : DateTime(firstDay.year, firstDay.month, firstDay.day + i);
      }
    }
    return null;
  }

  DateTime? _dayAt(int? days) =>
      days == null ? null : DateTime(today.year, today.month, today.day + days);
}

/// The goal as the page shows it: [inputs] null before the first
/// weigh-in, [progress] null with no target.
typedef GoalState = ({GoalPlanInputs? inputs, GoalProgress? progress});

/// The active profile's goal start, in the adaptive box.
class GoalStartStore {
  static const key = 'goalStart';
  static final _log = Logger('GoalStartStore');

  final AdaptiveStore _store;

  GoalStartStore([AdaptiveStore? store]) : _store = store ?? AdaptiveStore();

  Future<GoalStart?> read() async {
    final json = await _store.readKey(key);
    if (json is! Map) return null;
    try {
      return GoalStart.fromJson(json);
    } catch (e) {
      _log.warning('Unreadable goal start, starting anew: $e');
      return null;
    }
  }

  Future<void> save(GoalStart start) => _store.writeKey(key, start.toJson());

  /// Reads the goal and keeps its start: the one stored, or a new one
  /// when the target changed.
  Future<GoalState> load({AdaptiveService? service, DateTime? now}) async {
    // The whole trend the service keeps.
    final inputs = await (service ?? AdaptiveService.fromLocator()).goalPlan(
      pastDays: 1 << 20,
    );
    final target = inputs?.targetWeightKg;
    if (inputs == null || target == null) {
      return (inputs: inputs, progress: null);
    }
    final t = now ?? DateTime.now();
    final today = DateTime(t.year, t.month, t.day);
    final stored = await read();
    final start = resolveGoalStart(
      stored: stored,
      targetKg: target,
      paceKgPerWeek: inputs.paceKgPerWeek,
      paceSince: stored == null || stored.paceKgPerWeek != null
          ? null
          : paceSetOn(await _store.history(), inputs.paceKgPerWeek),
      trend: inputs.pastTrendKg,
      today: today,
    );
    if (!identical(start, stored)) await save(start);
    return (
      inputs: inputs,
      progress: GoalProgress(
        start: start,
        nowKg: inputs.nowKg,
        paceKgPerWeek: inputs.paceKgPerWeek,
        trend: inputs.pastTrendKg,
        today: today,
      ),
    );
  }

  static bool _listening = false;

  /// Keeps the start now and after each save of the goal; once, however
  /// often the app starts over.
  static void start() {
    unawaited(sync());
    if (_listening) return;
    _listening = true;
    paceChanges.addListener(() => unawaited(sync()));
  }

  /// At start-up and after the goal is saved, so a new target starts on
  /// the day it was set, not the day the page is next opened.
  static Future<void> sync() async {
    try {
      await GoalStartStore().load();
    } catch (e, s) {
      _log.warning('Goal start not kept', e, s);
    }
  }
}
