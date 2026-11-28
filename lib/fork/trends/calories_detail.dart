import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:opennutritracker/fork/layout/width_cap.dart';
import 'package:opennutritracker/fork/display/contrast.dart';
import 'package:opennutritracker/fork/display/motion.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:opennutritracker/core/domain/entity/tracked_day_entity.dart';
import 'package:opennutritracker/core/presentation/widgets/app_card.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/calc/day_boundary_calc.dart';
import 'package:opennutritracker/core/utils/calc/unit_calc.dart';
import 'package:opennutritracker/features/trends/presentation/bloc/trends_bloc.dart';
import 'package:intl/intl.dart' as intl;
import 'package:opennutritracker/core/domain/usecase/get_tracked_day_usecase.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/fork/display/display_prefs.dart';
import 'package:opennutritracker/fork/trends/detail_stats.dart';
import 'package:opennutritracker/fork/display/macro_foods.dart'
    show FoodsMetric;
import 'package:opennutritracker/fork/trends/detail_widgets.dart';
import 'package:opennutritracker/fork/trends/macro_contributors.dart';
import 'package:opennutritracker/fork/trends/trend_detail.dart';
import 'package:opennutritracker/fork/trends/trend_stats.dart';
import 'package:opennutritracker/fork/trends/trends_widgets.dart';
import 'package:opennutritracker/fork/trends/value_axis.dart';
import 'package:opennutritracker/fork/units/energy_text.dart';
import 'package:opennutritracker/fork/display/chart_semantics.dart';

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
          return const Center(
            child: CircularProgressIndicator(semanticsLabel: 'Loading'),
          );
        }
        final dates = windowDates(state.logicalToday, state.windowDays);
        final insets = MediaQuery.paddingOf(context);
        return ListView(
          padding: EdgeInsets.fromLTRB(
            Dimens.spacing16 + insets.left,
            Dimens.spacing8,
            Dimens.spacing16 + insets.right,
            Dimens.spacing32 + insets.bottom,
          ),
          children: [
            for (final child in [
              ..._header(context, state, dates),
              const SizedBox(height: Dimens.spacing16),
              RangePills(
                rangeDays: state.rangeDays,
                onChanged: (d) => context.read<TrendsBloc>().add(
                  LoadTrendsEvent(rangeDays: d),
                ),
              ),
              const SizedBox(height: Dimens.spacing16),
              MacroEnergyChart(state: state, dates: dates),
              const SizedBox(height: Dimens.spacing16),
              PeriodTopFoods(
                key: ValueKey((dates.firstOrNull, dates.length)),
                metric: FoodsMetric.energy,
                dates: dates,
                color: chartAccent(context),
                load: deps.loadIntakes,
              ),
              if (dayOutcomes(state.days, dates, today: state.logicalToday)
                  case final o when o.logged > 0) ...[
                trendSection(context, 'How the days went'),
                DaysWentCard(outcomes: o, today: state.logicalToday),
              ],
              WeekdayCard(dayStartMinutes: state.dayStartMinutes),
              ValueListenableBuilder(
                valueListenable: deps.expenditure,
                builder: (context, future, _) => FutureBuilder(
                  future: future,
                  builder: (context, snapshot) {
                    final history = snapshot.data ?? const [];
                    final split = weekendSplit(
                      state.days,
                      dates,
                      balance: {
                        for (final (i, b) in balanceSeries(
                          history,
                          dates,
                        ).indexed)
                          dates[i]: ?b,
                      },
                    );
                    if (split == null) return const SizedBox.shrink();
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        trendSection(
                          context,
                          'Weekdays and weekends, last ${days(dates.length)}',
                        ),
                        WeekendCard(split: split, rangeDays: dates.length),
                      ],
                    );
                  },
                ),
              ),
              if (macroShares(state.days, dates) case final shares?) ...[
                trendSection(context, 'Where the energy came from'),
                _Shares(shares: shares),
              ],
            ])
              WidthCap(child: child),
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
  final energy = nutritionSeries(state.days, dates, (d) => d.caloriesTracked);
  final mean = meanOf(energy);
  final goal = goalOf(state.days, dates, (d) => d.calorieGoal);
  final logged = energy.whereType<double>().length;
  final span = rangeDatesText(context, dates);
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
/// or a week's or a month's average over a longer range ([barSpans]); the
/// goal dashed across, or ticked on each bar where the goals differ.
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
    final spans = barSpans(dates);
    final many = spans.length < dates.length;
    final byDate = {
      for (final d in state.days)
        DateTime(d.day.year, d.day.month, d.day.day): d,
    };
    final bars = _bars(
      energy,
      [
        for (final date in dates)
          if (byDate[date] case final d?) macroEnergy(d) else null,
      ],
      spans,
      macros,
    );
    // What is spoken is what is drawn: the bars' heights.
    final heights = [for (final b in bars.nonNulls) b.total];
    final perBar = !many
        ? ''
        : daysPerBar(dates.length) == 7
        ? "a week's average a bar, "
        : "a month's average a bar, ";
    final goals = spanMeans(
      nutritionSeries(
        state.days,
        dates,
        (d) => d.calorieGoal,
      ).map((g) => g != null && g > 0 ? g : null).toList(),
      spans,
    );
    // Ticks only where they say more than one line would.
    final tick = goals.nonNulls.map((g) => shown(g).round()).toSet().length > 1;
    final spanLabel = spanLabels(context, dates);
    final top = [
      for (final b in bars) shown(b?.total ?? 0),
      if (tick) ...goals.nonNulls.map(shown) else if (goal != null) shown(goal),
      1.0,
    ].reduce(math.max);
    final axis = valueAxis(context, 0, top * 1.12);

    return AppCard(
      padding: const EdgeInsets.all(Dimens.spacing16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (mean == null)
            noData(context, 'Nothing logged in this range.')
          else
            ChartSemantics(
              label:
                  '${energyTitle(context)} by macro chart, '
                  '$perBar'
                  'between ${shown(heights.reduce(math.min)).round()} and '
                  '${shown(heights.reduce(math.max)).round()} $unit a day',
              child: SizedBox(
                height: 200,
                child: LayoutBuilder(
                  builder: (context, box) => BarChart(
                    // A new range is drawn afresh, not morphed from the old.
                    key: ValueKey((dates.firstOrNull, dates.length)),
                    duration: motionDuration(
                      context,
                      const Duration(milliseconds: 150),
                    ),
                    BarChartData(
                      minY: 0,
                      maxY: top * 1.12,
                      alignment: BarChartAlignment.spaceAround,
                      gridData: const FlGridData(show: false),
                      borderData: FlBorderData(show: false),
                      titlesData: weekdayTitles(
                        context,
                        [for (final s in spans) dates[s.start]],
                        right: axis.titles,
                        perBar: daysPerBar(dates.length),
                      ),
                      extraLinesData: goalLine(
                        context,
                        tick || goal == null ? null : shown(goal),
                      ),
                      errorIndicatorData: goalTicks(palette.textMuted),
                      barTouchData: BarTouchData(
                        touchTooltipData: BarTouchTooltipData(
                          getTooltipColor: (_) => scheme.inverseSurface,
                          fitInsideHorizontally: true,
                          fitInsideVertically: true,
                          // Rounded, as energyValue is everywhere (S114).
                          getTooltipItem: (group, _, rod, _) => BarTooltipItem(
                            barTooltip(
                              '${rod.toY.round()}',
                              unit,
                              spanLabel(spans[group.x]),
                              many: many,
                            ),
                            TextStyle(color: scheme.onInverseSurface),
                          ),
                        ),
                      ),
                      barGroups: [
                        for (final (i, b) in bars.indexed)
                          _group(
                            i,
                            b,
                            tick ? goals[i] : null,
                            barWidth(box.maxWidth - axis.width, bars.length),
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
    _Bar? bar,
    double? goal,
    double width,
    List<_Macro> macros,
    double Function(double) shown,
    Color plain,
  ) {
    final tick = goal == null ? null : shown(goal);
    if (bar == null) {
      return BarChartGroupData(
        x: x,
        barRods: [
          BarChartRodData(
            toY: 0,
            width: width,
            toYErrorRange: goalRange(0, tick),
          ),
        ],
      );
    }
    final total = shown(bar.total);
    final items = <BarChartRodStackItem>[];
    if (bar.parts.any((p) => p > 0)) {
      var from = 0.0;
      for (final (i, m) in macros.indexed) {
        final to = from + shown(bar.parts[i]);
        items.add(BarChartRodStackItem(from, to, m.color));
        from = to;
      }
      // Days logged without macros, in a bar of several, on top and plain.
      if (total - from > 0.5) {
        items.add(BarChartRodStackItem(from, total, plain));
      }
    }
    return BarChartGroupData(
      x: x,
      barRods: [
        BarChartRodData(
          toY: total,
          width: width,
          // Energy logged without macros: one plain bar.
          color: items.isEmpty ? plain : null,
          rodStackItems: items,
          toYErrorRange: goalRange(total, tick),
          borderRadius: BorderRadius.circular(dates.length <= 31 ? 3 : 0),
        ),
      ],
    );
  }
}

typedef _Bar = ({double total, List<double> parts});

/// Each bar's energy and its macros' parts in [macros]' order, the mean of
/// its days logged: a day without macros adds to the total, to no part.
List<_Bar?> _bars(
  DaySeries energy,
  List<({double carbs, double fat, double protein})?> splits,
  List<({int start, int end})> spans,
  List<_Macro> macros,
) => [
  for (final s in spans)
    if (meanOf(energy.sublist(s.start, s.end)) case final total?)
      (
        total: total,
        parts: [
          for (final m in macros)
            meanOf([
              for (var i = s.start; i < s.end; i++)
                if (energy[i] != null)
                  splits[i] == null ? 0.0 : m.of(splits[i]!),
            ])!,
        ],
      )
    else
      null,
];

/// The logged days against their goals, and the highest and lowest.
class DaysWentCard extends StatelessWidget {
  final ({
    int onTarget,
    int under,
    int over,
    int logged,
    DayValue? highest,
    DayValue? lowest,
    double? overBy,
    double? underBy,
    double? topThreeShare,
  })
  outcomes;

  /// The day the Highest and Lowest rows call "today".
  final DateTime today;

  /// A day's value as shown: its energy, or grams.
  final String Function(BuildContext, double) valueText;

  const DaysWentCard({
    super.key,
    required this.outcomes,
    required this.today,
    this.valueText = energyText,
  });

  @override
  Widget build(BuildContext context) {
    final o = outcomes;
    final locale = Localizations.localeOf(context).toLanguageTag();
    String day(DayValue d) => dayValueText(
      valueText(context, d.value),
      d.date,
      today: today,
      locale: locale,
    );
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
            value: '${o.onTarget} of ${finishedDays(o.logged)}',
          ),
          TrendRow(label: 'Under', value: days(o.under)),
          TrendRow(label: 'Over', value: days(o.over)),
          if (o.overBy case final v?)
            TrendRow(
              label: 'Over by, on average',
              value: valueText(context, v),
            ),
          if (o.underBy case final v?)
            TrendRow(
              label: 'Under by, on average',
              value: valueText(context, v),
            ),
          if (o.topThreeShare case final s?)
            TrendRow(
              label: 'Top 3 days\' share of the excess',
              value: '${(s * 100).round()}%',
            ),
          if (o.highest case final d?)
            TrendRow(label: 'Highest', value: day(d)),
          if (o.lowest case final d?) TrendRow(label: 'Lowest', value: day(d)),
        ],
      ),
    );
  }
}

/// The mean energy by weekday over the last three months, whatever the
/// range, the weekday furthest from its own goal marked.
class WeekdayCard extends StatefulWidget {
  /// The clock; the app's when null.
  final DateTime Function()? now;

  /// Where the day starts, for the logical today the months end on.
  final int dayStartMinutes;

  const WeekdayCard({super.key, this.now, this.dayStartMinutes = 0});

  @override
  State<WeekdayCard> createState() => _WeekdayCardState();
}

class _WeekdayCardState extends State<WeekdayCard> {
  late final Future<List<TrackedDayEntity>> _days = _load();

  Future<List<TrackedDayEntity>> _load() async {
    final clock = widget.now;
    final now = clock == null
        ? DayBoundaryCalc.currentLogicalDayMinutes(widget.dayStartMinutes)
        : DayBoundaryCalc.logicalDayOfMinutes(clock(), widget.dayStartMinutes);
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
                                        ? chartAccent(context)
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
                      ? 'No weekday runs far from its goal.'
                      : '${name(standout.weekday, intl.DateFormat.EEEE(locale))}s '
                            'run ${energyText(context, standout.off.abs())} '
                            '${standout.off > 0 ? 'over' : 'under'} '
                            'their goal.',
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

/// Monday to Friday against the weekend: the energy, the macros and the
/// balance a day, each part's own mean.
class WeekendCard extends StatelessWidget {
  final ({WeekPart weekdays, WeekPart weekend}) split;

  /// The range's days: under four weeks, what the weekend gives back is
  /// one or two weekends' noise, so it is not said.
  final int rangeDays;

  const WeekendCard({super.key, required this.split, required this.rangeDays});

  @override
  Widget build(BuildContext context) {
    final (:weekdays, :weekend) = split;
    final text = Theme.of(context).textTheme;
    final muted = paletteOf(context).textMuted;
    String grams(double? g) => g == null ? '–' : '${g.round()} g';
    String balance(double? b) =>
        b == null ? '–' : energyText(context, b, signed: true);
    final off = weekend.kcal - weekdays.kcal;
    final giveBack = rangeDays >= 28 ? weekendGiveBack(split) : null;
    final rows = [
      (
        'Energy',
        energyText(context, weekdays.kcal),
        energyText(context, weekend.kcal),
      ),
      ...inMacroOrder(
        carbs: ('Carbs', grams(weekdays.carbs), grams(weekend.carbs)),
        fat: ('Fat', grams(weekdays.fat), grams(weekend.fat)),
        protein: ('Protein', grams(weekdays.protein), grams(weekend.protein)),
      ),
      if (weekdays.balance != null || weekend.balance != null)
        ('Balance', balance(weekdays.balance), balance(weekend.balance)),
    ];
    Widget cell(String s, {TextStyle? style, bool end = true}) => Expanded(
      child: Text(s, textAlign: end ? TextAlign.end : null, style: style),
    );
    return AppCard(
      padding: const EdgeInsets.all(Dimens.spacing16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              cell(
                'A day',
                style: text.labelMedium?.copyWith(color: muted),
                end: false,
              ),
              cell(
                'Mon–Fri\n${days(weekdays.days)}',
                style: text.labelMedium?.copyWith(color: muted),
              ),
              cell(
                'Sat–Sun\n${days(weekend.days)}',
                style: text.labelMedium?.copyWith(color: muted),
              ),
            ],
          ),
          for (final (label, a, b) in rows)
            MergeSemantics(
              child: Padding(
                padding: const EdgeInsets.only(top: Dimens.spacing8),
                child: Row(
                  children: [
                    cell(label, style: text.bodyMedium, end: false),
                    cell(a, style: text.bodyMedium),
                    cell(
                      b,
                      style: text.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: Dimens.spacing8),
          Text(
            off.abs() < 100
                ? 'Weekends run about the same as weekdays.'
                : 'Weekends run ${energyText(context, off.abs())} a day '
                      '${off > 0 ? 'over' : 'under'} weekdays.',
            style: text.bodySmall?.copyWith(color: muted),
          ),
          if (giveBack != null)
            Text(
              giveBack > 1
                  ? 'Weekends give back more than the weekdays\' deficit.'
                  : 'Weekends give back about ${(giveBack * 100).round()}% '
                        'of the weekdays\' deficit.',
              style: text.bodySmall?.copyWith(color: muted),
            ),
        ],
      ),
    );
  }
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
