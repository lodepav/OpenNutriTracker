import 'package:intl/intl.dart' as intl;
import 'package:opennutritracker/core/domain/entity/body_weight_unit_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_weight_goal_entity.dart';
import 'package:opennutritracker/fork/adaptive/goal_plan.dart'
    show daysToTarget;
import 'package:opennutritracker/fork/goal/goal_planner.dart';
import 'package:opennutritracker/fork/goal/goal_progress.dart';
import 'package:opennutritracker/fork/goal/goal_you_tile.dart';
import 'package:opennutritracker/fork/goal/phase_colors.dart' show phaseName;
import 'package:opennutritracker/fork/phases/phases.dart';
import 'package:opennutritracker/fork/report/rate_text.dart';
import 'package:opennutritracker/fork/trends/trend_stats.dart' show weightIn;
import 'package:opennutritracker/fork/units/weight_text.dart';

/// What a goal summary offers under its figures.
enum GoalAction {
  plan('Plan a goal'),
  completeOrExtend('Complete or extend');

  final String label;

  const GoalAction(this.label);
}

/// Where a goal summary goes on a tap: the planner, Goal progress, Goal
/// reached, or the sheet that extends or completes a goal that ended.
enum GoalTap { planner, progress, reached, extend }

/// The one summary of the weight goal that You, Trends, the weight trend,
/// the Trends goal card and Goal progress all show (design A, "figure
/// first").
class GoalSummary {
  final String value;
  final String? suffix;
  final String? note;

  /// How far along, 0 to 1; null for no bar.
  final double? bar;

  /// The plan's phase bar in place of [bar].
  final bool phases;
  final GoalAction? action;
  final GoalTap tap;

  /// The goal [phases], [GoalTap.reached] and [GoalTap.extend] are of.
  final PhasePlan? plan;
  final double? nowKg;

  /// Where the bar starts and ends, for the card's labels under it.
  final ({double kg, DateTime day})? start;
  final double? targetKg;

  /// Maintaining since a completed goal: the card offers the completed
  /// goals.
  final bool sinceGoal;

  const GoalSummary({
    required this.value,
    this.suffix,
    this.note,
    this.bar,
    this.phases = false,
    this.action,
    required this.tap,
    this.plan,
    this.nowKg,
    this.start,
    this.targetKg,
    this.sinceGoal = false,
  });

  /// [action] where a tile's tap does it; a tile that opens Goal progress
  /// offers no planner (the card keeps the action as its button).
  GoalAction? get tileAction => switch ((action, tap)) {
    (GoalAction.plan, GoalTap.planner) => action,
    (GoalAction.completeOrExtend, GoalTap.reached || GoalTap.extend) => action,
    _ => null,
  };

  /// "Goal, 7.1 kg to go, Cut, about Mar 30", one label for the tile.
  String spoken([String label = 'Goal']) => [
    label,
    suffix == null ? value : '$value $suffix',
    ?note?.replaceAll(' · ', ', '),
  ].join(', ');
}

/// The trend's pace over the last 30 days, kg a day; null with less, as
/// the weight trend page's goal tile counts it.
double? kgPerDay30(GoalProgress? progress) => switch (progress?.recentPace()) {
  (kgPerWeek: final k, days: 30) => k / 7,
  _ => null,
};

/// [d] as the goal's dates read: "Oct 29", with the year outside [today]'s.
String goalDay(String locale, DateTime today, DateTime d) =>
    (d.year == today.year
            ? intl.DateFormat.MMMd(locale)
            : intl.DateFormat.yMMMd(locale))
        .format(d);

DateTime _date(DateTime t) => DateTime(t.year, t.month, t.day);

