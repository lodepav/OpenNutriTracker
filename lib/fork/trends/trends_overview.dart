import 'package:flutter/material.dart';
import 'package:opennutritracker/fork/units/amount_text.dart';
import 'package:opennutritracker/fork/layout/width_cap.dart';
import 'package:opennutritracker/fork/display/contrast.dart';
import 'package:opennutritracker/core/utils/calc/unit_calc.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:opennutritracker/core/domain/entity/tracked_day_entity.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/features/trends/presentation/bloc/trends_bloc.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_service.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_store.dart';
import 'package:opennutritracker/core/domain/entity/body_weight_unit_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_weight_goal_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_user_usecase.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/fork/body/measurement_store.dart';
import 'package:opennutritracker/fork/body/side_compare.dart';
import 'package:opennutritracker/fork/body/waist_ratio.dart';
import 'package:opennutritracker/fork/display/display_prefs.dart';
import 'package:opennutritracker/fork/report/rate_text.dart';
import 'package:opennutritracker/fork/layout/arrange_screen.dart';
import 'package:opennutritracker/fork/layout/layout_store.dart';
import 'package:opennutritracker/fork/report/trends_layout.dart';
import 'package:opennutritracker/fork/adaptive/goal_saving.dart'
    show paceChanges;
import 'package:opennutritracker/fork/goal/goal_progress.dart';
import 'package:opennutritracker/fork/goal/goal_summary.dart';
import 'package:opennutritracker/fork/goal/goal_summary_view.dart';
import 'package:opennutritracker/fork/goal/goal_you_tile.dart';
import 'package:opennutritracker/fork/phases/phases.dart';
import 'package:opennutritracker/fork/report/nutrient_explorer.dart'
    show IntakeLoader, allTrackedDays, intakesBetween;
