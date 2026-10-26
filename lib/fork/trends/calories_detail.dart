import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:opennutritracker/core/domain/entity/tracked_day_entity.dart';
import 'package:opennutritracker/core/presentation/widgets/app_card.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/calc/unit_calc.dart';
import 'package:opennutritracker/features/trends/presentation/bloc/trends_bloc.dart';
import 'package:intl/intl.dart' as intl;
import 'package:opennutritracker/core/domain/usecase/get_tracked_day_usecase.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/fork/display/display_prefs.dart';
import 'package:opennutritracker/fork/trends/detail_stats.dart';
import 'package:opennutritracker/fork/trends/detail_widgets.dart';
import 'package:opennutritracker/fork/trends/trend_detail.dart';
import 'package:opennutritracker/fork/trends/trend_stats.dart';
import 'package:opennutritracker/fork/trends/trends_widgets.dart';
import 'package:opennutritracker/fork/units/energy_text.dart';

/// The Calories page, after the canvas's TdNutrA: the average and the
/// goal, each day stacked by macro, how the days went, the weekdays over
/// three months and where the energy came from.
class CaloriesDetailPage extends StatelessWidget {
  final TrendsDeps deps;

  const CaloriesDetailPage({super.key, required this.deps});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(energyTitle(context))),
    body: BlocBuilder<TrendsBloc, TrendsState>(
      builder: (context, state) {
        if (state is! TrendsLoaded) {
          return const Center(child: CircularProgressIndicator());
        }
        final now = DateTime.now();
        final dates = windowDates(
          DateTime(now.year, now.month, now.day),
          state.windowDays,
        );
        return ListView(
          padding: EdgeInsets.fromLTRB(
            Dimens.spacing16,
            Dimens.spacing8,
            Dimens.spacing16,
            Dimens.spacing32 + MediaQuery.paddingOf(context).bottom,
          ),
          children: [
            ..._header(context, state, dates),
            const SizedBox(height: Dimens.spacing16),
            RangePills(
              rangeDays: state.rangeDays,
              onChanged: (d) =>
                  context.read<TrendsBloc>().add(LoadTrendsEvent(rangeDays: d)),
            ),
            const SizedBox(height: Dimens.spacing16),
            MacroEnergyChart(state: state, dates: dates),
            if (dayOutcomes(state.days, dates) case final o
                when o.logged > 0) ...[
              trendSection(context, 'How the days went'),
              _DaysWent(outcomes: o, week: dates.length <= 7),
            ],
            const WeekdayCard(),
            if (macroShares(state.days, dates) case final shares?) ...[
              trendSection(context, 'Where the calories came from'),
              _Shares(shares: shares),
            ],
          ],
        );
      },
    ),
  );
}

/// The average and the goal, and the range with the days logged in it.
List<Widget> _header(
  BuildContext context,
  TrendsLoaded state,
  List<DateTime> dates,
) {
  final unit = energyUnit(context);
  final mean = meanOf(
    nutritionSeries(state.days, dates, (d) => d.caloriesTracked),
  );
  final goal = goalOf(state.days, dates, (d) => d.calorieGoal);
  final logged = nutritionSeries(
    state.days,
    dates,
    (d) => d.caloriesTracked,
  ).whereType<double>().length;
  final format = intl.DateFormat.MMMd(
    Localizations.localeOf(context).toLanguageTag(),
  );
  final span = dates.isEmpty
      ? ''
      : dates.length == 1
      ? format.format(dates.single)
      : '${format.format(dates.first)} – ${format.format(dates.last)}';
  return [
    StatHeader(
      stats: [
        (
          label: 'Average',
          value: mean == null ? '–' : '${energyValue(context, mean)}',
          unit: unit,
        ),
        (
          label: 'Goal',
          value: goal == null ? '–' : '${energyValue(context, goal)}',
          unit: unit,
        ),
      ],
    ),
    const SizedBox(height: Dimens.spacing4),
    Text(
      '$span · $logged of ${dates.length} days logged',
      style: Theme.of(
        context,
      ).textTheme.bodyMedium?.copyWith(color: paletteOf(context).textMuted),
    ),
  ];
}

typedef _Macro = ({
  String label,
  Color color,
  double Function(({double carbs, double fat, double protein}) split) of,
});

/// A bar a day, carbs, fat and protein stacked in the user's macro order,
/// the goal dashed across.
class MacroEnergyChart extends StatelessWidget {
  final TrendsLoaded state;
  final List<DateTime> dates;

  const MacroEnergyChart({super.key, required this.state, required this.dates});

