import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;
import 'package:opennutritracker/core/domain/entity/body_weight_unit_entity.dart';
import 'package:opennutritracker/core/presentation/widgets/app_card.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/fork/goal/completed_goals_page.dart';
import 'package:opennutritracker/fork/goal/goal_planner.dart';
import 'package:opennutritracker/fork/goal/goal_reached.dart';
import 'package:opennutritracker/fork/goal/phase_colors.dart';
import 'package:opennutritracker/fork/goal/planner_screen.dart';
import 'package:opennutritracker/fork/phases/phase_report.dart';
import 'package:opennutritracker/fork/phases/phases.dart';
import 'package:opennutritracker/fork/units/weight_text.dart';

DateTime _date(DateTime t) => DateTime(t.year, t.month, t.day);

/// Goal progress's plan (round 4, calendar B): whether the goal is reached
/// or over, the whole plan a square a day beside the goals before it, this
/// week, the phases, and the planner; the completed goals below.
class GoalPlanSection extends StatelessWidget {
  final PhasePlan? plan;
  final List<GoalRecord> history;

  /// The trend now; null before the first weigh-in.
  final double? nowKg;
  final BodyWeightUnit unit;
  final DateTime today;

  /// After the plan changed here.
  final VoidCallback onChanged;

  const GoalPlanSection({
    super.key,
    required this.plan,
    required this.history,
    required this.nowKg,
    required this.unit,
    required this.today,
    required this.onChanged,
  });

  String _day(BuildContext context, DateTime d) {
    final locale = Localizations.localeOf(context).toLanguageTag();
    return (d.year == today.year
            ? intl.DateFormat.MMMd(locale)
            : intl.DateFormat.yMMMd(locale))
        .format(d);
  }