import 'package:opennutritracker/fork/trends/estimate_span.dart';
import 'package:opennutritracker/fork/trends/expenditure_detail.dart'
    show estimateDay;
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

  /// Where the fibre, sugars and salt tiles and pages read the intakes;
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

  /// Where the Goal tile reads the profile's goal and weekly rate, as the
  /// You tab shows them; tests swap it.
  @visibleForTesting
  static Future<ProfilePace> Function() loadPace = () async {
    final user = await locator<GetUserUsecase>().getUserData();
    return (goal: user.goal, kgPerWeek: user.weeklyWeightGoalKg);
  };

  /// The goal as Goal progress loads it, keeping the start when none is
  /// kept yet, and the trend now, with the goal running, those completed,
  /// and the profile's pace; nulls with none, or no store (widget tests).
  static Future<TrendsGoal> goal() async {
    GoalState? state;
    ({PhasePlan? plan, List<GoalRecord> history})? phases;
    ProfilePace? pace;
    try {
      state = await loadGoal();
    } catch (_) {}
    try {
      phases = await loadPhases();
    } catch (_) {}
    try {
      pace = await loadPace();
    } catch (_) {}
    return (
      progress: state?.progress,
      nowKg: state?.inputs?.nowKg ?? state?.progress?.nowKg,
      plan: phases?.plan,
      history: phases?.history ?? const <GoalRecord>[],
      pace: pace,
    );
  }

  /// Where the streak reads every tracked day, past the range; null
  /// without a database, and the range's days are counted. Tests swap it.
  @visibleForTesting
  static Future<List<TrackedDayEntity>?> Function() loadAllDays =
      allTrackedDays;

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

  /// The profile's height and gender, for the waist tile.
  late Future<BodyFrame?> _frame = loadBodyFrame();

  /// Every tracked day, for the streak.
  late Future<List<TrackedDayEntity>?> _allDays = TrendsOverview.loadAllDays();

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
      _micros = loadMicros(_deps.loadIntakes, dates, days: widget.state.days);
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
    // A height changed in the profile reloads Trends.
    if (old.state != widget.state) {
      _frame = loadBodyFrame();
      _allDays = TrendsOverview.loadAllDays();
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
    final dates = windowDates(state.logicalToday, state.windowDays);
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
                  builder: (context, goal) => FutureBuilder(
                    future: _frame,
                    builder: (context, frame) {
                      final all = {
                        for (final t in trendTiles(
                          context,
                          state,
                          dates: dates,
                          history: snapshot.data ?? const [],
                          micros: micros.data,
                          measurements: measured.data,
                          goal: goal.data,
                          frame: frame.data,
                          open: (m) => openTrendDetail(context, m, _deps),
                        ))
                          t.id.substring('trends-tile-'.length): t,
                      };
                      final layout = TrendsTilesStore.current.value;
                      // Only a profile that never arranged its tiles gets
                      // the default six; a saved order shows tiles it does
                      // not know, as before.
                      final optional = layout.order.isEmpty
                          ? all.keys.toSet().difference(defaultTrendTiles)
                          : const <String>{};
                      // Kept while loading, so the grid does not jump.
                      final settled = [
                        measured,
                        goal,
                        frame,
                      ].every((s) => s.connectionState == ConnectionState.done);
                      final tiles = arranged(all, (
                        order: layout.order,
                        hidden: {...layout.hidden, ...optional},
                      )).where((t) => !settled || !_noData(t)).toList();
                      final perRow =
                          MediaQuery.textScalerOf(context).scale(10) > 15
                          ? 1
                          : 2;
                      final logged = state.days.where(isLogged).length;
                      final range = rangeText(
                        state.rangeDays,
                        state.windowDays,
                      );
                      // One column, built once: a lazy list dropped the
                      // cards scrolled past, and rebuilt they load from
                      // nothing to their height above the screen, which
                      // fought the scroll on the way back up.
                      final insets = MediaQuery.paddingOf(context);
                      return SingleChildScrollView(
                        padding: EdgeInsets.fromLTRB(
                          // the gutter every other page has
                          Dimens.spacing16 + insets.left,
                          Dimens.spacing8,
                          Dimens.spacing16 + insets.right,
                          Dimens.spacing32,
                        ),
                        child: WidthCap(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              FutureBuilder(
                                future: _allDays,
                                builder: (context, all) =>
                                    // Not the range's streak while loading.
                                    !all.hasData &&
                                        all.connectionState !=
                                            ConnectionState.done
                                    ? const SizedBox.shrink()
                                    : _Streak(
                                        days: all.data ?? state.days,
                                        today: state.logicalToday,
                                      ),
                              ),
                              const SizedBox(height: Dimens.spacing8),
                              RangePills(
                                rangeDays: state.rangeDays,
                                onChanged: (d) => context
                                    .read<TrendsBloc>()
                                    .add(LoadTrendsEvent(rangeDays: d)),
                              ),
                              const SizedBox(height: Dimens.spacing8),
                              Semantics(
                                label:
                                    '$range${logged == 0 ? '' : ', $logged ${logged == 1 ? 'day' : 'days'} logged'}',
                                excludeSemantics: true,
                                child: Text(
                                  '$range${logged == 0 ? '' : ' · $logged\u00A0logged'}',
                                  key: const ValueKey('trends-span'),
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: paletteOf(context).textMuted,
                                      ),
                                ),
                              ),
                              const SizedBox(height: Dimens.spacing8),
                              for (var i = 0; i < tiles.length; i += perRow)
                                Padding(
                                  padding: const EdgeInsets.only(
                                    bottom: Dimens.spacing8,
                                  ),
                                  // A row's two one height, as on Home.
                                  child: perRow == 1
                                      ? tiles[i]
                                      : IntrinsicHeight(
                                          child: Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.stretch,
                                            children: [
                                              Expanded(child: tiles[i]),
                                              const SizedBox(
                                                width: Dimens.spacing8,
                                              ),
                                              Expanded(
                                                child: i + 1 < tiles.length
                                                    ? tiles[i + 1]
                                                    : const SizedBox.shrink(),
                                              ),
                                            ],
                                          ),
                                        ),
                                ),
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
                                                key: value.label,
                                            },
                                            optional: optional,
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
                              ...arrangeTrendCards(widget.cards),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
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
  BodyFrame? frame,
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
    Color? sparkNegativeColor,
    double? sparkGoal,
    String Function(double value)? sparkScale,
    bool bars = true,
    required String spoken,
    String? note,
    bool noteMuted = false,
  }) => TrendTile(
    id: 'trends-tile-${m.name}',
    label: metricTitle(context, m),
    value: value,
    suffix: suffix,
    valueColor: valueColor,
    chart: Sparkline(
      values: spark,
      color: sparkColor,
      negativeColor: sparkNegativeColor,
      goal: sparkGoal,
      scaleText: sparkScale,
      bars: bars,
    ),
    onTap: () => open(m),
    spokenLabel: spoken,
    note: note,
    noteMuted: noteMuted,
  );

  /// "Protein, daily average 93 of 110 g", or that none was logged.
  String averageSpoken(TrendMetric m, String? mean, String? goal, String u) =>
      mean == null
      ? '${metricTitle(context, m)}, nothing logged'
      : '${metricTitle(context, m)}, daily average $mean'
            '${goal == null ? '' : ' of $goal'} $u';

  final energy = nutritionSeries(state.days, dates, (d) => d.caloriesTracked);
  final energyMean = meanOf(energy);
  final energyGoal = goalOf(state.days, dates, (d) => d.calorieGoal);

  final weight = WeightTrendStats.of(state.weight, dates);
  final wu = state.bodyWeightUnit;
  final wLabel = weightUnitLabel(context, wu);

  // Without the days a run cut at the look-back spends settling.
  final estimate = estimateShown(
    history,
    weighIns: state.weight,
    settings: AdaptiveStore.settings.value.expenditure,
  );
  final spent = expenditureSeries(estimate, dates);
  final spentNow = spent.whereType<double>().lastOrNull;
  // Both from the day the estimate starts: before it the line would start
  // late and the bars be grey stubs beside "logged".
  final spentLine = fromDay(
    expenditureSeries(estimate, dates, settledOnly: true),
    dates,
    estimate.firstOrNull?.date,
  );
  final balance = balanceSeries(estimate, dates);
  final balanceMean = meanOf(balance);
  final balanceBars = fromDay(balance, dates, estimate.firstOrNull?.date);
  final estimateFrom = switch (balanceBars.from) {
    null => null,
    final d => 'from ${estimateDay(context, d, state.logicalToday)}',
  };

  TrendTile macroTile(TrendMetric m, Color color) {
    final macro = macroOf(m);
    final series = nutritionSeries(state.days, dates, macro.eaten);
    final mean = meanOf(series);
    final goal = goalOf(state.days, dates, macro.goal);
    return tile(
      m,
      value: mean == null ? '–' : '${mean.round()}',
      // S114: grams rounded, as the weekly report's are.
      suffix: goal == null ? 'g' : '/ ${goal.round()} g',
      valueColor: color,
      spark: series,
      sparkColor: color,
      sparkGoal: goal,
      spoken: averageSpoken(
        m,
        mean == null ? null : '${mean.round()}',
        goal == null ? null : '${goal.round()}',
        'g',
      ),
    );
  }

  TrendTile microTile(TrendMetric m) {
    final nutrient = microNutrient(m);
    final micro = micros == null ? null : microOf(micros, state.days, dates, m);
    final mean = micro == null ? null : microMean(micro);
    final goal = micro?.summary.goal;
    final color = chartAccent(context);
    // As shown: "2300 / 2300 mg" is not over.
    final over =
        nutrient.isLimit &&
        mean != null &&
        goal != null &&
        double.parse(nutrient.text(mean)) > double.parse(nutrient.text(goal));
    final spoken = averageSpoken(
      m,
      mean == null ? null : nutrient.text(mean),
      goal == null ? null : nutrient.text(goal),
      nutrient.unit,
    );
    return tile(
      m,
      value: mean == null ? '–' : nutrient.text(mean),
      suffix: goal == null
          ? nutrient.unit
          : '/ ${nutrient.text(goal)} ${nutrient.unit}',
      spark: micro?.series ?? [for (final _ in dates) null],
      sparkColor: color,
      sparkGoal: goal,
      note: over ? 'over limit' : null,
      spoken: over ? '$spoken, over limit' : spoken,
    );
  }

  final flOz = state.usesImperialFoodUnits;
  final water = waterSeries(state.waterByDay, dates, flOz: flOz);
  final waterUnit = flOz ? 'fl oz' : 'ml';
  final waterGoal = flOz
      ? UnitCalc.mlToFlOz(state.waterGoalMl.toDouble()).round()
      : state.waterGoalMl;
  final waterMean = meanOf(water);
  final rate = weight.perWeekKg == null
      ? null
      : weightIn(wu, weight.perWeekKg!).abs().toStringAsFixed(2);
  final balanceShown = balanceMean == null
      ? null
      : energyValue(context, balanceMean);

  return [
    tile(
      TrendMetric.calories,
      // Rounded, as energyValue is everywhere (S114).
      value: energyMean == null ? '–' : '${energyValue(context, energyMean)}',
      suffix: energyGoal == null
          ? unit
          : '/ ${energyValue(context, energyGoal)} $unit',
      spark: energy,
      sparkColor: chartAccent(context),
      sparkGoal: energyGoal,
      spoken: averageSpoken(
        TrendMetric.calories,
        energyMean == null ? null : '${energyValue(context, energyMean)}',
        energyGoal == null ? null : '${energyValue(context, energyGoal)}',
        unit,
      ),
    ),
    tile(
      TrendMetric.weight,
      value: weight.nowKg == null
          ? '–'
          : weightIn(wu, weight.nowKg!).toStringAsFixed(1),
      suffix: wLabel,
      // Its own line, as on Home: beside the trend it never fits.
      note: weight.perWeekKg == null
          ? null
          : weeklyRateText(weight.perWeekKg!, wu).replaceAll(' ', '\u00A0'),
      noteMuted: true,
      spark: weight.trend,
      sparkColor: chartAccent(context),
      bars: false,
      sparkScale: (kg) => weightIn(wu, kg).toStringAsFixed(1),
      spoken: weight.nowKg == null
          ? 'Weight trend, no weigh-ins'
          : 'Weight trend, '
                '${weightIn(wu, weight.nowKg!).toStringAsFixed(1)} $wLabel'
                '${switch (rate) {
                  null => '',
                  '0.00' => ', steady',
                  _ => ', ${weight.perWeekKg! < 0 ? 'down' : 'up'} $rate $wLabel a week',
                }}',
    ),
    tile(
      TrendMetric.expenditure,
      value: spentNow == null ? '–' : '${energyValue(context, spentNow)}',
      suffix: spentNow == null ? 'after a weigh-in' : '$unit\u00A0a\u00A0day',
      spark: spentLine.values,
      sparkColor: chartAccent(context),
      bars: false,
      sparkScale: (kcal) => '${energyValue(context, kcal)}',
      note: estimateFrom,
      noteMuted: true,
      spoken: spentNow == null
          ? 'Expenditure, after a weigh-in'
          : 'Expenditure, ${energyValue(context, spentNow)} $unit a day'
                '${estimateFrom == null ? '' : ', $estimateFrom'}',
    ),
    tile(
      TrendMetric.balance,
      value: balanceMean == null
          ? '–'
          : signedText(energyValue(context, balanceMean).toDouble()),
      suffix: '$unit\u00A0a\u00A0day',
      spark: balanceBars.values,
      // As the page: a surplus in muted ink, a deficit in the accent.
      sparkColor: chartSurplus(context),
      sparkNegativeColor: chartAccent(context),
      note: [?estimateFrom, 'up: surplus · down: deficit'].join(' · '),
      noteMuted: true,
      spoken:
          switch (balanceShown) {
            null => 'Energy balance, no estimate yet',
            0 => 'Energy balance, even',
            final b =>
              'Energy balance, ${b.abs()} $unit a day '
                  '${b < 0 ? 'under' : 'over'}',
          } +
          (estimateFrom == null ? '' : ', $estimateFrom'),
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
        value: waterMean == null ? '–' : '${waterMean.round()}',
        suffix: state.waterGoalMl > 0 ? '/ $waterGoal $waterUnit' : waterUnit,
        spark: water,
        sparkColor: waterColor(context),
        spoken: averageSpoken(
          TrendMetric.water,
          waterMean == null ? null : '${waterMean.round()}',
          state.waterGoalMl > 0 ? '$waterGoal' : null,
          flOz ? 'fluid ounces' : 'ml',
        ),
      ),
    _goalTile(context, state, weight, goal),
    _sidesTile(context, state, measurements),
    _waistTile(context, state, measurements, frame),
  ];
}

