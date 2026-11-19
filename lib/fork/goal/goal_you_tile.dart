import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;
import 'package:opennutritracker/core/domain/entity/body_weight_unit_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_weight_goal_entity.dart';
import 'package:opennutritracker/fork/adaptive/goal_saving.dart'
    show paceChanges;
import 'package:opennutritracker/fork/goal/goal_summary.dart';
import 'package:opennutritracker/fork/goal/goal_summary_view.dart';
import 'package:opennutritracker/fork/phases/phases.dart';
import 'package:opennutritracker/fork/report/rate_text.dart';
import 'package:opennutritracker/fork/trends/trend_detail.dart'
    show weightUnitLabel;
import 'package:opennutritracker/fork/trends/trends_overview.dart'
    show TrendsGoal, TrendsOverview;

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

const _keeping = 'Keeping your weight';

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
      UserWeightGoalEntity.maintainWeight => _keeping,
      UserWeightGoalEntity.gainWeight => 'Gaining weight',
    };
  }
  if (weeklyRateShown(kgPerWeek, unit) == 0) return _keeping;
  return '${kgPerWeek < 0 ? 'Losing' : 'Gaining'} '
      '${unsignedRateText(kgPerWeek, unit)}';
}

/// The You tab's goal tile: the goal's summary ([goalSummary]) from the
/// profile's [targetKg] and [pace] and the goal kept ([TrendsOverview.goal]).
class GoalYouTile extends StatefulWidget {
  final String title;
  final BodyWeightUnit unit;
  final double? targetKg;
  final ({UserWeightGoalEntity goal, double? kgPerWeek}) pace;

  /// The goal kept; [TrendsOverview.goal] by default.
  final Future<TrendsGoal> Function()? load;

  const GoalYouTile({
    super.key,
    required this.title,
    required this.unit,
    required this.targetKg,
    required this.pace,
    this.load,
  });

  @override
  State<GoalYouTile> createState() => _GoalYouTileState();
}

class _GoalYouTileState extends State<GoalYouTile> {
  TrendsGoal? _goal;

  @override
  void initState() {
    super.initState();
    PhaseStore.changes.addListener(_reload);
    paceChanges.addListener(_reload);
    _reload();
  }

  @override
  void didUpdateWidget(GoalYouTile old) {
    super.didUpdateWidget(old);
    // The kept start follows the target.
    if (old.targetKg != widget.targetKg || old.pace != widget.pace) _reload();
  }

  @override
  void dispose() {
    PhaseStore.changes.removeListener(_reload);
    paceChanges.removeListener(_reload);
    super.dispose();
  }

  Future<void> _reload() async {
    final TrendsGoal goal;
    try {
      goal = await (widget.load ?? TrendsOverview.goal)();
    } catch (_) {
      // No store in a test: the profile's own goal shows.
      return;
    }
    if (mounted) setState(() => _goal = goal);
  }

  @override
  Widget build(BuildContext context) {
    final goal = _goal;
    final summary = goalSummary(
      locale: Localizations.localeOf(context).toLanguageTag(),
      unit: widget.unit,
      unitLabel: weightUnitLabel(context, widget.unit),
      today: DateTime.now(),
      plan: goal?.plan,
      history: goal?.history ?? const [],
      pace: widget.pace,
      targetKg: widget.targetKg,
      nowKg: goal?.nowKg,
      progress: goal?.progress,
      kgPerDay: kgPerDay30(goal?.progress),
    );
    return goalSummaryTile(
      context,
      summary,
      id: 'profile-goal-tile',
      label: widget.title,
      unit: widget.unit,
    );
  }
}
