import 'package:flutter/material.dart';
import 'package:opennutritracker/core/presentation/widgets/app_card.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/calc/unit_calc.dart';
import 'package:opennutritracker/features/trends/presentation/bloc/trends_bloc.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_service.dart';
import 'package:opennutritracker/fork/trends/detail_stats.dart';
import 'package:opennutritracker/fork/trends/detail_widgets.dart';
import 'package:opennutritracker/fork/trends/trend_detail.dart';
import 'package:opennutritracker/fork/trends/trend_stats.dart';
import 'package:opennutritracker/fork/trends/trends_widgets.dart';
import 'package:opennutritracker/fork/units/energy_text.dart';

/// The Energy balance page: the average and total of what was eaten less
/// what was burnt, each logged day's bar, how the days went, and the weight
/// change the balance makes against the trend's.
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
  final series = balanceSeries(history, dates);
  final mean = meanOf(series);
  final sum = balanceSummary(history, dates);
  String signed(double kcal) =>
      signedText(energyValue(context, kcal).toDouble());
  return [
    StatHeader(
      stats: [
        (
          label: 'Average',
          value: mean == null ? '–' : signed(mean),
          unit: '$unit/day',
        ),
        (
          label: 'Total',
          value: sum == null ? '–' : signed(sum.total),
          unit: unit,
        ),
        (label: 'Logged', value: '${sum?.logged ?? 0}', unit: 'days'),
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
    if (sum != null && mean != null) ...[
      trendSection(context, 'How the days went'),
      TrendRows(
        rows: [
          (
            label: 'In deficit',
            value: '${sum.deficit} of ${_days(sum.logged)}',
          ),
          (label: 'In surplus', value: _days(sum.surplus)),
          (label: 'Eaten a day', value: energyText(context, sum.eaten)),
          (label: 'Burnt a day', value: energyText(context, sum.burnt)),
        ],
      ),
      trendSection(context, 'What it means for weight'),
      _WeightTiles(state: state, dates: dates, meanKcal: mean),
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

String _days(int n) => n == 1 ? '1 day' : '$n days';

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
              'the average day over ${_days(dates.length)}, at 7700 kcal a kg',
        ),
        FigureTile(
          label: 'Trend weight',
          value: trend == null ? '–' : signedText(weightIn(wu, trend), 1),
          unit: trend == null ? null : label,
          note: trend == null
              ? 'no weigh-ins in this range'
              : 'its change over ${_days(dates.length)}',
        ),
      ],
    );
  }
}
