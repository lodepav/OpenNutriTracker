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
import 'package:opennutritracker/fork/display/display_prefs.dart';
import 'package:opennutritracker/fork/report/rate_text.dart';
import 'package:opennutritracker/fork/trends/trend_detail.dart';
import 'package:opennutritracker/fork/trends/trend_stats.dart';
import 'package:opennutritracker/fork/trends/trends_widgets.dart';
import 'package:opennutritracker/fork/units/energy_text.dart';

/// Variant C: the energy of each day stacked by macro, then the range's
/// daily averages against their goals.
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
          padding: const EdgeInsets.fromLTRB(
            Dimens.spacing16,
            Dimens.spacing8,
            Dimens.spacing16,
            Dimens.spacing32,
          ),
          children: [
            RangePills(
              rangeDays: state.rangeDays,
              onChanged: (d) =>
                  context.read<TrendsBloc>().add(LoadTrendsEvent(rangeDays: d)),
            ),
            const SizedBox(height: Dimens.spacing16),
            MacroEnergyChart(state: state, dates: dates),
            const SizedBox(height: Dimens.spacing16),
            AveragesTable(state: state, dates: dates),
          ],
        );
      },
    ),
  );
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
    final text = Theme.of(context).textTheme;
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
          Row(
            children: [
              Expanded(
                child: Text(
                  '${energyTitle(context)} by macro',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.titleSmall,
                ),
              ),
              if (mean != null)
                Text.rich(
                  TextSpan(
                    text: '${energyValue(context, mean)}',
                    style: text.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                    children: [
                      TextSpan(
                        text: ' avg / day',
                        style: text.bodySmall?.copyWith(
                          color: palette.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: Dimens.spacing12),
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
          Wrap(
            spacing: Dimens.spacing12,
            children: [
              for (final m in macros)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: m.color,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(m.label, style: text.bodySmall),
                  ],
                ),
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

/// The range's daily averages, each over the logged days, against the
/// goals: energy, the macros in the user's order, water, the weight trend.
class AveragesTable extends StatelessWidget {
  final TrendsLoaded state;
  final List<DateTime> dates;

  const AveragesTable({super.key, required this.state, required this.dates});

  @override
  Widget build(BuildContext context) {
    final palette = paletteOf(context);
    final text = Theme.of(context).textTheme;
    final unit = energyUnit(context);

    ({String name, Color? color, String avg, String goal, String diff}) row(
      String name,
      Color? color,
      double? avg,
      double? goal,
      String unit,
      int Function(double) shown,
    ) => (
      name: name,
      color: color,
      avg: avg == null ? '–' : '${shown(avg)} $unit',
      goal: goal == null ? '–' : '${shown(goal)} $unit',
      diff: avg == null || goal == null
          ? '–'
          : signedText((shown(avg) - shown(goal)).toDouble()),
    );

    int grams(double g) => g.round();
    final macroRows =
        inMacroOrder(
          carbs: TrendMetric.carbs,
          fat: TrendMetric.fat,
          protein: TrendMetric.protein,
        ).map((m) {
          final macro = macroOf(m);
          return row(
            metricTitle(context, m),
            switch (m) {
              TrendMetric.carbs => palette.carbs,
              TrendMetric.fat => palette.fat,
              _ => palette.protein,
            },
            meanOf(nutritionSeries(state.days, dates, macro.eaten)),
            goalOf(state.days, dates, macro.goal),
            'g',
            grams,
          );
        });
    final weight = WeightTrendStats.of(state.weight, dates);
    final wu = state.bodyWeightUnit;
    final rows = [
      row(
        energyTitle(context),
        null,
        meanOf(nutritionSeries(state.days, dates, (d) => d.caloriesTracked)),
        goalOf(state.days, dates, (d) => d.calorieGoal),
        unit,
        (kcal) => energyValue(context, kcal),
      ),
      ...macroRows,
      row(
        metricTitle(context, TrendMetric.water),
        null,
        meanOf(waterSeries(state.waterByDay, dates)),
        state.waterGoalMl > 0 ? state.waterGoalMl.toDouble() : null,
        'ml',
        grams,
      ),
      if (weight.nowKg != null)
        (
          name: metricTitle(context, TrendMetric.weight),
          color: null,
          avg:
              '${weightIn(wu, weight.nowKg!).toStringAsFixed(1)} '
              '${weightUnitLabel(context, wu)}',
          goal: state.targetWeightKg == null
              ? '–'
              : '${weightIn(wu, state.targetWeightKg!).toStringAsFixed(1)} '
                    '${weightUnitLabel(context, wu)}',
          diff: weight.perWeekKg == null
              ? '–'
              : '${signedRate(weightIn(wu, weight.perWeekKg!))}/wk',
        ),
    ];

    Widget cell(String s, {TextStyle? style, bool first = false}) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      child: Text(
        s,
        textAlign: first ? TextAlign.start : TextAlign.end,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style,
      ),
    );
    final head = text.labelSmall?.copyWith(color: palette.textMuted);
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Table(
        key: const ValueKey('trends-averages'),
        columnWidths: const {
          0: FlexColumnWidth(1.25),
          1: FlexColumnWidth(1.1),
          2: FlexColumnWidth(1.1),
          3: FlexColumnWidth(0.9),
        },
        children: [
          TableRow(
            children: [
              cell('Daily average', style: head, first: true),
              cell('Avg', style: head),
              cell('Goal', style: head),
              cell('Diff', style: head),
            ],
          ),
          for (final r in rows)
            TableRow(
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: palette.border)),
              ),
              children: [
                cell(
                  r.name,
                  first: true,
                  style: TextStyle(
                    color: r.color,
                    fontWeight: r.color == null ? null : FontWeight.w700,
                  ),
                ),
                cell(
                  r.avg,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                cell(r.goal),
                cell(r.diff),
              ],
            ),
        ],
      ),
    );
  }
}
