import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;
import 'package:opennutritracker/core/domain/entity/body_weight_unit_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_weight_goal_entity.dart';
import 'package:opennutritracker/fork/goal/goal_planner.dart';
import 'package:opennutritracker/fork/phases/phases.dart';
import 'package:opennutritracker/fork/report/rate_text.dart';
import 'package:opennutritracker/fork/you/you_widgets.dart';

/// What the app calls having no goal, on the You tile, Goal progress and
/// Trends alike.
const noGoalText = 'No goal';

/// The day the last completed goal ended, so maintenance began: null
/// while a goal runs, or before any was completed.
DateTime? maintainingSince(PhasePlan? plan, List<GoalRecord> history) {
  if (plan != null || history.isEmpty) return null;
  return history.map((r) => r.end).reduce((a, b) => a.isAfter(b) ? a : b);
}

/// "since Oct 29".
String _sinceText(BuildContext context, DateTime since) =>
    'since ${intl.DateFormat.MMMd(Localizations.localeOf(context).toLanguageTag()).format(since)}';

/// The goal with no target weight: a goal running, a maintenance one,
/// until it ends; maintenance since the last goal completed, or since a
/// goal ended that is not yet marked; or none.
({String value, String? note}) untargetedGoal(
  BuildContext context,
  PhasePlan? plan,
  DateTime? since, {
  DateTime? today,
}) {
  if (plan != null && !(today ?? DateTime.now()).isBefore(plan.end)) {
    return (value: 'Maintain', note: _sinceText(context, plan.end));
  }
  if (plan != null) {
    final until = intl.DateFormat.MMMd(
      Localizations.localeOf(context).toLanguageTag(),
    ).format(plan.lastDay);
    return (
      value: switch (plan.kind) {
        PhaseKind.cut => 'Cut',
        PhaseKind.maintain => 'Maintain',
        PhaseKind.bulk => 'Bulk',
      },
      note: 'until $until',
    );
  }
  if (since != null) {
    return (value: 'Maintain', note: _sinceText(context, since));
  }
  return (value: noGoalText, note: null);
}

/// "Maintaining since Oct 29".
String maintainingSinceText(BuildContext context, DateTime since) =>
    'Maintaining ${_sinceText(context, since)}';

/// The profile's plan with no target weight: "Losing 0.4 kg a week" at its
/// weekly rate, which the budget follows over the direction; the direction
/// alone without one.
String plannedRateText(
  UserWeightGoalEntity goal,
  double? kgPerWeek,
  BodyWeightUnit unit,
) {
  if (kgPerWeek == null) {
    return switch (goal) {
      UserWeightGoalEntity.loseWeight => 'Losing weight',
      UserWeightGoalEntity.maintainWeight => 'Keeping your weight',
      UserWeightGoalEntity.gainWeight => 'Gaining weight',
    };
  }
  if (weeklyRateShown(kgPerWeek, unit) == 0) return 'Keeping your weight';
  return '${kgPerWeek < 0 ? 'Losing' : 'Gaining'} '
      '${unsignedRateText(kgPerWeek, unit)}';
}

typedef GoalTileLoad =
    Future<({PhasePlan? plan, List<GoalRecord> history})> Function();

/// The You tab's goal tile: [value], [note] and [below] while a goal
/// runs or one is set in the profile, or the profile's plan with an offer
/// to set a target; "Maintain since …" after a completed one, and "Plan a
/// goal".
class GoalYouTile extends StatefulWidget {
  final String value;
  final String? note;
  final String? below;

  /// Whether the profile has a target weight of its own; its weekly rate
  /// alone is no goal (the user, 2026-10-31).
  final bool profileGoal;
  final String title;
  final VoidCallback onTap;

  /// The tap while the tile offers to set a target ("Set a target weight");
  /// [onTap] without one.
  final VoidCallback? onSetTarget;
  final GoalTileLoad? load;

  const GoalYouTile({
    super.key,
    required this.title,
    required this.value,
    required this.note,
    required this.below,
    required this.profileGoal,
    required this.onTap,
    this.onSetTarget,
    this.load,
  });

  @override
  State<GoalYouTile> createState() => _GoalYouTileState();
}

class _GoalYouTileState extends State<GoalYouTile> {
  ({PhasePlan? plan, List<GoalRecord> history})? _goals;

  @override
  void initState() {
    super.initState();
    PhaseStore.changes.addListener(_reload);
    _reload();
  }

  @override
  void dispose() {
    PhaseStore.changes.removeListener(_reload);
    super.dispose();
  }

  Future<void> _reload() async {
    final ({PhasePlan? plan, List<GoalRecord> history}) goals;
    try {
      goals = await (widget.load ?? _loadGoals)();
    } catch (_) {
      // No store in a test: the profile's own goal shows.
      return;
    }
    if (mounted) setState(() => _goals = goals);
  }

  static Future<({PhasePlan? plan, List<GoalRecord> history})>
  _loadGoals() async {
    final store = PhaseStore();
    return (plan: await store.plan(), history: await store.history());
  }

  @override
  Widget build(BuildContext context) {
    final goals = _goals;
    final plan = goals?.plan;
    // No target and no goal running: [below] offers one, as the tap does.
    final offer = !widget.profileGoal && plan == null;
    final since = offer && goals != null
        ? maintainingSince(null, goals.history)
        : null;
    final untargeted = since != null
        ? untargetedGoal(context, null, since)
        : plan != null && plan.targetKg == null
        ? untargetedGoal(context, plan, null)
        : null;
    final value = untargeted?.value ?? widget.value;
    final note = untargeted != null ? untargeted.note : widget.note;
    final below = since != null
        ? 'Plan a goal'
        : untargeted != null
        ? null
        : widget.below;
    return YouTile(
      identifier: 'profile-goal-tile',
      title: widget.title,
      value: value,
      note: note,
      below: below,
      spokenLabel: [
        widget.title,
        note == null ? value : '$value $note',
        if (!offer && below != null) below,
      ].join(', '),
      hint: offer && below != null ? below : 'Open the goal',
      onTap: offer && since == null
          ? widget.onSetTarget ?? widget.onTap
          : widget.onTap,
    );
  }
}
