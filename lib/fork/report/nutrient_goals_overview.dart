import 'package:flutter/material.dart';
import 'package:opennutritracker/core/data/repository/tracked_day_repository.dart';
import 'package:opennutritracker/core/domain/entity/tracked_day_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_entity.dart';
import 'package:opennutritracker/core/presentation/widgets/app_card.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/fork/copy/copy_ui.dart';
import 'package:opennutritracker/fork/report/nutrient_explorer.dart';

/// The tracked days from the first to the last.
typedef TrackedDayLoader =
    Future<List<TrackedDayEntity>> Function(DateTime first, DateTime last);

Future<List<TrackedDayEntity>> _trackedDays(DateTime first, DateTime last) =>
    locator<TrackedDayRepository>().getTrackedDayByRange(first, last);

/// How a nutrient stands against its goal.
enum GoalStanding {
  /// A target: green, however far along.
  toReach,

  /// A limit not passed: grey.
  under,

  /// A limit passed: red.
  over,
}

GoalStanding standingOf(NutrientSummary s) => !s.nutrient.isLimit
    ? GoalStanding.toReach
    : s.perDay > (s.goal ?? double.infinity)
    ? GoalStanding.over
    : GoalStanding.under;

/// The nutrients with a goal of their own (not energy or the macros), the
/// ones to reach first, then the limits.
List<NutrientSummary> goalRows(List<NutrientSummary> all) => [
  for (final s in all)
    if (s.nutrient.marksMiss && !s.nutrient.isLimit) s,
  for (final s in all)
    if (s.nutrient.marksMiss && s.nutrient.isLimit) s,
];

String _number(double value) =>
    value < 10 ? value.toStringAsFixed(1) : '${value.round()}';

/// Seam S135: Nutrient goals as MacroFactor's (PickNutr B), today's
/// nutrients or the last week's against their goals; Edit opens upstream's
/// list of goals.
class NutrientGoalsOverview extends StatefulWidget {
  final Future<DateTime> Function() today;
  final IntakeLoader load;
  final TrackedDayLoader days;
  final Future<UserEntity?> Function() user;
  final Future<int> Function() dayStart;

  /// Opens the goal list; the bars are read again when it closes.
  final Future<void> Function(BuildContext context) onEdit;

  const NutrientGoalsOverview({
    super.key,
    required this.onEdit,
    this.today = logicalToday,
    this.load = intakesBetween,
    this.days = _trackedDays,
    this.user = loadUser,
    this.dayStart = dayStartMinutes,
  });

  @override
  State<NutrientGoalsOverview> createState() => _NutrientGoalsOverviewState();
}

class _NutrientGoalsOverviewState extends State<NutrientGoalsOverview> {
  var _week = false;
  late Future<List<NutrientSummary>> _rows = _read();

  Future<List<NutrientSummary>> _read() async {
    final last = await widget.today();
    final first = _week ? DateTime(last.year, last.month, last.day - 6) : last;
    return goalRows(
      summarizeNutrients(
        await widget.load(first, last),
        await widget.days(first, last),
        await widget.user(),
        dayStartMinutes: await widget.dayStart(),
      ),
    );
  }

  void _show(bool week) => setState(() {
    _week = week;
    _rows = _read();
  });

  Future<void> _edit() async {
    await widget.onEdit(context);
    if (mounted) _show(_week);
  }

  @override
  Widget build(BuildContext context) {
    final palette = paletteOf(context);
    final text = Theme.of(context).textTheme;
    Widget chip(String label, bool week) => Semantics(
      identifier: 'nutrient-goals-${week ? 'week' : 'today'}',
      child: ChoiceChip(
        label: Text(label),
        selected: _week == week,
        onSelected: (_) => _show(week),
      ),
    );
    return Scaffold(
      backgroundColor: palette.canvas,
      appBar: AppBar(
        backgroundColor: palette.canvas,
        title: const Text('Nutrient goals'),
        actions: [
          Semantics(
            identifier: 'nutrient-goals-edit',
            child: TextButton.icon(
              onPressed: _edit,
              icon: const Icon(Icons.edit_rounded, size: 18),
              label: const Text('Edit'),
            ),
          ),
          const SizedBox(width: Dimens.spacing4),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          Dimens.spacing12,
          0,
          Dimens.spacing12,
          Dimens.spacing32 + MediaQuery.paddingOf(context).bottom,
        ),
        children: [
          Wrap(
            spacing: Dimens.spacing8,
            children: [chip('Today', false), chip('7-day average', true)],
          ),
          const SizedBox(height: Dimens.spacing8),
          FutureBuilder<List<NutrientSummary>>(
            future: _rows,
            builder: (context, snapshot) {
              final rows = snapshot.data;
              if (rows == null) {
                return const Padding(
                  padding: EdgeInsets.all(Dimens.spacing24),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              return AppCard(
                padding: const EdgeInsets.symmetric(
                  horizontal: Dimens.spacing12,
                  vertical: Dimens.spacing4,
                ),
                child: Column(children: [for (final s in rows) _GoalBar(s)]),
              );
            },
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Dimens.spacing4,
              Dimens.spacing8,
              Dimens.spacing4,
              0,
            ),
            child: Text(
              [
                'Green: reach it. Grey: stay under. Red: over a limit.',
                if (_week) 'The average is over the days with food logged.',
              ].join(' '),
              style: text.bodySmall?.copyWith(color: palette.textMuted),
            ),
          ),
        ],
      ),
    );
  }
}

class _GoalBar extends StatelessWidget {
  final NutrientSummary summary;

  const _GoalBar(this.summary);

  @override
  Widget build(BuildContext context) {
    final palette = paletteOf(context);
    final text = Theme.of(context).textTheme;
    final s = summary;
    final unit = s.nutrient.unit;
    final goal = s.goal;
    final standing = standingOf(s);
    final color = switch (standing) {
      GoalStanding.toReach => palette.accent,
      GoalStanding.under => palette.textMuted,
      GoalStanding.over => Theme.of(context).colorScheme.error,
    };
    final share = goal == null || goal == 0 ? 0.0 : s.perDay / goal;
    final of = goal == null ? '' : ' of ${_number(goal)} $unit';
    final says = switch (standing) {
      GoalStanding.toReach when share >= 1 => ', reached',
      GoalStanding.over => ', over the limit',
      _ => '',
    };
    return Semantics(
      identifier: 'nutrient-goal-${s.nutrient.label}',
      label: '${s.nutrient.label}, ${_number(s.perDay)}$of$says',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Dimens.spacing8),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(child: Text(s.nutrient.label, style: text.bodyLarge)),
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: _number(s.perDay),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      TextSpan(
                        text: goal == null
                            ? ' $unit'
                            : ' / ${_number(goal)} $unit',
                        style: text.bodySmall?.copyWith(
                          color: palette.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: Dimens.spacing4),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: share.clamp(0.0, 1.0),
                minHeight: 7,
                color: color,
                backgroundColor: palette.surfaceMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