/// The goal from what the places that show it read: the [plan] running and
/// the goals completed before ([history]), the profile's [pace], its
/// [targetKg], the trend [nowKg], the kept start's [progress] and the
/// trend's 30-day pace [kgPerDay] ([kgPerDay30]), on [today]. [locale] is
/// the date format's, [unitLabel] the weight unit's.
GoalSummary goalSummary({
  required String locale,
  required BodyWeightUnit unit,
  required String unitLabel,
  required DateTime today,
  PhasePlan? plan,
  List<GoalRecord> history = const [],
  ({UserWeightGoalEntity goal, double? kgPerWeek})? pace,
  double? targetKg,
  double? nowKg,
  GoalProgress? progress,
  double? kgPerDay,
}) {
  String day(DateTime d) => goalDay(locale, today, d);
  // The kept start counts only for the target it was kept for.
  final kept = switch ((progress, plan?.targetKg ?? targetKg)) {
    (final p?, final t?) when (p.targetKg - t).abs() < 0.05 => p,
    _ => null,
  };
  String there(double target) {
    final reached = kept == null || !kept.reached
        ? null
        // A step past the target leaves only the target's row.
        : kept.milestones(double.maxFinite).last;
    return '${weightText(target, unit)}'
        '${reached?.on == null ? '' : ' on ${day(reached!.on!)}'}'
        ' · keep it or go on';
  }

  ({double kg, DateTime day})? startOf() => kept != null
      ? (kg: kept.start.kg, day: kept.start.date)
      : plan?.startKg != null
      ? (kg: plan!.startKg!, day: plan.start)
      : null;
  double? barOf(double target, double now) {
    final from = startOf()?.kg;
    if (from == null || (target - from).abs() < 0.1) return null;
    return ((now - from) / (target - from)).clamp(0.0, 1.0);
  }

  if (plan != null) {
    final target = plan.targetKg;
    final status = nowKg != null
        ? goalStatus(plan, nowKg, today)
        : _date(today).isBefore(plan.end)
        ? GoalStatus.running
        : GoalStatus.ended;
    if (status == GoalStatus.reached) {
      return GoalSummary(
        value: 'There',
        note: there(target!),
        bar: 1,
        action: GoalAction.completeOrExtend,
        tap: GoalTap.reached,
        plan: plan,
        nowKg: nowKg,
        start: startOf(),
        targetKg: target,
      );
    }
    if (status == GoalStatus.ended) {
      // Not "There": the plan ran out short of its target, or had none.
      return GoalSummary(
        value: 'Ended',
        note: '${day(plan.lastDay)} · keep it or go on',
        action: GoalAction.completeOrExtend,
        tap: nowKg == null ? GoalTap.progress : GoalTap.extend,
        plan: plan,
        nowKg: nowKg,
      );
    }
    if (target != null && nowKg != null) {
      final left = goalLeftKg(target, nowKg, kept);
      return GoalSummary(
        value: weightIn(unit, left).toStringAsFixed(1),
        suffix: '$unitLabel to go',
        note: '${plan.kind.label} · about ${day(plan.lastDay)}',
        bar: barOf(target, nowKg),
        tap: GoalTap.progress,
        plan: plan,
        nowKg: nowKg,
        start: startOf(),
        targetKg: target,
      );
    }
    final index = plan.indexOn(today);
    return GoalSummary(
      value: switch (plan.kind) {
        PhaseKind.cut => 'Cut',
        PhaseKind.maintain => 'Maintain',
        PhaseKind.bulk => 'Bulk',
      },
      suffix: 'until ${day(plan.lastDay)}',
      note: index < 0 || index >= plan.phases.length
          ? null
          : 'Now: ${phaseName(plan.phases[index].kind, inCut: plan.kind == PhaseKind.cut).toLowerCase()}',
      phases: true,
      tap: GoalTap.progress,
      plan: plan,
      nowKg: nowKg,
    );
  }

  if (targetKg != null && nowKg != null) {
    final left = goalLeftKg(targetKg, nowKg, kept);
    if (left < 0.1) {
      return GoalSummary(
        value: 'There',
        note: there(targetKg),
        bar: 1,
        action: GoalAction.plan,
        tap: GoalTap.progress,
        nowKg: nowKg,
        start: startOf(),
        targetKg: targetKg,
      );
    }
    final days = kgPerDay == null
        ? null
        : daysToTarget(nowKg, targetKg, kgPerDay);
    final t = _date(today);
    return GoalSummary(
      value: weightIn(unit, left).toStringAsFixed(1),
      suffix: '$unitLabel to go',
      note: kgPerDay == null
          ? 'Under 30 days of trend'
          : days == null
          ? 'Not at your 30-day pace'
          : 'About ${day(DateTime(t.year, t.month, t.day + days))} '
                'at your 30-day pace',
      bar: barOf(targetKg, nowKg),
      action: GoalAction.plan,
      tap: GoalTap.progress,
      nowKg: nowKg,
      start: startOf(),
      targetKg: targetKg,
    );
  }
  return untargetedGoal(locale, today, history, unit, pace: pace);
}

/// No plan and no target: maintenance since the last goal completed,
/// unless the profile's [pace] loses or gains, as a rate set on You after
/// the goal ended is what the budget follows; else that pace, its verb
/// the value ([plannedRateText]), or its direction alone with no weekly
/// rate; none when the profile could not be read. A weekly rate alone is
/// no goal (the user, 2026-10-31), so each offers to plan one.
GoalSummary untargetedGoal(
  String locale,
  DateTime today,
  List<GoalRecord> history,
  BodyWeightUnit unit, {
  ({UserWeightGoalEntity goal, double? kgPerWeek})? pace,
}) {
  final rate = pace?.kgPerWeek;
  final moving =
      pace != null &&
      (rate == null
          ? pace.goal != UserWeightGoalEntity.maintainWeight
          : weeklyRateShown(rate, unit) != 0);
  final since = maintainingSince(null, history);
  if (since != null && !moving) {
    final last = history.firstWhere((r) => r.end == since);
    final target = last.targetKg;
    return GoalSummary(
      value: 'Maintain',
      suffix: 'since ${goalDay(locale, today, since)}',
      note: target == null
          ? null
          : 'Last goal: ${last.kind.label.toLowerCase()} to '
                '${weightText(target, unit)}',
      action: GoalAction.plan,
      tap: GoalTap.planner,
      sinceGoal: true,
    );
  }
  if (pace == null) {
    return const GoalSummary(
      value: noGoalText,
      note: 'Plan a pace, dates and calories',
      action: GoalAction.plan,
      tap: GoalTap.planner,
    );
  }
  if (!moving) {
    return const GoalSummary(
      value: 'Maintain',
      note: 'No end date',
      action: GoalAction.plan,
      tap: GoalTap.planner,
    );
  }
  // Whole, "Losing 0.4 kg a week" is cut off in a 360 dp Trends tile.
  final text = plannedRateText(pace.goal, rate, unit);
  final verb = text.indexOf(' ');
  return GoalSummary(
    value: text.substring(0, verb),
    // "Losing weight" with no rate: the verb alone.
    suffix: rate == null ? null : text.substring(verb + 1),
    note: 'No end date',
    action: GoalAction.plan,
    tap: GoalTap.planner,
  );
}
