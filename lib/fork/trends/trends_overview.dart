import 'package:flutter/material.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:opennutritracker/core/domain/entity/tracked_day_entity.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/features/trends/presentation/bloc/trends_bloc.dart';
import 'package:opennutritracker/features/trends/presentation/trends_calc.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_service.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_store.dart';
import 'package:opennutritracker/fork/display/display_prefs.dart';
import 'package:opennutritracker/fork/report/rate_text.dart';
import 'package:opennutritracker/fork/report/trends_layout.dart';
import 'package:opennutritracker/fork/goal/goal_progress_page.dart';
import 'package:opennutritracker/fork/trends/trend_detail.dart';
import 'package:opennutritracker/fork/trends/trend_stats.dart';
import 'package:opennutritracker/fork/trends/trends_widgets.dart';
import 'package:opennutritracker/fork/units/energy_text.dart';
import 'package:opennutritracker/generated/l10n.dart';

/// Seam S120: Trends as MacroFactor's (variant A): the streak, the range
/// pills, a grid of tiles that each open their page, then the fork's other
/// cards in the user's arrangement (S47).
class TrendsOverview extends StatefulWidget {
  final TrendsLoaded state;

  /// Upstream's weight and water cards, shown on their detail pages.
  final Widget Function(TrendsLoaded state) weightCard;
  final Widget Function(TrendsLoaded state) waterCard;

  /// The cards below the grid, by the ids of [trendCards].
  final Map<String, Widget> cards;

  /// For tests; the app's from the locator.
  final AdaptiveService? service;

  const TrendsOverview({
    super.key,
    required this.state,
    required this.weightCard,
    required this.waterCard,
    required this.cards,
    this.service,
  });

  @override
  State<TrendsOverview> createState() => _TrendsOverviewState();
}

class _TrendsOverviewState extends State<TrendsOverview> {
  late final _history = ValueNotifier(_load());

  /// The estimate moves with the expenditure settings and the days left
  /// out (D17), and with what was logged.
  late final _changes = Listenable.merge([
    AdaptiveStore.settings,
    AdaptiveStore.skipped,
  ]);

  late final _deps = TrendsDeps(
    expenditure: _history,
    // Through the current widget, so a page open across a theme change
    // builds the cards with the new palette.
    weightCard: (s) => widget.weightCard(s),
    waterCard: (s) => widget.waterCard(s),
    service: widget.service,
  );

  Future<List<ExpenditureDay>> _load() async {
    try {
      return await (widget.service ?? AdaptiveService.fromLocator())
          .expenditureHistory();
    } catch (_) {
      // Nothing to estimate from (or no locator, in widget tests).
      return const [];
    }
  }

  void _reload() => _history.value = _load();

  @override
  void initState() {
    super.initState();
    _changes.addListener(_reload);
  }