  Future<void> _plan(BuildContext context, {required bool fresh}) async {
    if (await openGoalPlanner(context, fresh: fresh)) onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final plan = this.plan;
    const gap = SizedBox(height: Dimens.spacing12);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (plan == null) ...[
          AppCard(
            padding: const EdgeInsets.all(Dimens.spacing16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'No goal planned',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                const Text(
                  'Plan a cut, maintenance or a bulk: its pace, what you '
                  'burn, the calorie target and macros, step by step.',
                ),
                const SizedBox(height: Dimens.spacing12),
                Semantics(
                  identifier: 'goal-plan-new',
                  child: FilledButton(
                    onPressed: () => _plan(context, fresh: true),
                    child: const Text('Plan a goal'),
                  ),
                ),
              ],
            ),
          ),
        ] else ...[
          if (nowKg != null)
            _StatusBanner(plan, nowKg!, unit, today, onChanged),
          AppCard(
            padding: const EdgeInsets.all(Dimens.spacing16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Whole plan',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: Dimens.spacing8),
                PlanGrid(plan: plan, history: history, today: today),
                const SizedBox(height: Dimens.spacing8),
                const PhaseLegend(),
                const SizedBox(height: 6),
                Text(
                  'A square a day; today is outlined.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          gap,
          _ThisWeek(plan: plan, history: history, today: today, day: _day),
          gap,
          AppCard(
            padding: const EdgeInsets.symmetric(vertical: Dimens.spacing4),
            child: Column(
              children: [
                for (final (i, p) in plan.phases.indexed)
                  _phaseRow(context, plan, i, p),
                if (plan.indexOn(today) >= 0) ...[
                  const Divider(height: 1),
                  Semantics(
                    identifier: 'goal-phase-reports',
                    child: ListTile(
                      title: const Text('Phase reports'),
                      subtitle: const Text(
                        'Each phase begun: its change and pace against the '
                        'plan, what you ate and burned',
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => openPhaseReports(
                        context,
                        plan,
                        today: today,
                        unit: unit,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          gap,
          Row(
            children: [
              Expanded(
                child: Semantics(
                  identifier: 'goal-plan-edit',
                  child: OutlinedButton(
                    onPressed: () => _plan(context, fresh: false),
                    child: const Text('Edit plan'),
                  ),
                ),
              ),
              const SizedBox(width: Dimens.spacing8),
              Expanded(
                child: Semantics(
                  identifier: 'goal-plan-new',
                  child: OutlinedButton(
                    onPressed: () => _plan(context, fresh: true),
                    child: const Text('Plan a new goal'),
                  ),
                ),
              ),
            ],
          ),
        ],
        gap,
        AppCard(
          child: Semantics(
            identifier: 'goal-completed-list',
            child: ListTile(
              title: const Text('Completed goals'),
              subtitle: Text(
                history.isEmpty
                    ? 'None yet'
                    : '${history.length} · the last a '
                          '${history.last.kind.label.toLowerCase()}'
                          '${history.last.endKg == null ? '' : ' to ${weightText(history.last.endKg!, unit)}'}',
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => CompletedGoalsPage(unit: unit),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _phaseRow(BuildContext context, PhasePlan plan, int i, DietPhase p) {
    final first = plan.startOf(i);
    final last = plan.startOf(i + 1).subtract(const Duration(hours: 12));
    final now = plan.indexOn(today) == i;
    final until = p.untilKg;
    return ListTile(
      leading: _Square(color: phaseColor(context, p.kind)),
      title: Text(
        '${phaseName(p.kind, inCut: plan.kind == PhaseKind.cut)}'
        '${until == null ? '' : ' to ${weightText(until, unit)}'}',
      ),
      subtitle: Text(
        '${_day(context, first)} – ${until == null ? '' : 'about '}'
        '${_day(context, last)}',
      ),
      trailing: now
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'Now',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSecondaryContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
            )
          : null,
    );
  }
}

class _Square extends StatelessWidget {
  final Color color;

  const _Square({required this.color});

  @override
  Widget build(BuildContext context) => Container(
    width: 16,
    height: 16,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(4),
    ),
  );
}

/// Reached, or over without: a card to complete or extend the goal.
class _StatusBanner extends StatelessWidget {
  final PhasePlan plan;
  final double nowKg;
  final BodyWeightUnit unit;
  final DateTime today;
  final VoidCallback onChanged;

  const _StatusBanner(
    this.plan,
    this.nowKg,
    this.unit,
    this.today,
    this.onChanged,
  );

  @override
  Widget build(BuildContext context) {
    final status = goalStatus(plan, nowKg, today);
    if (status == GoalStatus.running) return const SizedBox.shrink();
    final reached = status == GoalStatus.reached;
    final target = plan.targetKg;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: Dimens.spacing12),
      child: AppCard(
        color: scheme.secondaryContainer,
        padding: const EdgeInsets.all(Dimens.spacing16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              reached
                  ? 'You reached ${weightText(target!, unit)}'
                  : 'The plan has ended',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: scheme.onSecondaryContainer,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              reached
                  ? 'Mark the goal completed, or extend it.'
                  : target == null
                  ? 'Mark it completed, or extend it.'
                  : 'You are at ${weightText(nowKg, unit)}, '
                        '${weightText((target - nowKg).abs(), unit)} from the '
                        'target. Extend the goal, or mark it completed.',
              style: TextStyle(color: scheme.onSecondaryContainer),
            ),
            const SizedBox(height: Dimens.spacing12),
            Semantics(
              identifier: 'goal-status-open',
              child: FilledButton(
                onPressed: () async {
                  final changed = reached
                      ? await openGoalReached(context, plan, nowKg, unit)
                      : await showExtendSheet(
                          context,
                          plan,
                          nowKg,
                          unit,
                          ended: true,
                        );
                  if (changed) onChanged();
                },
                child: Text(reached ? 'See how it went' : 'Extend or complete'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The weeks around the plan, a square a day (Monday at the top), in each
/// day's goal colour; days no goal covers are left blank.
class PlanGrid extends StatelessWidget {
  final PhasePlan plan;
  final List<GoalRecord> history;
  final DateTime today;

  const PlanGrid({
    super.key,
    required this.plan,
    required this.history,
    required this.today,
  });

  /// The Monday the grid starts on: up to 26 weeks before the plan, as far
  /// back as the goals before it go.
  DateTime get first {
    final start = _date(plan.start);
    var from = DateTime(start.year, start.month, start.day - 7 * 4);
    final earliest = history.isEmpty ? null : _date(history.first.start);
    final limit = DateTime(start.year, start.month, start.day - 7 * 26);
    if (earliest != null && earliest.isBefore(from)) {
      from = earliest.isBefore(limit) ? limit : earliest;
    }
    return DateTime(from.year, from.month, from.day - (from.weekday - 1));
  }

  int get weeks {
    final end = _date(plan.end);
    final after = DateTime(end.year, end.month, end.day + 14);
    final t = _date(today);
    final last = after.isAfter(t)
        ? after
        : DateTime(t.year, t.month, t.day + 14);
    final span =
        (DateTime.utc(last.year, last.month, last.day)
                    .difference(
                      DateTime.utc(first.year, first.month, first.day),
                    )
                    .inDays /
                7)
            .ceil();
    return span.clamp(4, 60);
  }

  @override
  Widget build(BuildContext context) {
    final from = first;
    final count = weeks;
    final kinds = [
      for (var d = 0; d < count * 7; d++)
        kindOn(DateTime(from.year, from.month, from.day + d), plan, history),
    ];
    final colors = {
      for (final k in PhaseKind.values) k: phaseColor(context, k),
    };
    final locale = Localizations.localeOf(context).toLanguageTag();
    return Semantics(
      label: _summary(context),
      child: ExcludeSemantics(
        child: LayoutBuilder(
          builder: (context, box) {
            final cell = math.min(14.0, box.maxWidth / count);
            return CustomPaint(
              size: Size(cell * count, 16 + cell * 7),
              painter: _GridPainter(
                from: from,
                weeks: count,
                kinds: kinds,
                colors: colors,
                none: Theme.of(context).colorScheme.outlineVariant,
                todayIndex: DateTime.utc(today.year, today.month, today.day)
                    .difference(DateTime.utc(from.year, from.month, from.day))
                    .inDays,
                ring: Theme.of(context).colorScheme.onSurface,
                label: Theme.of(context).textTheme.labelSmall!.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                month: (d) => intl.DateFormat.MMM(locale).format(d),
                cell: cell,
              ),
            );
          },
        ),
      ),
    );
  }

  String _summary(BuildContext context) {
    final locale = Localizations.localeOf(context).toLanguageTag();
    final format = intl.DateFormat.yMMMd(locale);
    final inCut = plan.kind == PhaseKind.cut;
    return [
      for (final r in history.reversed.take(2).toList().reversed)
        '${r.kind.label} ${format.format(r.start)} to ${format.format(r.end)}',
      for (final (i, p) in plan.phases.indexed)
        '${phaseName(p.kind, inCut: inCut)} from ${format.format(plan.startOf(i))}',
      'maintenance from ${format.format(plan.end)}',
    ].join('; ');
  }
}

class _GridPainter extends CustomPainter {
  final DateTime from;
  final int weeks;
  final List<PhaseKind?> kinds;
  final Map<PhaseKind, Color> colors;
  final Color none;
  final int todayIndex;
  final Color ring;
  final TextStyle label;
  final String Function(DateTime) month;
  final double cell;

  _GridPainter({
    required this.from,
    required this.weeks,
    required this.kinds,
    required this.colors,
    required this.none,
    required this.todayIndex,
    required this.ring,
    required this.label,
    required this.month,
    required this.cell,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const top = 16.0;
    final gap = cell > 8 ? 2.0 : 1.0;
    final paint = Paint();
    var lastMonth = -1;
    var lastLabelX = -100.0;
    for (var w = 0; w < weeks; w++) {
      final monday = DateTime(from.year, from.month, from.day + w * 7);
      // A month is named over its first whole week.
      final firstOfMonth = DateTime(monday.year, monday.month, 1);
      final x = w * cell;
      if (monday.month != lastMonth && monday.day <= 7 ||
          (w == 0 && monday.day <= 21)) {
        if (x - lastLabelX > 28) {
          final text = TextPainter(
            text: TextSpan(text: month(firstOfMonth), style: label),
            textDirection: TextDirection.ltr,
          )..layout();
          text.paint(canvas, Offset(x, 0));
          lastLabelX = x;
        }
        lastMonth = monday.month;
      }
      for (var d = 0; d < 7; d++) {
        final i = w * 7 + d;
        final kind = kinds[i];
        final rect = RRect.fromRectAndRadius(
          Rect.fromLTWH(x, top + d * cell, cell - gap, cell - gap),
          Radius.circular(cell / 5),
        );
        // A day no goal covers is an outline, apart from maintenance.
        if (kind == null) {
          canvas.drawRRect(
            rect.deflate(0.5),
            Paint()
              ..color = none
              ..style = PaintingStyle.stroke,
          );
        } else {
          canvas.drawRRect(rect, paint..color = colors[kind]!);
        }
        if (i == todayIndex) {
          canvas.drawRRect(
            rect.inflate(0.5),
            Paint()
              ..color = ring
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.6,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) =>
      old.kinds != kinds || old.todayIndex != todayIndex || old.cell != cell;
}

/// This week's days in their colours, and when the next phase begins.
class _ThisWeek extends StatelessWidget {
  final PhasePlan plan;
  final List<GoalRecord> history;
  final DateTime today;
  final String Function(BuildContext, DateTime) day;

  const _ThisWeek({
    required this.plan,
    required this.history,
    required this.today,
    required this.day,
  });

  @override
  Widget build(BuildContext context) {
    final t = _date(today);
    final monday = DateTime(t.year, t.month, t.day - (t.weekday - 1));
    final days = [
      for (var i = 0; i < 7; i++)
        DateTime(monday.year, monday.month, monday.day + i),
    ];
    final locale = Localizations.localeOf(context).toLanguageTag();
    final weekday = intl.DateFormat.E(locale);
    final inCut = plan.kind == PhaseKind.cut;
    final index = plan.indexOn(t);
    final next = index + 1;
    final nextText = index < 0
        ? 'The plan starts ${day(context, plan.start)}.'
        : next < plan.phases.length
        ? 'Next: ${phaseName(plan.phases[next].kind, inCut: inCut).toLowerCase()} '
              'from ${day(context, plan.startOf(next))}.'
        : next == plan.phases.length
        ? 'Maintenance from ${day(context, plan.end)}, after the last phase.'
        : 'The plan\'s phases are over: maintenance.';
    final theme = Theme.of(context);
    return AppCard(
      padding: const EdgeInsets.all(Dimens.spacing16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('This week', style: theme.textTheme.titleMedium),
              ),
              Text(
                '${day(context, days.first)} – ${day(context, days.last)}',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
          const SizedBox(height: Dimens.spacing8),
          Row(
            children: [
              for (final d in days)
                Expanded(
                  child: Builder(
                    builder: (context) {
                      final kind = kindOn(d, plan, history);
                      final isToday = d == t;
                      return Semantics(
                        label:
                            '${weekday.format(d)} ${d.day}: '
                            '${kind == null ? 'no goal' : phaseName(kind, inCut: inCut)}'
                            '${isToday ? ', today' : ''}',
                        child: ExcludeSemantics(
                          child: Column(
                            children: [
                              Text(
                                weekday.format(d),
                                style: theme.textTheme.labelSmall,
                              ),
                              Text(
                                '${d.day}',
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: isToday
                                      ? FontWeight.w800
                                      : FontWeight.w500,
                                  decoration: isToday
                                      ? TextDecoration.underline
                                      : null,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Container(
                                height: 6,
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: kind == null
                                      ? null
                                      : phaseColor(context, kind),
                                  border: kind == null
                                      ? Border.all(
                                          color:
                                              theme.colorScheme.outlineVariant,
                                        )
                                      : null,
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
          const SizedBox(height: Dimens.spacing8),
          Text(nextText, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}
