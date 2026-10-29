import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;
import 'package:opennutritracker/core/domain/entity/body_weight_unit_entity.dart';
import 'package:opennutritracker/core/presentation/widgets/app_card.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/hive_db_provider.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/fork/goal/goal_progress_page.dart';
import 'package:opennutritracker/fork/goal/goal_you_tile.dart' show noGoalText;
import 'package:opennutritracker/fork/goal/phase_colors.dart';
import 'package:opennutritracker/fork/goal/planner_screen.dart';
import 'package:opennutritracker/fork/phases/phases.dart';
import 'package:opennutritracker/fork/units/weight_text.dart';

/// Trends' goal card: the goal planned and its phases, Goal progress, and
/// the planner; in place of the pace slider and the phase list, which the
/// planner's steps now hold.
class GoalCard extends StatefulWidget {
  final BodyWeightUnit unit;
  final Future<PhasePlan?> Function()? load;

  const GoalCard({super.key, required this.unit, this.load});

  @override
  State<GoalCard> createState() => _GoalCardState();
}

class _GoalCardState extends State<GoalCard> {
  late Future<PhasePlan?> _plan = _read();

  Future<PhasePlan?> _read() async {
    try {
      return await (widget.load ?? () => PhaseStore().plan())();
    } catch (_) {
      // No store in a test: no plan.
      return null;
    }
  }

  void _reload() {
    if (mounted) setState(() => _plan = _read());
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FutureBuilder(
      future: _plan,
      builder: (context, snapshot) {
        final plan = snapshot.data;
        final target = plan?.targetKg;
        final today = DateTime.now();
        final index = plan?.indexOn(today);
        final now = plan == null || index! < 0
            ? null
            : index < plan.phases.length
            ? phaseName(
                plan.phases[index].kind,
                inCut: plan.kind == PhaseKind.cut,
              )
            : 'Maintenance';
        final format = intl.DateFormat.yMMMd(
          Localizations.localeOf(context).toLanguageTag(),
        );
        return AppCard(
          padding: const EdgeInsets.all(Dimens.spacing16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Goal', style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                plan == null
                    ? '$noGoalText. Plan a cut, maintenance or a bulk: '
                          'its pace, what you burn, the calorie target and '
                          'macros, step by step.'
                    : '${plan.kind.label}'
                          '${target == null ? '' : ' to ${weightText(target, widget.unit)}'}'
                          ', until ${format.format(plan.end)}'
                          '${now == null ? '' : ' · now: ${now.toLowerCase()}'}',
              ),
              if (plan != null) ...[
                const SizedBox(height: Dimens.spacing12),
                PhaseBar(plan),
              ],
              const SizedBox(height: Dimens.spacing12),
              Wrap(
                spacing: Dimens.spacing8,
                children: [
                  if (plan != null)
                    Semantics(
                      identifier: 'trends-goal-open',
                      child: FilledButton.tonal(
                        onPressed: () => openGoalProgress(context, widget.unit),
                        child: const Text('Goal and plan'),
                      ),
                    ),
                  Semantics(
                    identifier: 'trends-goal-plan',
                    child: plan == null
                        ? FilledButton(
                            onPressed: () async {
                              if (await openGoalPlanner(context)) _reload();
                            },
                            child: const Text('Plan a goal'),
                          )
                        : TextButton(
                            onPressed: () async {
                              if (await openGoalPlanner(context)) _reload();
                            },
                            child: const Text('Edit plan'),
                          ),
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
