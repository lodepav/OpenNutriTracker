import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart' as intl;
import 'package:intl/intl.dart' show toBeginningOfSentenceCase;
import 'package:opennutritracker/core/domain/entity/body_weight_unit_entity.dart';
import 'package:opennutritracker/core/domain/entity/tracked_day_entity.dart';
import 'package:opennutritracker/core/presentation/widgets/app_card.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/calc/unit_calc.dart';
import 'package:opennutritracker/features/trends/presentation/bloc/trends_bloc.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_service.dart';
import 'package:opennutritracker/fork/adaptive/expenditure_card.dart';
import 'package:opennutritracker/fork/report/rate_text.dart';
import 'package:opennutritracker/fork/trends/calories_detail.dart';
import 'package:opennutritracker/fork/trends/trend_stats.dart';
import 'package:opennutritracker/fork/trends/trends_widgets.dart';
import 'package:opennutritracker/fork/units/energy_text.dart';
import 'package:opennutritracker/generated/l10n.dart';

/// What the detail pages read beside the bloc's state: the expenditure
/// history the overview loads, and upstream's weight and water cards
/// (seam S120), which keep their charts and the weigh-in button.
class TrendsDeps {
  final ValueListenable<Future<List<ExpenditureDay>>> expenditure;
  final Widget Function(TrendsLoaded state) weightCard;
  final Widget Function(TrendsLoaded state) waterCard;
  final AdaptiveService? service;

  const TrendsDeps({
    required this.expenditure,
    required this.weightCard,
    required this.waterCard,
    this.service,
  });
}

/// "Calories", or "Energy" in kJ as upstream's card said it (S103).
String energyTitle(BuildContext context) => usesKj(context)
    ? S.of(context).mealEnergyLabel
    : S.of(context).trendsCaloriesLabel;

/// A tile's name, and its detail page's title.
String metricTitle(BuildContext context, TrendMetric m) {
  final s = S.of(context);
  return switch (m) {
    TrendMetric.calories => energyTitle(context),
    TrendMetric.weight => 'Weight trend',
    TrendMetric.expenditure => 'Expenditure',
    TrendMetric.balance => 'Energy balance',
    TrendMetric.carbs => toBeginningOfSentenceCase(s.carbsLabel),
    TrendMetric.fat => toBeginningOfSentenceCase(s.fatLabel),
    TrendMetric.protein => toBeginningOfSentenceCase(s.proteinLabel),
    TrendMetric.water => s.trendsWaterLabel,
  };
}

String weightUnitLabel(BuildContext context, BodyWeightUnit unit) =>
    switch (unit) {
      BodyWeightUnit.kg => S.of(context).kgLabel,
      BodyWeightUnit.lb => S.of(context).lbsLabel,
      BodyWeightUnit.st => S.of(context).stLabel,
    };

/// A macro's eaten and goal grams off a tracked day.
({
  double? Function(TrackedDayEntity) eaten,
  double? Function(TrackedDayEntity) goal,
})
macroOf(TrendMetric m) => switch (m) {
  TrendMetric.carbs => (eaten: (d) => d.carbsTracked, goal: (d) => d.carbsGoal),
  TrendMetric.fat => (eaten: (d) => d.fatTracked, goal: (d) => d.fatGoal),
  _ => (eaten: (d) => d.proteinTracked, goal: (d) => d.proteinGoal),
};

/// Opens [metric]'s page over Trends, on the same bloc, so its pills move
/// the overview's range too.
void openTrendDetail(
  BuildContext context,
  TrendMetric metric,
  TrendsDeps deps,
) {
  final bloc = context.read<TrendsBloc>();
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => BlocProvider<TrendsBloc>.value(
        value: bloc,
        child: metric == TrendMetric.calories
            ? CaloriesDetailPage(deps: deps)
            : TrendDetailPage(metric: metric, deps: deps),
      ),
    ),
  );
}

/// Variant B: a metric's average and change, the range pills, its chart.
class TrendDetailPage extends StatelessWidget {
  final TrendMetric metric;
  final TrendsDeps deps;

