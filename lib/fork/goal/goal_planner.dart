import 'package:opennutritracker/core/utils/calc/calendar_day_calc.dart';
import 'package:opennutritracker/fork/phases/phases.dart';

/// The goal planner's paces, kg a week: gentle, steady and fast.
const cutPacesKg = [0.25, 0.5, 0.75];
const bulkPacesKg = [0.1, 0.25, 0.4];

/// A maintenance goal's lengths, in weeks.
const maintainWeeksChoices = [4, 8, 12];

/// Diet breaks: [breakWeeks] at maintenance after every [breakEveryWeeks]
/// of cutting.
const breakEveryWeeks = 6;
const breakWeeks = 2;

DateTime _date(DateTime t) => DateTime(t.year, t.month, t.day);

/// What the goal planner's steps choose, before it is a [PhasePlan].
class GoalDraft {
  final PhaseKind kind;

  /// The trend weight the goal starts from.
  final double startKg;

  /// The weight a cut or bulk ends at; a maintenance goal has none.
  final double? targetKg;
  final DateTime start;

  /// kg a week, unsigned; the kind gives the sign.
  final double paceKg;
  final bool breaks;
  final int maintainWeeks;

  const GoalDraft({
    required this.kind,
    required this.startKg,
    required this.start,
    this.targetKg,
    this.paceKg = 0.5,
    this.breaks = false,
    this.maintainWeeks = 8,
  });

  /// A new goal from [nowKg]: [targetKg] decides the kind, a cut at the
  /// steady pace without one.
  factory GoalDraft.fresh(double nowKg, DateTime today, {double? targetKg}) {
    final kind = targetKg == null || (targetKg - nowKg).abs() < 0.1
        ? PhaseKind.cut
        : targetKg < nowKg
        ? PhaseKind.cut
        : PhaseKind.bulk;
    return GoalDraft(
      kind: kind,
      startKg: nowKg,
      start: _date(today),
      targetKg: targetKg != null && (targetKg - nowKg).abs() >= 0.1
          ? targetKg
          : null,
      paceKg: kind == PhaseKind.bulk ? bulkPacesKg[1] : cutPacesKg[1],
    );
  }

  /// The draft of a running [plan], to edit it.
  factory GoalDraft.of(PhasePlan plan, double nowKg) {
    final kind = plan.kind;
    final paced = plan.phases.where((p) => p.kind == kind).firstOrNull;
    return GoalDraft(
      kind: kind,
      startKg: plan.startKg ?? nowKg,
      start: plan.start,
      targetKg: plan.targetKg,
      paceKg: (paced?.kgPerWeek ?? 0.5).abs(),
      breaks:
          plan.phases.any((p) => p.kind == PhaseKind.maintain) &&
          kind == PhaseKind.cut,
      maintainWeeks: kind == PhaseKind.maintain
          ? plan.phases.fold(0, (w, p) => w + p.weeks)
          : 8,
    );
  }

  GoalDraft copyWith({
    PhaseKind? kind,
    double? startKg,
    double? Function()? targetKg,
    DateTime? start,
    double? paceKg,
    bool? breaks,
    int? maintainWeeks,
  }) => GoalDraft(
    kind: kind ?? this.kind,
    startKg: startKg ?? this.startKg,
    targetKg: targetKg == null ? this.targetKg : targetKg(),
    start: start ?? this.start,
    paceKg: paceKg ?? this.paceKg,
    breaks: breaks ?? this.breaks,
    maintainWeeks: maintainWeeks ?? this.maintainWeeks,
  );

  /// The paces offered for the kind; none for maintenance.
  List<double> get paces => switch (kind) {
    PhaseKind.cut => cutPacesKg,
    PhaseKind.bulk => bulkPacesKg,
    PhaseKind.maintain => const [],
  };

  /// kg a week, signed.
  double get signedPace => switch (kind) {
    PhaseKind.cut => -paceKg,
    PhaseKind.bulk => paceKg,
    PhaseKind.maintain => 0,
  };

  /// Why the goal cannot be planned yet; null when it can.
  String? get problem {
    if (kind == PhaseKind.maintain) return null;
    final target = targetKg;
    if (target == null) return 'Set a target weight.';
    if (kind == PhaseKind.cut && target > startKg - 0.1) {
      return 'A cut needs a target below your weight now.';
    }
    if (kind == PhaseKind.bulk && target < startKg + 0.1) {
      return 'A bulk needs a target above your weight now.';
    }
    return null;
  }