/// Goal, left vs right and waist to height with nothing to show yet: the
/// cards below invite the first entry, so Trends leaves them out.
bool _noData(TrendTile t) => switch (t.id) {
  'trends-tile-goal' => t.value == noGoalText,
  'trends-tile-sides' || 'trends-tile-waist' => t.value == '–',
  _ => false,
};

/// Waist to height: the latest ratio and its band; it opens its page.
TrendTile _waistTile(
  BuildContext context,
  TrendsLoaded state,
  List<Measurement>? measurements,
  BodyFrame? frame,
) {
  final text = measurements == null || frame == null
      ? null
      : waistTileText(waistPoints(measurements, frame.heightCm));
  final imperial = state.bodyWeightUnit != BodyWeightUnit.kg;
  return TrendTile(
    id: 'trends-tile-waist',
    label: 'Waist to height',
    value: text?.value ?? '–',
    suffix: text?.suffix ?? 'measure your waist',
    spokenLabel: text == null
        ? 'Waist to height, not measured'
        : 'Waist to height, ${text.value}, ${text.suffix}',
    chart: const SizedBox(),
    onTap: () => openWaistRatio(
      context,
      imperial: imperial,
      rangeDays: state.windowDays,
    ),
  );
}

/// The goal's summary ([goalSummary]) at the range's trend now; it goes
/// where the summary does.
TrendTile _goalTile(
  BuildContext context,
  TrendsLoaded state,
  WeightTrendStats weight,
  TrendsGoal? goal,
) => goalSummaryTile(
  context,
  goalSummary(
    locale: Localizations.localeOf(context).toLanguageTag(),
    unit: state.bodyWeightUnit,
    unitLabel: weightUnitLabel(context, state.bodyWeightUnit),
    today: DateTime.now(),
    plan: goal?.plan,
    history: goal?.history ?? const [],
    pace: goal?.pace,
    targetKg: state.targetWeightKg,
    nowKg: weight.nowKg,
    progress: goal?.progress,
    kgPerDay: kgPerDay30(goal?.progress),
  ),
  id: 'trends-tile-goal',
  unit: state.bodyWeightUnit,
);

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
    spokenLabel:
        '${part.label} left versus right, '
        '${switch (text) {
          null => 'not measured',
          (value: final v, suffix: null) => v.toLowerCase(),
          (value: final v, suffix: final s?) => '$v ${s.replaceAll(' · ', ', ').replaceFirst(units.unit, spokenUnit(units.unit))}',
        }}',
    chart: const SizedBox(),
    onTap: () => openSideCompare(
      context,
      imperial: units.imperial,
      rangeDays: state.windowDays,
    ),
  );
}

/// The on-track streak over all of [days], whatever the range: upstream's
/// card counted it within the range, so 1W capped it at 7.
class _Streak extends StatelessWidget {
  final List<TrackedDayEntity> days;
  final DateTime today;

  const _Streak({required this.days, required this.today});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final palette = paletteOf(context);
    final stats = historyStreak({
      for (final d in days)
        if (d.getCalendarDayRatingColor(context) != scheme.error)
          DateTime(d.day.year, d.day.month, d.day.day),
    }, today);
    // No "0 day streak" to someone who has not had one yet (C3)
    if (stats.longest == 0) return const SizedBox.shrink();
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Dimens.spacing4),
        child: Row(
          children: [
            Icon(
              Icons.local_fire_department_rounded,
              color: textAccent(context),
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

/// The profile's goal and weekly rate, kg a week, as the You tab reads them.
typedef ProfilePace = ({UserWeightGoalEntity goal, double? kgPerWeek});

/// The Goal tile's goal: its progress to the target, the trend now, the
/// goal running, those completed, and the profile's pace.
typedef TrendsGoal = ({
  GoalProgress? progress,
  double? nowKg,
  PhasePlan? plan,
  List<GoalRecord> history,
  ProfilePace? pace,
});
