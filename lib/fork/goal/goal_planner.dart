import 'package:opennutritracker/core/utils/calc/calendar_day_calc.dart';
import 'package:opennutritracker/fork/phases/phases.dart';

/// The goal planner's paces, kg a week: gentle, steady and fast.
const cutPacesKg = [0.25, 0.5, 0.75];
const bulkPacesKg = [0.1, 0.25, 0.4];

/// A custom pace's range and step, kg a week.
const cutCustomPaceKg = (min: 0.1, max: 1.5);
const bulkCustomPaceKg = (min: 0.05, max: 0.75);
const customPaceStepKg = 0.05;

/// A maintenance goal's lengths, in weeks.
const maintainWeeksChoices = [4, 8, 12];

/// A custom maintenance length's range, in weeks.
const customMaintainWeeks = (min: 1, max: 52);

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
    // The pace now: an extension's, after the first.
    final paced = plan.phases.where((p) => p.kind == kind).lastOrNull;
    final phases = plan.phases;
    return GoalDraft(
      kind: kind,
      startKg: plan.startKg ?? nowKg,
      start: plan.start,
      targetKg: plan.targetKg,
      paceKg: (paced?.kgPerWeek ?? 0.5).abs(),
      // Regular breaks, not an extension's one-off break or a gap held at
      // maintenance.
      breaks:
          kind == PhaseKind.cut &&
          [
            for (var i = 1; i < phases.length; i++)
              phases[i].kind == PhaseKind.maintain &&
                  phases[i].weeks == breakWeeks &&
                  phases[i - 1].kind == PhaseKind.cut &&
                  phases[i - 1].weeks == breakEveryWeeks,
          ].any((b) => b),
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

/// [plan]'s phases run by [day]: those over, the one running cut to the
/// weeks begun (so it ends this week), and, a week or more after the
/// plan's end, the weeks held at maintenance since.
List<DietPhase> _ranUntil(PhasePlan plan, DateTime day) {
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
      kept.add(DietPhase(kind: PhaseKind.maintain, kgPerWeek: 0, weeks: gap));
    }
  }
  return kept;
}

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
  final kept = _ranUntil(plan, _date(today));
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
  // A reached goal run on for weeks aims at no weight: kept, its target
  // would show as reached again at once.
  final reached = goalStatus(plan, nowKg, today) == GoalStatus.reached;
  final target = untilKg ?? (weeks != null && reached ? null : plan.targetKg);
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
    targetKg: target,
    extensions: plan.extensions + 1,
    phases: kept,
  );
}

/// The phase kind on [day]: the running plan's, an [upcoming] goal's, a
/// completed goal's, or null on a day no goal covers. After the last
/// plan's end, maintenance.
PhaseKind? kindOn(
  DateTime day,
  PhasePlan? plan,
  List<GoalRecord> history, {
  List<PhasePlan> upcoming = const [],
}) {
  final date = _date(day);
  for (final p in [?plan, ...upcoming].reversed) {
    final i = p.indexOn(date);
    if (i >= p.phases.length) return PhaseKind.maintain;
    if (i >= 0) return p.phases[i].kind;
  }
  for (final r in history.reversed) {
    if (!date.isBefore(_date(r.start)) && !date.isAfter(_date(r.end))) {
      return r.kind;
    }
  }
  return null;
}

/// [plan] edited as [draft] has it, on [today] at the trend [nowKg]: once
/// begun, the phases run so far stay as they were, and [draft]'s follow
/// from the end of this week; not begun yet, [draft]'s plan. Either keeps
/// [plan]'s extensions.
PhasePlan editedPlan(
  PhasePlan plan,
  GoalDraft draft, {
  required DateTime today,
  required double nowKg,
}) {
  final day = _date(today);
  if (plan.indexOn(day) < 0) {
    final fresh = draft.toPlan();
    return PhasePlan(
      start: fresh.start,
      startKg: fresh.startKg,
      targetKg: fresh.targetKg,
      extensions: plan.extensions,
      phases: fresh.phases,
    );
  }
  final kept = _ranUntil(plan, day);
  final from = PhasePlan(start: plan.start, phases: kept).end;
  final ahead = draft.copyWith(start: from, startKg: nowKg).toPlan();
  return PhasePlan(
    start: plan.start,
    startKg: plan.startKg,
    targetKg: ahead.targetKg,
    extensions: plan.extensions,
    phases: [...kept, ...ahead.phases],
  );
}

/// The weight [plan] ends at: its target, else where its paces lead.
double? endKgOf(PhasePlan plan) =>
    plan.targetKg ?? plan.weightAt(plan.phases.length);

/// What is wrong with queued goal [plan] where it now starts: a target it
/// has passed, after a goal before it moved, went or changed.
String? queuedProblem(PhasePlan plan) {
  final kg = plan.startKg;
  return kg == null ? null : GoalDraft.of(plan, kg).problem;
}

/// [plan] planned again from [start] at [startKg]: the same goal, pace and
/// breaks, its weeks worked out afresh.
PhasePlan restarted(PhasePlan plan, DateTime start, double startKg) =>
    GoalDraft.of(
      plan,
      startKg,
    ).copyWith(start: _date(start), startKg: startKg).toPlan();

/// The goals in [upcoming], each [restarted] the day after the one before
/// ends, from the weight it ends at (or [fromKg]): the first after
/// [current].
List<PhasePlan> reflowed(
  PhasePlan current,
  List<PhasePlan> upcoming, {
  required double fromKg,
}) {
  var start = current.end;
  var kg = endKgOf(current) ?? fromKg;
  final out = <PhasePlan>[];
  for (final p in upcoming) {
    final next = restarted(p, start, kg);
    out.add(next);
    start = next.end;
    kg = endKgOf(next) ?? kg;
  }
  return out;
}
