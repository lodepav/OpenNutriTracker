import 'package:flutter/material.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:opennutritracker/core/domain/entity/tracked_day_entity.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/features/trends/presentation/bloc/trends_bloc.dart';
import 'package:opennutritracker/features/trends/presentation/trends_calc.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_service.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_store.dart';
import 'package:opennutritracker/core/domain/entity/body_weight_unit_entity.dart';
import 'package:opennutritracker/fork/body/measurement_store.dart';
import 'package:opennutritracker/fork/body/side_compare.dart';
import 'package:opennutritracker/fork/display/display_prefs.dart';
import 'package:opennutritracker/fork/report/rate_text.dart';
import 'package:opennutritracker/fork/layout/arrange_screen.dart';
import 'package:opennutritracker/fork/layout/layout_store.dart';
import 'package:opennutritracker/fork/report/trends_layout.dart';
import 'package:opennutritracker/fork/adaptive/goal_plan_card.dart'
    show paceChanges;
import 'package:opennutritracker/fork/goal/goal_progress.dart';
import 'package:opennutritracker/fork/goal/goal_progress_page.dart';
import 'package:opennutritracker/fork/goal/goal_you_tile.dart';
import 'package:opennutritracker/fork/phases/phases.dart';
import 'package:opennutritracker/fork/report/nutrient_explorer.dart'
    show IntakeLoader, intakesBetween;
import 'package:opennutritracker/fork/trends/nutrient_trends.dart';
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

  /// Where the fibre, sugars and sodium tiles and pages read the intakes;
  /// tests swap it.
  @visibleForTesting
  static IntakeLoader loadIntakes = intakesBetween;

  /// Where the Goal tile's bar reads the goal, as Goal progress does;
  /// tests swap it.
  @visibleForTesting
  static Future<GoalState> Function() loadGoal = () => GoalStartStore().load();

  /// Where the Goal tile reads the goal running and those completed;
  /// tests swap it.
  @visibleForTesting
  static Future<({PhasePlan? plan, List<GoalRecord> history})> Function()
  loadPhases = () async {
    final store = PhaseStore();
    return (plan: await store.plan(), history: await store.history());
  };

  /// The goal as Goal progress loads it, keeping the start when none is
  /// kept yet, with the goal running and, after a completed one, when
  /// maintenance began; nulls with none, or no store (widget tests).
  static Future<TrendsGoal> goal() async {
    GoalProgress? progress;
    ({PhasePlan? plan, List<GoalRecord> history})? phases;
    try {
      progress = (await loadGoal()).progress;
    } catch (_) {}
    try {
      phases = await loadPhases();
    } catch (_) {}
    return (
      progress: progress,
      plan: phases?.plan,
      since: maintainingSince(phases?.plan, phases?.history ?? const []),
    );
  }

  /// Where the left and right tile reads the measurements, here and on
  /// Home; tests swap it.
  static Future<List<Measurement>> Function() loadMeasurements = () async =>
      MeasurementStore().all();

  @override
  State<TrendsOverview> createState() => _TrendsOverviewState();
}

class _TrendsOverviewState extends State<TrendsOverview> {
  late final _history = ValueNotifier(_load());

  /// The tiles' and the cards' arrangement, and the pair the left and
  /// right tile compares; Trends rebuilds on any.
  final _layouts = Listenable.merge([
    TrendsTilesStore.current,
    TrendsLayoutStore.current,
    SidePartPref.current,
  ]);

  /// The body measurements, for the left and right tile.
  late Future<List<Measurement>> _measurements = _measure();

  static Future<List<Measurement>> _measure() =>
      TrendsOverview.loadMeasurements().catchError(
        (Object _) => <Measurement>[],
      );

  void _remeasure() => setState(() {
    _measurements = _measure();
  });

  /// The goal, for the Goal tile; read again for a new pace or target.
  late Future<TrendsGoal> _goal = TrendsOverview.goal();