  /// The plan the draft makes: a cut or bulk until the target (a cut cut
  /// into stretches by diet breaks), or maintenance for its weeks.
  PhasePlan toPlan() {
    final target = targetKg;
    if (kind == PhaseKind.maintain || target == null) {
      return PhasePlan(
        start: start,
        startKg: startKg,
        phases: [
          DietPhase(
            kind: PhaseKind.maintain,
            kgPerWeek: 0,
            weeks: maintainWeeks,
          ),
        ],
      );
    }
    var left = DietPhase.weeksTo(startKg, target, signedPace);
    final phases = <DietPhase>[];
    if (kind == PhaseKind.cut && breaks) {
      while (left > breakEveryWeeks) {
        phases
          ..add(
            DietPhase(
              kind: PhaseKind.cut,
              kgPerWeek: signedPace,
              weeks: breakEveryWeeks,
            ),
          )
          ..add(
            const DietPhase(
              kind: PhaseKind.maintain,
              kgPerWeek: 0,
              weeks: breakWeeks,
            ),
          );
        left -= breakEveryWeeks;
      }
    }
    phases.add(
      DietPhase(
        kind: kind,
        kgPerWeek: signedPace,
        weeks: left,
        untilKg: target,
      ),
    );
    return PhasePlan(
      start: start,
      startKg: startKg,
      targetKg: target,
      phases: phases,
    );
  }
}

/// Where a goal stands today.
enum GoalStatus { running, reached, ended }

/// [plan] at the trend [nowKg] on [today]: reached once the trend is at
/// its target or past it, ended once its last phase is over without.
GoalStatus goalStatus(PhasePlan plan, double nowKg, DateTime today) {
  final target = plan.targetKg;
  if (target != null) {
    final from = plan.startKg;
    final way = from != null && (target - from).abs() >= 0.1
        ? (target - from).sign
        : plan.kind == PhaseKind.bulk
        ? 1.0
        : -1.0;
    final left = target - nowKg;
    if (left.abs() < 0.1 || left.sign != way) return GoalStatus.reached;
  }
  return _date(today).isBefore(plan.end)
      ? GoalStatus.running
      : GoalStatus.ended;
}

/// [plan] completed on [today] at the trend [nowKg].
GoalRecord completedGoal(PhasePlan plan, double? nowKg, DateTime today) =>
    GoalRecord(
      kind: plan.kind,
      start: plan.start,
      end: _date(today),
      startKg: plan.startKg,
      endKg: nowKg,
      targetKg: plan.targetKg,
      extensions: plan.extensions,
    );

/// [plan] extended from [today] at the trend [nowKg]: until [untilKg]
/// (the plan's target by default) or for [weeks], after a diet break when
/// [breakFirst]. The running phase ends this week; a plan over for a week
/// or more holds maintenance until now.
PhasePlan extendedPlan(
  PhasePlan plan, {
  required DateTime today,
  required double nowKg,
  double? untilKg,
  int? weeks,
  bool breakFirst = false,
}) {
  final day = _date(today);
  final index = plan.indexOn(day);
  final kept = <DietPhase>[
    ...plan.phases.take(index.clamp(0, plan.phases.length)),
  ];
  if (index >= 0 && index < plan.phases.length) {
    final ran = CalendarDayCalc.daysBetween(plan.startOf(index), day);
    final p = plan.phases[index];
    kept.add(
      DietPhase(
        kind: p.kind,
        kgPerWeek: p.kgPerWeek,
        weeks: (ran / 7).ceil().clamp(1, p.weeks),
      ),
    );
  } else if (index >= plan.phases.length) {
    final gap = CalendarDayCalc.daysBetween(plan.end, day) ~/ 7;
    if (gap > 0) {
      kept.add(
        DietPhase(
          kind: PhaseKind.maintain,
          kgPerWeek: 0,
          weeks: gap.clamp(1, 52),
        ),
      );
    }
  }
  if (breakFirst) {
    kept.add(
      const DietPhase(
        kind: PhaseKind.maintain,
        kgPerWeek: 0,
        weeks: breakWeeks,
      ),
    );
  }
  final kind = plan.kind;
  final pace = plan.phases
      .lastWhere((p) => p.kind == kind, orElse: () => plan.phases.last)
      .kgPerWeek;
  final until = weeks == null ? (untilKg ?? plan.targetKg) : untilKg;
  kept.add(
    DietPhase(
      kind: kind,
      kgPerWeek: pace,
      weeks:
          weeks ??
          (until == null
              ? breakEveryWeeks
              : DietPhase.weeksTo(nowKg, until, pace)),
      untilKg: weeks == null ? until : null,
    ),
  );
  return PhasePlan(
    start: plan.start,
    startKg: plan.startKg,
    targetKg: untilKg ?? plan.targetKg,
    extensions: plan.extensions + 1,
    phases: kept,
  );
}

/// The phase kind on [day]: the running plan's, a completed goal's, or
/// null on a day no goal covers. After the plan's end, maintenance.
PhaseKind? kindOn(DateTime day, PhasePlan? plan, List<GoalRecord> history) {
  final date = _date(day);
  if (plan != null) {
    final i = plan.indexOn(date);
    if (i >= plan.phases.length) return PhaseKind.maintain;
    if (i >= 0) return plan.phases[i].kind;
  }
  for (final r in history.reversed) {
    if (!date.isBefore(_date(r.start)) && !date.isAfter(_date(r.end))) {
      return r.kind;
    }
  }
  return null;
}
