import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;
import 'package:opennutritracker/fork/phases/phases.dart';
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
/// until it ends; maintenance since the last goal completed; or none.
({String value, String? note}) untargetedGoal(
  BuildContext context,
  PhasePlan? plan,
  DateTime? since,
) {
  if (plan != null) {
    final until = intl.DateFormat.MMMd(
      Localizations.localeOf(context).toLanguageTag(),
    ).format(plan.end.subtract(const Duration(hours: 12)));
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

typedef GoalTileLoad =
    Future<({PhasePlan? plan, List<GoalRecord> history})> Function();

/// The You tab's goal tile: [value], [note] and [below] while a goal
/// runs or one is set in the profile; with none, "No goal", or
/// "Maintaining since …" after a completed one, and "Plan a goal".
class GoalYouTile extends StatefulWidget {
  final String value;
  final String? note;
  final String? below;

  /// Whether the profile has a pace or a target weight of its own.
  final bool profileGoal;
  final String title;
  final VoidCallback onTap;
  final GoalTileLoad? load;

  const GoalYouTile({
    super.key,
    required this.title,
    required this.value,
    required this.note,
    required this.below,
    required this.profileGoal,
    required this.onTap,
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
    final none = goals != null && goals.plan == null && !widget.profileGoal;
    final since = none ? maintainingSince(null, goals.history) : null;
    return YouTile(
      identifier: 'profile-goal-tile',
      title: widget.title,
      value: !none
          ? widget.value
          : since == null
          ? noGoalText
          : 'Maintain',
      note: !none
          ? widget.note
          : since == null
          ? null
          : _sinceText(context, since),
      below: none ? 'Plan a goal' : widget.below,
      hint: 'Open the goal and its plan',
      onTap: widget.onTap,
    );
  }
}