  void _regoal() => setState(() {
    _goal = TrendsOverview.goal();
  });

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
    loadIntakes: (first, last) => TrendsOverview.loadIntakes(first, last),
  );

  /// The window's intakes for the micronutrient tiles, kept while the
  /// window and the loaded state stay.
  Future<MicroData?>? _micros;
  (DateTime, TrendsLoaded)? _microsFor;

  Future<MicroData?> _microsOf(List<DateTime> dates) {
    final key = (dates.first, widget.state);
    if (_microsFor != key) {
      _microsFor = key;
      _micros = loadMicros(_deps.loadIntakes, dates);
    }
    return _micros!;
  }

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
    MeasurementStore.changes.addListener(_remeasure);
    paceChanges.addListener(_regoal);
    PhaseStore.changes.addListener(_regoal);
    SidePartPref.ensureLoaded();
  }

  @override
  void didUpdateWidget(TrendsOverview old) {
    super.didUpdateWidget(old);
    if (old.state.targetWeightKg != widget.state.targetWeightKg) {
      _goal = TrendsOverview.goal();
    }
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
    MeasurementStore.changes.removeListener(_remeasure);
    paceChanges.removeListener(_regoal);
    PhaseStore.changes.removeListener(_regoal);
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
    return ListenableBuilder(
      listenable: _layouts,
      builder: (context, _) => ValueListenableBuilder(
        valueListenable: DisplayPrefs.showWater,
        builder: (context, _, _) => ValueListenableBuilder(
          valueListenable: _history,
          builder: (context, future, _) => FutureBuilder(
            future: future,
            builder: (context, snapshot) => FutureBuilder(
              future: dates.isEmpty ? null : _microsOf(dates),
              builder: (context, micros) => FutureBuilder(
                future: _measurements,
                builder: (context, measured) => FutureBuilder(
                  future: _goal,
                  builder: (context, goal) {
                    final all = {
                      for (final t in trendTiles(
                        context,
                        state,
                        dates: dates,
                        history: snapshot.data ?? const [],
                        micros: micros.data,
                        measurements: measured.data,
                        goal: goal.data,
                        open: (m) => openTrendDetail(context, m, _deps),
                      ))
                        t.id.substring('trends-tile-'.length): t,
                    };
                    final tiles = arranged(all, TrendsTilesStore.current.value);
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
                            padding: const EdgeInsets.only(
                              bottom: Dimens.spacing8,
                            ),
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
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: paletteOf(context).textMuted),
                        ),
                        ...arrangeTrendCards(widget.cards),
                        const SizedBox(height: Dimens.spacing16),
                        Center(
                          child: TextButton.icon(
                            key: const ValueKey('trends-arrange'),
                            icon: const Icon(Icons.tune_rounded),
                            label: const Text('Arrange Trends'),
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute<void>(
                                builder: (_) => ArrangeScreen(
                                  title: 'Arrange Trends',
                                  lists: [
                                    ArrangeList(
                                      title: 'Tiles',
                                      store: TrendsTilesStore(),
                                      names: {
                                        for (final MapEntry(:key, :value)
                                            in all.entries)
                                          key: value.label.replaceAll(
                                            ' · avg',
                                            '',
                                          ),
                                      },
                                    ),
                                    ArrangeList(
                                      title: 'Cards',
                                      store: TrendsLayoutStore(),
                                      names: trendCards,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The tiles, by id `trends-tile-<metric>`: what each shows over [dates],
/// and [open] opens a metric's page. Home shows those added there.
List<TrendTile> trendTiles(
  BuildContext context,
  TrendsLoaded state, {
  required List<DateTime> dates,
  required List<ExpenditureDay> history,
  required MicroData? micros,
  required List<Measurement>? measurements,
  TrendsGoal? goal,
  required void Function(TrendMetric metric) open,
}) {
  final palette = paletteOf(context);
  final unit = energyUnit(context);

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

  TrendTile microTile(TrendMetric m) {
    final nutrient = microNutrient(m);
    final micro = micros == null ? null : microOf(micros, state.days, dates, m);
    final mean = micro == null ? null : meanOf(micro.series);
    final goal = micro?.summary.goal;
    final color = Theme.of(context).colorScheme.primary;
    return tile(
      m,
      label: '${metricTitle(context, m)} · avg',
      value: mean == null ? '–' : '${mean.round()}',
      suffix: goal == null
          ? nutrient.unit
          : '/ ${goal.round()} ${nutrient.unit}',
      spark: micro?.series ?? [for (final _ in dates) null],
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
    for (final m in microLabels.keys) microTile(m),
    if (DisplayPrefs.showWater.value)
      tile(
        TrendMetric.water,
        label: '${metricTitle(context, TrendMetric.water)} · avg',
        value: waterMean == null ? '–' : '${waterMean.round()}',
        suffix: state.waterGoalMl > 0 ? '/ ${state.waterGoalMl} ml' : 'ml',
        spark: water,
        sparkColor: waterColor(context),
      ),
    _goalTile(context, state, weight, goal),
    _sidesTile(context, state, measurements),
  ];
}

/// Goal progress: the way left to the target, none once there or past
/// it, as Goal progress counts from [goal]'s start; it opens Goal progress.
TrendTile _goalTile(
  BuildContext context,
  TrendsLoaded state,
  WeightTrendStats weight,
  TrendsGoal? goal,
) {
  final wu = state.bodyWeightUnit;
  final target = state.targetWeightKg;
  final now = weight.nowKg;
  final left = target == null || now == null
      ? null
      : goalLeftKg(target, now, goal?.progress);
  final untargeted = untargetedGoal(context, goal?.plan, goal?.since);
  return TrendTile(
    id: 'trends-tile-goal',
    label: 'Goal',
    value: left == null
        ? untargeted.value
        : left < 0.1
        ? 'There'
        : weightIn(wu, left).toStringAsFixed(1),
    suffix: left == null
        ? untargeted.note
        : left < 0.1
        ? null
        : '${weightUnitLabel(context, wu)} to go',
    chart: target == null || now == null
        ? const SizedBox()
        : _GoalBar(progress: goal?.progress),
    onTap: () => openGoalProgress(context, wu),
  );
}

/// Left against right: the latest difference of the pair picked and the
/// bigger side; it opens their comparison.
TrendTile _sidesTile(
  BuildContext context,
  TrendsLoaded state,
  List<Measurement>? measurements,
) {
  final part = SidePartPref.current.value;
  final units = SideUnits(state.bodyWeightUnit != BodyWeightUnit.kg);
  final text = measurements == null
      ? null
      : sideTileText(sidePairs(measurements, part), units);
  return TrendTile(
    id: 'trends-tile-sides',
    label: '${part.label} · left vs right',
    value: text?.value ?? '–',
    suffix: text == null ? 'measure both sides' : text.suffix,
    chart: const SizedBox(),
    onTap: () => openSideCompare(
      context,
      imperial: units.imperial,
      rangeDays: state.windowDays,
    ),
  );
}

/// How far along the goal is, from its kept start; nothing before one is
/// kept.
class _GoalBar extends StatelessWidget {
  final GoalProgress? progress;

  const _GoalBar({required this.progress});

  @override
  Widget build(BuildContext context) {
    final progress = this.progress;
    if (progress == null || progress.totalKg.abs() < 0.1) {
      return const SizedBox();
    }
    final palette = paletteOf(context);
    // The tile's text says it; the bar's percent would only be read
    // before it.
    return ExcludeSemantics(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ClipRRect(
          borderRadius: Dimens.borderRadiusS,
          child: LinearProgressIndicator(
            value: progress.fraction,
            minHeight: 8,
            color: Theme.of(context).colorScheme.primary,
            backgroundColor: palette.surfaceMuted,
          ),
        ),
      ),
    );
  }
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
    // No "0 day streak" to someone who has not had one yet (C3)
    if (stats.longest == 0) return const SizedBox.shrink();
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

/// The Goal tile's goal: its progress to the target, the goal running,
/// and when maintenance began after a completed one.
typedef TrendsGoal = ({
  GoalProgress? progress,
  PhasePlan? plan,
  DateTime? since,
});
