import 'package:flutter/material.dart';
import 'package:opennutritracker/core/domain/entity/body_weight_unit_entity.dart';
import 'package:opennutritracker/fork/display/contrast.dart';
import 'package:opennutritracker/core/presentation/widgets/app_card.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/calc/unit_calc.dart';
import 'package:opennutritracker/features/trends/presentation/bloc/trends_bloc.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_service.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_store.dart';
import 'package:opennutritracker/fork/trends/estimate_span.dart';
import 'package:opennutritracker/fork/trends/expenditure_detail.dart'
    show estimateFromNote;
import 'package:opennutritracker/fork/trends/detail_stats.dart';
import 'package:opennutritracker/fork/trends/detail_widgets.dart';
import 'package:opennutritracker/fork/trends/trend_detail.dart';
import 'package:opennutritracker/fork/trends/trend_stats.dart';
import 'package:opennutritracker/fork/trends/trends_widgets.dart';
import 'package:opennutritracker/fork/units/energy_text.dart';

/// The Energy balance page: the average and total of what was eaten less
/// what was burnt, each logged day's bar, how the days went, and the weight
/// change the balance makes against the trend's, all from the day the
/// estimate starts when that is later than the range.
List<Widget> balanceBody(
  BuildContext context,
  TrendsLoaded state,
  List<ExpenditureDay> history, {
  required List<DateTime> dates,
  required Widget pills,
}) {
  const gap = SizedBox(height: Dimens.spacing16);
  final palette = paletteOf(context);
  final kj = usesKj(context);
  double shown(double kcal) => kj ? UnitCalc.kcalToKj(kcal) : kcal;
  final unit = energyUnit(context);
  final estimate = estimateShown(
    history,
    weighIns: state.weight,
    settings: AdaptiveStore.settings.value.expenditure,
  );
  // The chart and both weight tiles over the days with an estimate.
  final first = estimate.firstOrNull?.date;
  final since = [
    for (final d in dates)
      if (first == null ||
          !d.isBefore(DateTime(first.year, first.month, first.day)))
        d,
  ];
  final span = since.isEmpty ? dates : since;
  final from = span.length < dates.length ? span.first : null;
  final series = balanceSeries(estimate, span);
  final mean = meanOf(series);
  final sum = balanceSummary(estimate, span, today: state.logicalToday);
  String signed(double kcal) =>
      signedText(energyValue(context, kcal).toDouble());
  return [
    StatHeader(
      stats: [
        (
          label: 'Average',
          value: mean == null ? '–' : signed(mean),
          unit: '$unit a day',
        ),
        (
          label: 'Total',
          value: sum == null ? '–' : signed(sum.total),
          unit: unit,
        ),
        (
          label: 'Days with an estimate',
          value: '${sum?.logged ?? 0}',
          unit: sum?.logged == 1 ? 'day' : 'days',
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
            // A new range draws afresh, not old days against its axis.
            key: ValueKey(dates.first),
            values: [for (final v in series) v == null ? null : shown(v)],
            dates: span,
            color: chartSurplus(context),
            negativeColor: chartAccent(context),
            unit: unit,
            label: 'Energy balance chart',
          ),
          if (from != null) ...[
            const SizedBox(height: Dimens.spacing4),
            estimateFromNote(context, from, span.last),
          ],
          const SizedBox(height: Dimens.spacing8),
          Text(
            'What you logged less what you burnt, '
            '${switch (daysPerBar(span.length)) {
              1 => 'each logged day',
              7 => "a week's average a bar",
              _ => "a month's average a bar",
            }}: below the line is a deficit.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: palette.textMuted),
          ),
        ],
      ),
    ),
    if (sum != null && mean != null) ...[
      trendSection(context, 'How the days went'),
      TrendRows(
        rows: [
          if (sum.finished > 0) ...[
            (
              label: 'In deficit',
              value: '${sum.deficit} of ${finishedDays(sum.finished)}',
            ),
            (label: 'In surplus', value: days(sum.surplus)),
          ],
          (label: 'Eaten a day', value: energyText(context, sum.eaten)),
          (label: 'Burnt a day', value: energyText(context, sum.burnt)),
        ],
      ),
      trendSection(context, 'What it means for weight'),
      _WeightTiles(state: state, dates: span, meanKcal: mean),
      const SizedBox(height: Dimens.spacing8),
      Text(
        'The two part ways while water moves the scale, and while the '
        'expenditure estimate is settling.',
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: palette.textMuted),
      ),
    ],
  ];
}

/// The weight change the average balance makes over the range, beside the
/// change in the weight trend.
class _WeightTiles extends StatelessWidget {
  final TrendsLoaded state;
  final List<DateTime> dates;
  final double meanKcal;

  const _WeightTiles({
    required this.state,
    required this.dates,
    required this.meanKcal,
  });

  @override
  Widget build(BuildContext context) {
    final wu = state.bodyWeightUnit;
    final label = weightUnitLabel(context, wu);
    final trend = WeightTrendStats.of(state.weight, dates).changeKg;
    final expected = balanceWeightKg(meanKcal, dates.length);
    return FigureGrid(
      tiles: [
        FigureTile(
          label: 'From the balance',
          value: signedText(weightIn(wu, expected), 1),
          unit: label,
          note:
              'the average day over ${days(dates.length)}, at '
              '${energyText(context, kcalPerWeightUnit(7700, wu))} a '
              '${wu == BodyWeightUnit.kg ? 'kg' : 'lb'}',
        ),
        FigureTile(
          label: 'Trend weight',
          value: trend == null ? '–' : signedText(weightIn(wu, trend), 1),
          unit: trend == null ? null : label,
          note: trend == null
              ? 'no weigh-ins in this range'
              : 'its change over ${days(dates.length)}',
        ),
      ],
    );
  }
}
