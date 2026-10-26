import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart' show toBeginningOfSentenceCase;
import 'package:opennutritracker/core/domain/entity/body_weight_unit_entity.dart';
import 'package:opennutritracker/core/domain/entity/tracked_day_entity.dart';
import 'package:opennutritracker/core/presentation/widgets/app_card.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/features/trends/presentation/bloc/trends_bloc.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_service.dart';
import 'package:opennutritracker/fork/trends/balance_detail.dart';
import 'package:opennutritracker/fork/trends/calories_detail.dart';
import 'package:opennutritracker/fork/trends/expenditure_detail.dart';
import 'package:opennutritracker/fork/trends/trend_stats.dart';
import 'package:opennutritracker/fork/trends/trends_widgets.dart';
import 'package:opennutritracker/fork/trends/weight_detail.dart';
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
  TrendsDeps deps, {
  TrendsBloc? bloc,
}) {
  bloc ??= context.read<TrendsBloc>();
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => BlocProvider<TrendsBloc>.value(
        value: bloc!,
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
    const gap = SizedBox(height: Dimens.spacing16);

    switch (metric) {
      case TrendMetric.weight:
        return weightDetailBody(context, state, dates, deps, pills);
      case TrendMetric.expenditure:
        return expenditureBody(
          context,
          state,
          history,
          dates: dates,
          pills: pills,
          service: deps.service,
        );
      case TrendMetric.balance:
        return balanceBody(context, state, history, dates: dates, pills: pills);
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
}
