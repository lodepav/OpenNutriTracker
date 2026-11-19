import 'package:flutter/material.dart';
import 'package:opennutritracker/core/domain/entity/body_weight_unit_entity.dart';
import 'package:opennutritracker/core/presentation/widgets/app_card.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/hive_db_provider.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/fork/goal/completed_goals_page.dart';
import 'package:opennutritracker/fork/goal/goal_progress_page.dart';
import 'package:opennutritracker/fork/goal/goal_summary.dart';
import 'package:opennutritracker/fork/goal/goal_summary_view.dart';
import 'package:opennutritracker/fork/goal/planner_screen.dart';
import 'package:opennutritracker/fork/phases/phases.dart';
import 'package:opennutritracker/fork/trends/card_title.dart';
import 'package:opennutritracker/fork/trends/trend_detail.dart'
    show weightUnitLabel;
import 'package:opennutritracker/fork/trends/trends_overview.dart'
    show TrendsGoal, TrendsOverview;
import 'package:opennutritracker/fork/units/weight_text.dart';

/// Trends' goal card: the goal's summary ([goalSummary]) larger, the start
/// and target under its bar, then Goal progress, the planner, or what to
/// do once the goal is reached or over.
class GoalCard extends StatefulWidget {
  final BodyWeightUnit unit;

  /// The goal kept; [TrendsOverview.goal] by default.
  final Future<TrendsGoal> Function()? load;

  const GoalCard({super.key, required this.unit, this.load});

  @override
  State<GoalCard> createState() => _GoalCardState();
}

class _GoalCardState extends State<GoalCard> {
  late Future<TrendsGoal> _goal = _read();

  Future<TrendsGoal> _read() => (widget.load ?? TrendsOverview.goal)();

  void _reload() {
    if (mounted) {
      setState(() {
        _goal = _read();
      });
    }
  }

  @override
  void initState() {
    super.initState();
    PhaseStore.changes.addListener(_reload);
    if (locator.isRegistered<HiveDBProvider>()) {
      locator<HiveDBProvider>().addListener(_reload);
    }
  }

  @override
  void dispose() {
    PhaseStore.changes.removeListener(_reload);
    if (locator.isRegistered<HiveDBProvider>()) {
      locator<HiveDBProvider>().removeListener(_reload);
    }
    super.dispose();
  }

  Future<void> _plan() async {
    if (await openGoalPlanner(context)) _reload();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = paletteOf(context);
    final unit = widget.unit;
    return FutureBuilder(
      future: _goal,
      builder: (context, snapshot) {
        final goal = snapshot.data;
        final locale = Localizations.localeOf(context).toLanguageTag();
        final today = DateTime.now();
        final summary = goalSummary(
          locale: locale,
          unit: unit,
          unitLabel: weightUnitLabel(context, unit),
          today: today,
          plan: goal?.plan,
          history: goal?.history ?? const [],
          pace: goal?.pace,
          targetKg: goal?.progress?.targetKg,
          nowKg: goal?.nowKg,
          progress: goal?.progress,
          kgPerDay: kgPerDay30(goal?.progress),
        );
        final plan = summary.plan;
        final start = summary.start;
        final target = summary.targetKg;
        final muted = theme.textTheme.bodySmall?.copyWith(
          color: palette.textMuted,
        );
        return AppCard(
          padding: const EdgeInsets.all(Dimens.spacing20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CardTitle(
                child: Text('Goal', style: theme.textTheme.titleMedium),
              ),
              const SizedBox(height: 4),
              Semantics(
                label: summary.spoken(),
                excludeSemantics: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.rich(
                      TextSpan(
                        text: summary.value,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                        children: [
                          if (summary.suffix != null)
                            TextSpan(
                              text: ' ${summary.suffix}',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: palette.textMuted,
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (summary.note != null)
                      Text(
                        summary.note!,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: palette.textMuted,
                        ),
                      ),
                    if (summary.bar != null || summary.phases) ...[
                      const SizedBox(height: Dimens.spacing12),
                      GoalSummaryBar(summary, height: 12),
                    ],
                    if (summary.bar != null && start != null && target != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${weightText(start.kg, unit)} '
                                '${goalDay(locale, today, start.day)}',
                                style: muted,
                              ),
                            ),
                            Text(weightText(target, unit), style: muted),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: Dimens.spacing12),
              Wrap(
                spacing: Dimens.spacing8,
                children: [
                  if (summary.action == GoalAction.completeOrExtend)
                    Semantics(
                      identifier: 'trends-goal-open',
                      child: FilledButton(
                        onPressed: () =>
                            openGoalSummary(context, summary, unit),
                        child: Text(summary.action!.label),
                      ),
                    )
                  else if (plan != null)
                    Semantics(
                      identifier: 'trends-goal-open',
                      child: FilledButton(
                        onPressed: () => openGoalProgress(context, unit),
                        child: const Text('Goal and plan'),
                      ),
                    )
                  else
                    Semantics(
                      identifier: 'trends-goal-plan',
                      child: FilledButton(
                        onPressed: _plan,
                        child: const Text('Plan a goal'),
                      ),
                    ),
                  if (plan != null)
                    Semantics(
                      identifier: 'trends-goal-plan',
                      child: TextButton(
                        onPressed: _plan,
                        child: const Text('Edit plan'),
                      ),
                    )
                  else if (summary.sinceGoal)
                    TextButton(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => CompletedGoalsPage(unit: unit),
                        ),
                      ),
                      child: const Text('Completed goals'),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