  @override
  void didUpdateWidget(TrendsOverview old) {
    super.didUpdateWidget(old);
    // After the frame: an open detail page listens too, and is not
    // under this one to be rebuilt with it.
    if (old.state != widget.state) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _reload();
      });
    }
  }

  @override
  void dispose() {
    _changes.removeListener(_reload);
    _history.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final now = DateTime.now();
    final dates = windowDates(
      DateTime(now.year, now.month, now.day),
      state.windowDays,
    );
    return ValueListenableBuilder(
      valueListenable: TrendsLayoutStore.current,
      builder: (context, _, _) => ValueListenableBuilder(
        valueListenable: DisplayPrefs.showWater,
        builder: (context, _, _) => ValueListenableBuilder(
          valueListenable: _history,
          builder: (context, future, _) => FutureBuilder(
            future: future,
            builder: (context, snapshot) {
              final tiles = _tiles(context, dates, snapshot.data ?? const []);
              final logged = state.days.where(isLogged).length;
              return ListView(
                padding: const EdgeInsets.fromLTRB(
                  Dimens.spacing12,
                  Dimens.spacing8,
                  Dimens.spacing12,
                  Dimens.spacing32,
                ),
                children: [
                  _Streak(days: state.days, windowDays: state.windowDays),
                  const SizedBox(height: Dimens.spacing8),
                  RangePills(
                    rangeDays: state.rangeDays,
                    onChanged: (d) => context.read<TrendsBloc>().add(
                      LoadTrendsEvent(rangeDays: d),
                    ),
                  ),
                  const SizedBox(height: Dimens.spacing12),
                  for (var i = 0; i < tiles.length; i += 2)
                    Padding(
                      padding: const EdgeInsets.only(bottom: Dimens.spacing8),
                      // The tiles are alike, so a row's two are one height;
                      // AutoSizeText measures, so no IntrinsicHeight here.
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: tiles[i]),
                          const SizedBox(width: Dimens.spacing8),
                          Expanded(
                            child: i + 1 < tiles.length
                                ? tiles[i + 1]
                                : const SizedBox.shrink(),
                          ),
                        ],
                      ),
                    ),
                  Text(
                    'Tap a card for its chart · '
                    '${rangeText(state.rangeDays, state.windowDays)}, '
                    '$logged logged',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: paletteOf(context).textMuted,
                    ),
                  ),
                  ...arrangeTrendCards(widget.cards),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  List<Widget> _tiles(
    BuildContext context,
    List<DateTime> dates,
    List<ExpenditureDay> history,
  ) {
    final state = widget.state;
    final palette = paletteOf(context);
    final unit = energyUnit(context);
    void open(TrendMetric m) => openTrendDetail(context, m, _deps);

    TrendTile tile(
      TrendMetric m, {
      required String value,
      String? suffix,
      Color? valueColor,
      required DaySeries spark,
      required Color sparkColor,
      bool bars = true,
      String? label,
    }) => TrendTile(
      id: 'trends-tile-${m.name}',
      label: label ?? metricTitle(context, m),
      value: value,
      suffix: suffix,
      valueColor: valueColor,
      chart: Sparkline(values: spark, color: sparkColor, bars: bars),
      onTap: () => open(m),
    );

    final energy = nutritionSeries(state.days, dates, (d) => d.caloriesTracked);
    final energyMean = meanOf(energy);
    final energyGoal = goalOf(state.days, dates, (d) => d.calorieGoal);

    final weight = WeightTrendStats.of(state.weight, dates);
    final wu = state.bodyWeightUnit;
    final wLabel = weightUnitLabel(context, wu);

    final spent = expenditureSeries(history, dates);
    final spentNow = spent.whereType<double>().lastOrNull;
    final balance = balanceSeries(history, dates);
    final balanceMean = meanOf(balance);

    TrendTile macroTile(TrendMetric m, Color color) {
      final macro = macroOf(m);
      final series = nutritionSeries(state.days, dates, macro.eaten);
      final mean = meanOf(series);
      final goal = goalOf(state.days, dates, macro.goal);
      return tile(
        m,
        label: '${metricTitle(context, m)} · avg',
        value: mean == null ? '–' : '${mean.round()}',
        // S114: grams rounded, as the weekly report's are.
        suffix: goal == null ? 'g' : '/ ${goal.round()} g',
        valueColor: color,
        spark: series,
        sparkColor: color,
      );
    }

    final water = waterSeries(state.waterByDay, dates);
    final waterMean = meanOf(water);

    return [
      tile(
        TrendMetric.calories,
        label: '${energyTitle(context)} · avg',
        // Cut, as energyValue is everywhere (S114).
        value: energyMean == null ? '–' : '${energyValue(context, energyMean)}',
        suffix: energyGoal == null
            ? unit
            : '/ ${energyValue(context, energyGoal)} $unit',
        spark: energy,
        sparkColor: palette.accent,
      ),
      tile(
        TrendMetric.weight,
        value: weight.nowKg == null
            ? '–'
            : weightIn(wu, weight.nowKg!).toStringAsFixed(1),
        suffix: weight.perWeekKg == null
            ? wLabel
            : '$wLabel · ${signedRate(weightIn(wu, weight.perWeekKg!))}/wk',
        spark: weight.trend,
        sparkColor: Theme.of(context).colorScheme.primary,
        bars: false,
      ),
      tile(
        TrendMetric.expenditure,
        value: spentNow == null ? '–' : '${energyValue(context, spentNow)}',
        suffix: spentNow == null ? 'after a weigh-in' : '$unit/day',
        spark: spent,
        sparkColor: palette.accent,
        bars: false,
      ),
      tile(
        TrendMetric.balance,
        value: balanceMean == null
            ? '–'
            : signedText(energyValue(context, balanceMean).toDouble()),
        suffix: '$unit/day',
        spark: balance,
        sparkColor: palette.fat,
      ),
      ...inMacroOrder(
        carbs: macroTile(TrendMetric.carbs, palette.carbs),
        fat: macroTile(TrendMetric.fat, palette.fat),
        protein: macroTile(TrendMetric.protein, palette.protein),
      ),
      if (DisplayPrefs.showWater.value)
        tile(
          TrendMetric.water,
          label: '${metricTitle(context, TrendMetric.water)} · avg',
          value: waterMean == null ? '–' : '${waterMean.round()}',
          suffix: state.waterGoalMl > 0 ? '/ ${state.waterGoalMl} ml' : 'ml',
          spark: water,
          sparkColor: waterColor(context),
        ),
      _goalTile(context, state, weight),
    ];
  }
}

/// Goal progress: the way left to the target; it opens Goal progress.
TrendTile _goalTile(
  BuildContext context,
  TrendsLoaded state,
  WeightTrendStats weight,
) {
  final wu = state.bodyWeightUnit;
  final target = state.targetWeightKg;
  final now = weight.nowKg;
  final left = target == null || now == null ? null : (target - now).abs();
  return TrendTile(
    id: 'trends-tile-goal',
    label: 'Goal progress',
    value: left == null
        ? 'No target'
        : left < 0.1
        ? 'There'
        : weightIn(wu, left).toStringAsFixed(1),
    suffix: left == null || left < 0.1
        ? null
        : '${weightUnitLabel(context, wu)} to go',
    chart: Sparkline(
      values: weight.trend,
      color: Theme.of(context).colorScheme.primary,
      bars: false,
    ),
    onTap: () => openGoalProgress(context, wu),
  );
}

/// The on-track streak over the range, as upstream's card counted it.
class _Streak extends StatelessWidget {
  final List<TrackedDayEntity> days;
  final int windowDays;

  const _Streak({required this.days, required this.windowDays});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final palette = paletteOf(context);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final start = DateTime(
      today.year,
      today.month,
      today.day - (windowDays - 1),
    );
    final stats = streakStats(
      {
        for (final d in days)
          if (d.getCalendarDayRatingColor(context) != scheme.error)
            DateTime(d.day.year, d.day.month, d.day.day),
      },
      start,
      today,
    );
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Dimens.spacing4),
        child: Row(
          children: [
            Icon(
              Icons.local_fire_department_rounded,
              color: scheme.primary,
              size: 20,
            ),
            const SizedBox(width: Dimens.spacing4),
            Expanded(
              child: Text(
                '${stats.current} ${S.of(context).trendsDayStreakLabel}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.titleSmall,
              ),
            ),
            Text(
              '${S.of(context).trendsBestStreakLabel} ${stats.longest}',
              style: text.bodySmall?.copyWith(color: palette.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}
