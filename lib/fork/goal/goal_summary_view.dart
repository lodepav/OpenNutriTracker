import 'package:flutter/material.dart';
import 'package:opennutritracker/core/domain/entity/body_weight_unit_entity.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/fork/display/contrast.dart';
import 'package:opennutritracker/fork/goal/goal_progress_page.dart';
import 'package:opennutritracker/fork/goal/goal_reached.dart';
import 'package:opennutritracker/fork/goal/goal_summary.dart';
import 'package:opennutritracker/fork/goal/phase_colors.dart';
import 'package:opennutritracker/fork/goal/planner_screen.dart';
import 'package:opennutritracker/fork/trends/trends_widgets.dart';

/// Goes where [summary] taps to.
Future<void> openGoalSummary(
  BuildContext context,
  GoalSummary summary,
  BodyWeightUnit unit,
) async {
  final plan = summary.plan;
  final now = summary.nowKg;
  switch (summary.tap) {
    case GoalTap.planner:
      await openGoalPlanner(context);
    case GoalTap.reached when plan != null && now != null:
      await openGoalReached(context, plan, now, unit);
    case GoalTap.extend when plan != null && now != null:
      await showExtendSheet(context, plan, now, unit, ended: true);
    case GoalTap.progress || GoalTap.reached || GoalTap.extend:
      openGoalProgress(context, unit);
  }
}

/// A half tile of [summary]: its value and suffix, then [GoalSummaryBelow].
TrendTile goalSummaryTile(
  BuildContext context,
  GoalSummary summary, {
  required String id,
  required BodyWeightUnit unit,
  String label = 'Goal',
}) => TrendTile(
  id: id,
  label: label,
  value: summary.value,
  suffix: summary.suffix,
  spokenLabel: summary.spoken(label),
  hint: summary.tileAction?.label,
  chart: GoalSummaryBelow(summary),
  onTap: () => openGoalSummary(context, summary, unit),
);

/// Under a goal tile's value: the note, the bar or the phase bar, and the
/// action in the accent. Not read out: the tile's label says it.
class GoalSummaryBelow extends StatelessWidget {
  final GoalSummary summary;

  const GoalSummaryBelow(this.summary, {super.key});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final note = summary.note;
    final action = summary.tileAction;
    final bar = GoalSummaryBar(summary, height: 8);
    return ExcludeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (note != null)
            Text(
              note,
              style: text.bodySmall?.copyWith(
                color: paletteOf(context).textMuted,
              ),
            ),
          if (summary.bar != null || summary.phases) ...[
            const SizedBox(height: 6),
            bar,
          ],
          if (action != null) ...[
            const SizedBox(height: 4),
            Text(
              action.label,
              style: text.labelMedium?.copyWith(
                color: textAccent(context),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// [summary]'s bar, [height] high: how far along in the accent, or the
/// plan's phases in their colours; nothing without either.
class GoalSummaryBar extends StatelessWidget {
  final GoalSummary summary;
  final double height;

  const GoalSummaryBar(this.summary, {super.key, required this.height});

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(height / 2);
    final plan = summary.plan;
    final fraction = summary.bar;
    if (summary.phases && plan != null) {
      return ClipRRect(
        borderRadius: radius,
        child: SizedBox(
          height: height,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (i, p) in plan.phases.indexed) ...[
                if (i > 0) const SizedBox(width: 2),
                Expanded(
                  flex: p.weeks,
                  child: ColoredBox(color: phaseColor(context, p.kind)),
                ),
              ],
            ],
          ),
        ),
      );
    }
    if (fraction == null) return const SizedBox.shrink();
    return ClipRRect(
      borderRadius: radius,
      child: LinearProgressIndicator(
        value: fraction,
        minHeight: height,
        color: chartAccent(context),
        backgroundColor: paletteOf(context).surfaceMuted,
      ),
    );
  }
}