  const TrendDetailPage({super.key, required this.metric, required this.deps});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(metricTitle(context, metric))),
    body: BlocBuilder<TrendsBloc, TrendsState>(
      builder: (context, state) {
        if (state is! TrendsLoaded) {
          return const Center(child: CircularProgressIndicator());
        }
        return ValueListenableBuilder(
          valueListenable: deps.expenditure,
          builder: (context, future, _) => FutureBuilder(
            future: future,
            builder: (context, snapshot) => ListView(
              padding: EdgeInsets.fromLTRB(
                Dimens.spacing16,
                Dimens.spacing8,
                Dimens.spacing16,
                Dimens.spacing32 + MediaQuery.paddingOf(context).bottom,
              ),
              children: _body(context, state, snapshot.data ?? const []),
            ),
          ),
        );
      },
    ),
  );

  List<Widget> _body(
    BuildContext context,
    TrendsLoaded state,
    List<ExpenditureDay> history,
  ) {
    final now = DateTime.now();
    final dates = windowDates(
      DateTime(now.year, now.month, now.day),
      state.windowDays,
    );
    final pills = RangePills(
      rangeDays: state.rangeDays,
      onChanged: (d) =>
          context.read<TrendsBloc>().add(LoadTrendsEvent(rangeDays: d)),
    );
    final palette = paletteOf(context);
    final kj = usesKj(context);
    double shown(double kcal) => kj ? UnitCalc.kcalToKj(kcal) : kcal;
    final unit = energyUnit(context);
    const gap = SizedBox(height: Dimens.spacing16);

    switch (metric) {
      case TrendMetric.weight:
        final stats = WeightTrendStats.of(state.weight, dates);
        final wu = state.bodyWeightUnit;
        final label = weightUnitLabel(context, wu);
        String? w(double? kg, {bool signed = false}) => kg == null
            ? null
            : signed
            ? signedText(weightIn(wu, kg), 1)
            : weightIn(wu, kg).toStringAsFixed(1);
        return [
          StatHeader(
            stats: [
              (
                label: 'Trend weight',
                value: w(stats.nowKg) ?? '–',
                unit: label,
              ),
              (
                label: 'Change',
                value: w(stats.changeKg, signed: true) ?? '–',
                unit: label,
              ),
              (
                label: 'Per week',
                value: stats.perWeekKg == null
                    ? '–'
                    : signedRate(weightIn(wu, stats.perWeekKg!)),
                unit: label,
              ),
            ],
          ),
          gap,
          pills,
          gap,
          deps.weightCard(state),
          ..._weighIns(context, state, dates, stats),
        ];
      case TrendMetric.expenditure:
        final series = expenditureSeries(history, dates);
        final present = series.whereType<double>();
        final change = present.length < 2 ? null : present.last - present.first;
        return [
          StatHeader(
            stats: [
              (
                label: 'Now',
                value: present.isEmpty
                    ? '–'
                    : '${energyValue(context, present.last)}',
                unit: unit,
              ),
              (
                label: 'Change',
                value: change == null
                    ? '–'
                    : signedText(energyValue(context, change).toDouble()),
                unit: unit,
              ),
              (
                label: 'Average',
                value: meanOf(series) == null
                    ? '–'
                    : '${energyValue(context, meanOf(series)!)}',
                unit: unit,
              ),
            ],
          ),
          gap,
          pills,
          if (history.isEmpty) ...[
            gap,
            noData(
              context,
              'Expenditure is estimated from your first weigh-in.',
            ),
          ] else
            ExpenditureTrendCard(
              rangeDays: state.windowDays,
              palette: palette,
              service: deps.service,
            ),
        ];
      case TrendMetric.balance:
        final series = balanceSeries(history, dates);
        final mean = meanOf(series);
        final change = fittedChange(series);
        return [
          StatHeader(
            stats: [
              (
                label: 'Average',
                value: mean == null
                    ? '–'
                    : signedText(energyValue(context, mean).toDouble()),
                unit: '$unit/day',
              ),
              (
                label: 'Change',
                value: change == null
                    ? '–'
                    : signedText(energyValue(context, change).toDouble()),
                unit: unit,
              ),
              (
                label: 'Logged',
                value: '${series.whereType<double>().length}',
                unit: 'days',
              ),
            ],
          ),
          gap,
          pills,
          gap,
          AppCard(
            padding: const EdgeInsets.all(Dimens.spacing16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DailyBarChart(
                  values: [for (final v in series) v == null ? null : shown(v)],
                  dates: dates,
                  color: palette.fat,
                  negativeColor: palette.accent,
                  unit: unit,
                  label: 'Energy balance chart',
                ),
                const SizedBox(height: Dimens.spacing8),
                Text(
                  'What you logged less what you burnt, each logged day: '
                  'below the line is a deficit.',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: palette.textMuted),
                ),
              ],
            ),
          ),
        ];
      case TrendMetric.carbs || TrendMetric.fat || TrendMetric.protein:
        final macro = macroOf(metric);
        final series = nutritionSeries(state.days, dates, macro.eaten);
        final goal = goalOf(state.days, dates, macro.goal);
        final color = switch (metric) {
          TrendMetric.carbs => palette.carbs,
          TrendMetric.fat => palette.fat,
          _ => palette.protein,
        };
        return [
          _averageHeader(series, goal, 'g'),
          gap,
          pills,
          gap,
          AppCard(
            padding: const EdgeInsets.all(Dimens.spacing16),
            child: DailyBarChart(
              values: series,
              dates: dates,
              color: color,
              goal: goal,
              unit: 'g',
              label: '${metricTitle(context, metric)} chart',
            ),
          ),
        ];
      case TrendMetric.water:
        final series = waterSeries(state.waterByDay, dates);
        return [
          _averageHeader(
            series,
            state.waterGoalMl > 0 ? state.waterGoalMl.toDouble() : null,
            'ml',
          ),
          gap,
          pills,
          gap,
          deps.waterCard(state),
        ];
      case TrendMetric.calories:
        throw StateError('Calories open CaloriesDetailPage');
    }
  }

  /// Average, goal and change, rounded.
  static Widget _averageHeader(DaySeries series, double? goal, String unit) {
    final mean = meanOf(series);
    final change = fittedChange(series);
    return StatHeader(
      stats: [
        (
          label: 'Average',
          value: mean == null ? '–' : '${mean.round()}',
          unit: unit,
        ),
        (
          label: 'Goal',
          value: goal == null ? '–' : '${goal.round()}',
          unit: unit,
        ),
        (
          label: 'Change',
          value: change == null ? '–' : signedText(change),
          unit: unit,
        ),
      ],
    );
  }

  /// The range's weigh-ins, newest first, each with the trend that day.
  static List<Widget> _weighIns(
    BuildContext context,
    TrendsLoaded state,
    List<DateTime> dates,
    WeightTrendStats stats,
  ) {
    if (dates.isEmpty) return const [];
    final palette = paletteOf(context);
    final text = Theme.of(context).textTheme;
    final wu = state.bodyWeightUnit;
    final label = weightUnitLabel(context, wu);
    final today = dates.last;
    final format = intl.DateFormat.MMMEd(
      Localizations.localeOf(context).toLanguageTag(),
    );
    final entries = [
      for (final e in state.weight)
        if (!e.date.isBefore(dates.first) &&
            !DateTime(e.date.year, e.date.month, e.date.day).isAfter(today))
          e,
    ]..sort((a, b) => b.date.compareTo(a.date));
    if (entries.isEmpty) return const [];
    return [
      const SizedBox(height: Dimens.spacing16),
      Semantics(
        header: true,
        child: Text(
          'Weigh-ins',
          style: text.titleSmall?.copyWith(color: palette.textMuted),
        ),
      ),
      const SizedBox(height: Dimens.spacing4),
      for (final e in entries)
        Builder(
          builder: (context) {
            final day = DateTime(e.date.year, e.date.month, e.date.day);
            final i = dates.indexOf(day);
            final trend = i < 0 ? null : stats.trend[i];
            return MergeSemantics(
              child: Container(
                constraints: const BoxConstraints(minHeight: 48),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: palette.border)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        day == today ? 'Today' : format.format(day),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (trend != null)
                      Text(
                        'trend ${weightIn(wu, trend).toStringAsFixed(1)}',
                        style: text.bodySmall?.copyWith(
                          color: palette.textMuted,
                        ),
                      ),
                    const SizedBox(width: Dimens.spacing16),
                    Text(
                      '${weightIn(wu, e.weightKg).toStringAsFixed(1)} $label',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
    ];
  }
}
