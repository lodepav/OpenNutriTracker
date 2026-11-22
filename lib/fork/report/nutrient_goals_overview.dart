import 'package:flutter/material.dart';
import 'package:opennutritracker/core/data/repository/tracked_day_repository.dart';
import 'package:opennutritracker/core/domain/entity/tracked_day_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_entity.dart';
import 'package:opennutritracker/core/presentation/widgets/app_card.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/fork/copy/copy_ui.dart';
import 'package:opennutritracker/fork/report/goal_standing.dart';
import 'package:opennutritracker/fork/report/nutrient_explorer.dart';
import 'package:opennutritracker/fork/report/nutrient_order.dart';
import 'package:opennutritracker/fork/units/amount_text.dart' show spokenUnit;

/// The tracked days from the first to the last.
typedef TrackedDayLoader =
    Future<List<TrackedDayEntity>> Function(DateTime first, DateTime last);

Future<List<TrackedDayEntity>> _trackedDays(DateTime first, DateTime last) =>
    locator<TrackedDayRepository>().getTrackedDayByRange(first, last);

/// The nutrients with a goal of their own (not energy or the macros), in
/// [nutrientOrder], as the editor and the Nutrients list show them.
List<NutrientSummary> goalRows(List<NutrientSummary> all) => [
  for (var rank = 0; rank <= nutrientOrder.length; rank++)
    for (final s in all)
      if (s.nutrient.marksMiss && nutrientRank(s.nutrient) == rank) s,
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
  final Future<List<TrackedDayEntity>?> Function() goalHistory;

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
    this.goalHistory = allTrackedDays,
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
        await widget.days(first, endOfDay(last)),
        await widget.user(),
        dayStartMinutes: await widget.dayStart(),
        // Today keeps to its own row, as the Diary's panel does.
        goalHistory: _week ? await widget.goalHistory() : null,
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
          // the gutter every other page has
          Dimens.spacing16,
          0,
          Dimens.spacing16,
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
                goalStandingKey,
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
    final standing = goalStanding(
      isLimit: s.nutrient.isLimit,
      perDay: s.perDay,
      goal: goal,
      isBand: s.nutrient.isBand,
    );
    final color = goalStandingColor(
      standing,
      palette,
      Theme.of(context).colorScheme,
    );
    final share = goal == null || goal == 0 ? 0.0 : s.perDay / goal;
    final of = goal == null ? '' : ' of ${_number(goal)}';
    final word = goalStandingWord(
      standing,
      isLimit: s.nutrient.isLimit,
      isBand: s.nutrient.isBand,
    );
    final says = word == null ? '' : ', $word';
    return Semantics(
      identifier: 'nutrient-goal-${s.nutrient.label}',
      label:
          '${goalRowLabel(s.nutrient)}, ${_number(s.perDay)}$of '
          '${spokenUnit(unit)}$says',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Dimens.spacing8),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: goalRowLabel(s.nutrient)),
                        if (word != null)
                          TextSpan(
                            text: ' · $word',
                            style: text.bodySmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                      ],
                    ),
                    style: text.bodyLarge,
                  ),
                ),
                // Keeps a wrapped label off the number at large text.
                const SizedBox(width: Dimens.spacing8),
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
