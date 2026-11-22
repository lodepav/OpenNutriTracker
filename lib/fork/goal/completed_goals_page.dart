import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;
import 'package:opennutritracker/core/domain/entity/body_weight_unit_entity.dart';
import 'package:opennutritracker/core/presentation/widgets/app_card.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/calc/calendar_day_calc.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_service.dart';
import 'package:opennutritracker/fork/goal/goal_chart.dart';
import 'package:opennutritracker/fork/goal/goal_figure_grid.dart';
import 'package:opennutritracker/fork/goal/goal_status.dart';
import 'package:opennutritracker/fork/goal/phase_colors.dart';
import 'package:opennutritracker/fork/phases/phases.dart';
import 'package:opennutritracker/fork/trends/detail_widgets.dart';
import 'package:opennutritracker/fork/trends/trends_widgets.dart';
import 'package:opennutritracker/fork/units/weight_text.dart';

DateTime _date(DateTime t) => DateTime(t.year, t.month, t.day);

/// What Completed goals shows: the goals kept, the running one, and the
/// trend over them.
typedef GoalHistory = ({
  List<GoalRecord> history,
  PhasePlan? running,
  List<double> trend,
  DateTime today,
});

/// The time [history] took in all, counted as its rows count each goal
/// (a day at least): in days under a week, else in weeks.
({String label, String value}) timeInGoals(List<GoalRecord> history) {
  final days = history.fold(0, (s, r) {
    final d = CalendarDayCalc.daysBetween(r.start, r.end);
    return s + (d < 1 ? 1 : d);
  });
  return days < 7
      ? (label: 'Days in goals', value: '$days')
      : (label: 'Weeks in goals', value: '${(days / 7).round()}');
}

Future<GoalHistory> _loadHistory() async {
  final store = PhaseStore();
  final history = await store.history();
  final running = await store.plan();
  final today = _date(DateTime.now());
  final from = history.isEmpty ? running?.start ?? today : history.first.start;
  final days = CalendarDayCalc.daysBetween(_date(from), today) + 1;
  final inputs = await AdaptiveService.fromLocator().goalPlan(
    pastDays: days < 30 ? 30 : days,
  );
  return (
    history: history,
    running: running,
    trend: inputs?.pastTrendKg ?? const <double>[],
    today: today,
  );
}

/// Completed goals (round 4, B): the trend over each goal's colour, what
/// they add up to, and each goal from which day to which, from which
/// weight to which.
class CompletedGoalsPage extends StatefulWidget {
  final BodyWeightUnit unit;
  final Future<GoalHistory> Function()? load;

  const CompletedGoalsPage({super.key, required this.unit, this.load});

  @override
  State<CompletedGoalsPage> createState() => _CompletedGoalsPageState();
}