  @override
  Widget build(BuildContext context) {
    final palette = paletteOf(context);
    final scheme = Theme.of(context).colorScheme;
    final kj = usesKj(context);
    double shown(double kcal) => kj ? UnitCalc.kcalToKj(kcal) : kcal;
    final unit = energyUnit(context);
    final byDate = {
      for (final d in state.days)
        DateTime(d.day.year, d.day.month, d.day.day): d,
    };
    final energy = nutritionSeries(state.days, dates, (d) => d.caloriesTracked);
    final mean = meanOf(energy);
    final goal = goalOf(state.days, dates, (d) => d.calorieGoal);
    final macros = inMacroOrder<_Macro>(
      carbs: (
        label: metricTitle(context, TrendMetric.carbs),
        color: palette.carbs,
        of: (m) => m.carbs,
      ),
      fat: (
        label: metricTitle(context, TrendMetric.fat),
        color: palette.fat,
        of: (m) => m.fat,
      ),
      protein: (
        label: metricTitle(context, TrendMetric.protein),
        color: palette.protein,
        of: (m) => m.protein,
      ),
    );
    final dayLabel = dayLabels(context, dates);
    final top = [
      for (final v in energy) shown(v ?? 0),
      if (goal != null) shown(goal),
      1.0,
    ].reduce(math.max);

    return AppCard(
      padding: const EdgeInsets.all(Dimens.spacing16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (mean == null)
            noData(context, 'Nothing logged in this range.')
          else
            Semantics(
              label: '${energyTitle(context)} by macro chart',
              child: SizedBox(
                height: 200,
                child: LayoutBuilder(
                  builder: (context, box) => BarChart(
                    BarChartData(
                      minY: 0,
                      maxY: top * 1.12,
                      alignment: BarChartAlignment.spaceAround,
                      gridData: const FlGridData(show: false),
                      borderData: FlBorderData(show: false),
                      titlesData: weekdayTitles(context, dates),
                      extraLinesData: goalLine(
                        context,
                        goal == null ? null : shown(goal),
                      ),
                      barTouchData: BarTouchData(
                        touchTooltipData: BarTouchTooltipData(
                          getTooltipColor: (_) => scheme.inverseSurface,
                          fitInsideHorizontally: true,
                          fitInsideVertically: true,
                          // Cut, as energyValue is everywhere (S114).
                          getTooltipItem: (group, _, rod, _) => BarTooltipItem(
                            '${rod.toY.toInt()} $unit\n${dayLabel(group.x)}',
                            TextStyle(color: scheme.onInverseSurface),
                          ),
                        ),
                      ),
                      barGroups: [
                        for (final (i, date) in dates.indexed)
                          _group(
                            i,
                            byDate[date],
                            box.maxWidth,
                            macros,
                            shown,
                            palette.textMuted,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          const SizedBox(height: Dimens.spacing8),
          ChartLegend(
            entries: [
              for (final m in macros)
                (label: m.label, color: m.color, line: false),
              if (goal != null)
                (label: 'Goal', color: palette.textMuted, line: true),
            ],
          ),
        ],
      ),
    );
  }

  BarChartGroupData _group(
    int x,
    TrackedDayEntity? day,
    double width,
    List<_Macro> macros,
    double Function(double) shown,
    Color plain,
  ) {
    final w = barWidth(width, dates.length);
    if (day == null || !isLogged(day)) {
      return BarChartGroupData(
        x: x,
        barRods: [BarChartRodData(toY: 0, width: w)],
      );
    }
    final split = macroEnergy(day);
    final total = shown(day.caloriesTracked);
    if (split == null) {
      // Energy logged without macros: one plain bar.
      return BarChartGroupData(
        x: x,
        barRods: [BarChartRodData(toY: total, width: w, color: plain)],
      );
    }
    var from = 0.0;
    final items = <BarChartRodStackItem>[];
    for (final m in macros) {
      final to = from + shown(m.of(split));
      items.add(BarChartRodStackItem(from, to, m.color));
      from = to;
    }
    return BarChartGroupData(
      x: x,
      barRods: [
        BarChartRodData(
          toY: total,
          width: w,
          rodStackItems: items,
          borderRadius: BorderRadius.circular(dates.length <= 31 ? 3 : 0),
        ),
      ],
    );
  }
}

/// The logged days against their goals, and the highest and lowest.
class _DaysWent extends StatelessWidget {
  final ({
    int onTarget,
    int under,
    int over,
    int logged,
    ({double kcal, DateTime date})? highest,
    ({double kcal, DateTime date})? lowest,
  })
  outcomes;

  /// A week names a day by its weekday, a longer range by its date.
  final bool week;

  const _DaysWent({required this.outcomes, required this.week});

  @override
  Widget build(BuildContext context) {
    final o = outcomes;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final format = week
        ? intl.DateFormat.E(locale)
        : intl.DateFormat.MMMd(locale);
    String days(int n) => n == 1 ? '1 day' : '$n days';
    String day(({double kcal, DateTime date}) d) =>
        '${energyText(context, d.kcal)} · ${format.format(d.date)}';
    return AppCard(
      padding: const EdgeInsets.symmetric(
        horizontal: Dimens.spacing16,
        vertical: Dimens.spacing4,
      ),
      child: Column(
        children: [
          TrendRow(
            first: true,
            label: 'On target (within ${(onTargetShare * 100).round()}%)',
            value: '${o.onTarget} of ${days(o.logged)}',
          ),
          TrendRow(label: 'Under', value: days(o.under)),
          TrendRow(label: 'Over', value: days(o.over)),
          if (o.highest case final d?)
            TrendRow(label: 'Highest', value: day(d)),
          if (o.lowest case final d?) TrendRow(label: 'Lowest', value: day(d)),
        ],
      ),
    );
  }
}

/// The mean energy by weekday over the last three months, whatever the
/// range, the weekday that stands out marked.
class WeekdayCard extends StatefulWidget {
  /// Today; the clock in tests.
  final DateTime Function() now;

  const WeekdayCard({super.key, this.now = DateTime.now});

  @override
  State<WeekdayCard> createState() => _WeekdayCardState();
}

class _WeekdayCardState extends State<WeekdayCard> {
  late final Future<List<TrackedDayEntity>> _days = _load();

  Future<List<TrackedDayEntity>> _load() async {
    final now = widget.now();
    try {
      return await locator<GetTrackedDayUsecase>().getTrackedDaysByRange(
        DateTime(now.year, now.month, now.day - 89),
        DateTime(now.year, now.month, now.day, 23, 59, 59),
      );
    } catch (_) {
      // No locator, in widget tests.
      return const [];
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: _days,
    builder: (context, snapshot) {
      final means = weekdayMeans(snapshot.data ?? const []);
      if (means == null) return const SizedBox.shrink();
      final palette = paletteOf(context);
      final text = Theme.of(context).textTheme;
      final standout = standoutWeekday(means);
      final top = means.byWeekday.values.reduce(math.max);
      final locale = Localizations.localeOf(context).toLanguageTag();
      // January 2024 starts on a Monday, so its day [weekday] is one.
      String name(int weekday, intl.DateFormat f) =>
          f.format(DateTime(2024, 1, weekday));
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          trendSection(context, 'By weekday, last 3 months'),
          AppCard(
            padding: const EdgeInsets.all(Dimens.spacing16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Sized by its bars and labels, so a large font grows it.
                Padding(
                  padding: const EdgeInsets.only(top: 30),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (var w = 1; w <= 7; w++)
                        Expanded(
                          child: Semantics(
                            label: means.byWeekday[w] == null
                                ? '${name(w, intl.DateFormat.EEEE(locale))}, '
                                      'nothing logged'
                                : '${name(w, intl.DateFormat.EEEE(locale))}, '
                                      '${energyText(context, means.byWeekday[w]!)}',
                            excludeSemantics: true,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 22,
                                  height: 70 * (means.byWeekday[w] ?? 0) / top,
                                  decoration: BoxDecoration(
                                    // Not the macro colours of the chart
                                    // above: the standout day in the accent.
                                    color: standout?.weekday == w
                                        ? Theme.of(context).colorScheme.primary
                                        : palette.textMuted,
                                    borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(5),
                                      bottom: Radius.circular(2),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    name(w, intl.DateFormat.E(locale)),
                                    maxLines: 1,
                                    style: text.labelSmall?.copyWith(
                                      color: palette.textMuted,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: Dimens.spacing8),
                Text(
                  standout == null
                      ? 'No weekday runs far from your average.'
                      : '${name(standout.weekday, intl.DateFormat.EEEE(locale))}s '
                            'run ${energyText(context, standout.off.abs())} '
                            '${standout.off > 0 ? 'over' : 'under'} '
                            'your average.',
                  style: text.bodySmall?.copyWith(color: palette.textMuted),
                ),
              ],
            ),
          ),
        ],
      );
    },
  );
}

/// The share of the energy each macro gave, against its goal's share.
class _Shares extends StatelessWidget {
  final ({
    ({double carbs, double fat, double protein}) eaten,
    ({double carbs, double fat, double protein})? goal,
  })
  shares;

  const _Shares({required this.shares});

  @override
  Widget build(BuildContext context) {
    final palette = paletteOf(context);
    final eaten = shares.eaten;
    final goal = shares.goal;
    final rows =
        inMacroOrder<
          ({TrendMetric metric, Color color, double share, double? goal})
        >(
          carbs: (
            metric: TrendMetric.carbs,
            color: palette.carbs,
            share: eaten.carbs,
            goal: goal?.carbs,
          ),
          fat: (
            metric: TrendMetric.fat,
            color: palette.fat,
            share: eaten.fat,
            goal: goal?.fat,
          ),
          protein: (
            metric: TrendMetric.protein,
            color: palette.protein,
            share: eaten.protein,
            goal: goal?.protein,
          ),
        );
    String pct(double share) => '${(share * 100).round()}%';
    return AppCard(
      padding: const EdgeInsets.all(Dimens.spacing16),
      child: Column(
        children: [
          ExcludeSemantics(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                height: 12,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final r in rows)
                      if (r.share > 0)
                        Expanded(
                          flex: (r.share * 1000).round().clamp(1, 1000),
                          child: ColoredBox(color: r.color),
                        ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: Dimens.spacing4),
          for (final (i, r) in rows.indexed)
            TrendRow(
              first: i == 0,
              label: metricTitle(context, r.metric),
              value: r.goal == null
                  ? pct(r.share)
                  : '${pct(r.share)} · goal ${pct(r.goal!)}',
            ),
        ],
      ),
    );
  }
}