class _CompletedGoalsPageState extends State<CompletedGoalsPage> {
  late final Future<GoalHistory> _data = (widget.load ?? _loadHistory)();

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Completed goals')),
    body: FutureBuilder(
      future: _data,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: noData(context, 'Your goals could not be read.'),
          );
        }
        final data = snapshot.data;
        if (data == null) {
          return const Center(child: CircularProgressIndicator());
        }
        return ListView(
          padding: EdgeInsets.fromLTRB(
            Dimens.spacing16,
            Dimens.spacing8,
            Dimens.spacing16,
            Dimens.spacing32 + MediaQuery.paddingOf(context).bottom,
          ),
          children: data.history.isEmpty && data.running == null
              ? [
                  noData(
                    context,
                    'No goals yet. A goal you mark completed is kept here.',
                  ),
                ]
              : _body(context, data),
        );
      },
    ),
  );

  List<Widget> _body(BuildContext context, GoalHistory data) {
    final unit = widget.unit;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final format = intl.DateFormat.yMMMd(locale);
    final history = data.history;
    final running = data.running;
    final today = data.today;
    final dayOne =
        running != null &&
        CalendarDayCalc.daysBetween(running.start, today) < 1;
    final first = DateTime(
      today.year,
      today.month,
      today.day - data.trend.length + 1,
    );
    double sum(PhaseKind kind) => history
        .where((r) => r.kind == kind && r.startKg != null && r.endKg != null)
        .fold(0.0, (s, r) => s + (r.endKg! - r.startKg!));
    final time = timeInGoals(history);
    final lost = sum(PhaseKind.cut);
    final gained = sum(PhaseKind.bulk);
    final bands = <GoalBand>[
      for (final r in history) (start: r.start, end: r.end, kind: r.kind),
      if (running != null)
        for (final (i, p) in running.phases.indexed)
          (
            start: running.startOf(i),
            end: running.startOf(i + 1),
            kind: p.kind,
          ),
    ];
    final drawn = drawnKinds(bands, first, data.trend.length);
    return [
      if (data.trend.length >= 2)
        AppCard(
          padding: const EdgeInsets.all(Dimens.spacing16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GoalWeightChart(
                trend: data.trend,
                first: first,
                unit: unit,
                bands: bands,
                label:
                    'Trend from ${format.format(first)}, '
                    '${weightText(data.trend.first, unit)}, to '
                    '${weightText(data.trend.last, unit)} today',
              ),
              // Only the colours drawn, none for a chart with no band.
              if (drawn.isNotEmpty) ...[
                const SizedBox(height: Dimens.spacing8),
                PhaseLegend(kinds: drawn),
              ],
            ],
          ),
        ),
      const SizedBox(height: Dimens.spacing12),
      if (history.isEmpty)
        noData(
          context,
          'Goals you complete show here, with how long each took.',
        )
      else
        GoalFigureGrid(
          tiles: [
            FigureTile(label: 'Goals completed', value: '${history.length}'),
            FigureTile(
              label: time.label,
              value: time.value,
              note: running == null ? null : 'and the one running',
            ),
            // A kind with no goal completed has no tile; a cut that ended
            // heavier shows its change, not "lost" a negative.
            if (history.any((r) => r.kind == PhaseKind.cut))
              lost <= 0
                  ? FigureTile(
                      label: 'Lost while cutting',
                      value: weightText(-lost, unit),
                    )
                  : FigureTile(
                      label: 'Change while cutting',
                      value: signedWeightText(lost, unit),
                    ),
            if (history.any((r) => r.kind == PhaseKind.bulk))
              gained >= 0
                  ? FigureTile(
                      label: 'Gained while bulking',
                      value: weightText(gained, unit),
                    )
                  : FigureTile(
                      label: 'Change while bulking',
                      value: signedWeightText(gained, unit),
                    ),
          ],
        ),
      if (running != null) ...[
        trendSection(context, 'Running'),
        AppCard(
          child: _row(
            context,
            kind: running.kind,
            length: goalLengthText(running.start, today),
            // On its first day there is no change yet to show.
            dates: dayOne
                ? 'Started today'
                : '${format.format(running.start)} – now',
            startKg: running.startKg,
            endKg: data.trend.isEmpty || dayOne ? null : data.trend.last,
            targetKg: running.targetKg,
            now: true,
          ),
        ),
      ],
      if (history.isNotEmpty) ...[
        trendSection(context, 'Completed'),
        AppCard(
          child: Column(
            children: [
              for (final (i, r) in history.reversed.indexed) ...[
                if (i > 0) const Divider(height: 1),
                _row(
                  context,
                  kind: r.kind,
                  length: goalLengthText(r.start, r.end),
                  dates: dateRangeText(format, r.start, r.end),
                  startKg: r.startKg,
                  endKg: r.endKg,
                  targetKg: r.targetKg,
                  extensions: r.extensions,
                ),
              ],
            ],
          ),
        ),
      ],
    ];
  }

  Widget _row(
    BuildContext context, {
    required PhaseKind kind,
    required String length,
    required String dates,
    required double? startKg,
    required double? endKg,
    required double? targetKg,
    int extensions = 0,
    bool now = false,
  }) {
    final unit = widget.unit;
    final theme = Theme.of(context);
    final weights = startKg == null || endKg == null
        ? null
        : '${weightText(startKg, unit)} → ${weightText(endKg, unit)}';
    final change = startKg == null || endKg == null
        ? null
        : signedWeightText(endKg - startKg, unit);
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.all(Dimens.spacing16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 6,
              height: 44,
              decoration: BoxDecoration(
                color: phaseColor(context, kind),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(width: Dimens.spacing12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${kind.label} · $length'
                    '${extensions == 0 ? '' : ' · extended $extensions×'}',
                    style: theme.textTheme.titleSmall,
                  ),
                  Text(dates, style: theme.textTheme.bodySmall),
                  if (weights != null)
                    Text(
                      '$weights'
                      '${targetKg == null ? '' : ' · target ${weightText(targetKg, unit)}'}',
                      style: theme.textTheme.bodySmall,
                    )
                  else if (targetKg != null)
                    Text(
                      'Target ${weightText(targetKg, unit)}',
                      style: theme.textTheme.bodySmall,
                    ),
                ],
              ),
            ),
            if (change != null)
              Text(
                now ? '$change so far' : change,
                style: theme.textTheme.titleSmall,
              ),
          ],
        ),
      ),
    );
  }
}
