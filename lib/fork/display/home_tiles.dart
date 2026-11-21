import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:opennutritracker/core/domain/entity/body_weight_unit_entity.dart';
import 'package:opennutritracker/core/domain/entity/weight_log_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_weight_log_usecase.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/calc/unit_calc.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/core/utils/navigation_options.dart';
import 'package:opennutritracker/features/fasting/presentation/bloc/fasting_bloc.dart';
import 'package:opennutritracker/fork/display/contrast.dart';
import 'package:opennutritracker/fork/display/display_prefs.dart';
import 'package:opennutritracker/fork/display/home_trend_tiles.dart';
import 'package:opennutritracker/fork/layout/home_layout.dart';
import 'package:opennutritracker/fork/layout/layout_store.dart';
import 'package:opennutritracker/fork/screens/home/home_loads.dart';
import 'package:opennutritracker/features/home/presentation/widgets/log_water_dialog.dart';
import 'package:opennutritracker/features/home/presentation/widgets/quick_weight_widget.dart';
import 'package:opennutritracker/fork/screens/trends/trends_page.dart'
    show openTrendFromHome;
import 'package:opennutritracker/fork/adaptive/adaptive_service.dart';
import 'package:opennutritracker/fork/adaptive/trend_points.dart';
import 'package:opennutritracker/fork/report/rate_text.dart';
import 'package:opennutritracker/fork/trends/trend_stats.dart' show TrendMetric;
import 'package:opennutritracker/fork/trends/trends_widgets.dart'
    show Sparkline, TrendTile;
import 'package:opennutritracker/fork/units/energy_text.dart';
import 'package:opennutritracker/fork/units/weight_text.dart' show weightText;

/// Home's 2×2 tiles (seam S119, MacroFactor's dashboard), in place of the
/// weight, water and fasting chips: the weight trend and its weekly rate,
/// the expenditure estimate, the water drunk and the fast under way. Each
/// opens the page its Trends tile opens (S145); logging moves to a + in
/// the weight and water tiles' corner.
class HomeTiles extends StatelessWidget {
  final double weightKg;
  final BodyWeightUnit bodyWeightUnit;
  final int waterMl;
  final int waterGoalMl;

  /// Water in fl oz, as the food units ask (#1306).
  final bool usesImperialUnits;
  final Future<List<WeightLogEntity>> Function() loadWeights;
  final Future<List<ExpenditureDay>> Function() loadExpenditure;

  /// The fasting tile, swapped out in tests for want of its bloc.
  final Widget fasting;

  /// Opens a metric's Trends page, swapped out in tests.
  final void Function(BuildContext context, TrendMetric metric) openTrend;

  /// Home's reloads, for Trends' tiles added here; the app's from the
  /// locator.
  final Stream<Object?>? homeLoads;

  const HomeTiles({
    super.key,
    required this.weightKg,
    required this.bodyWeightUnit,
    required this.waterMl,
    required this.waterGoalMl,
    this.usesImperialUnits = false,
    this.loadWeights = _weights,
    this.loadExpenditure = _expenditure,
    this.fasting = const FastingTile(),
    this.openTrend = openTrendFromHome,
    this.homeLoads,
  });

  // Async, so a store not there is a failed future: the tile shows what
  // it has without it.
  static Future<List<WeightLogEntity>> _weights() async =>
      locator<GetWeightLogUsecase>().getAllEntries();

  static Future<List<ExpenditureDay>> _expenditure() async =>
      AdaptiveService.fromLocator().expenditureHistory();

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      DisplayPrefs.showWater,
      DisplayPrefs.showFasting,
      LayoutStore.current(homeTilesKey),
    ]),
    builder: (context, _) {
      // Water or fasting hidden in Settings (S144) is not a tile; the
      // rest go two to a row as arranged (S162), one alone spanning it,
      // with Trends' tiles switched on there.
      final layout = LayoutStore.current(homeTilesKey).value;
      // As Trends': past 1.5x text two tiles to a row split their units.
      final perRow = MediaQuery.textScalerOf(context).scale(10) > 15 ? 1 : 2;
      final own = {
        'weight': WeightTile(
          // Reloaded once a weigh-in changes today's weight.
          key: ValueKey(weightKg),
          weightKg: weightKg,
          unit: bodyWeightUnit,
          load: loadWeights,
          hint: 'Open the weight trend',
          onTap: () => openTrend(context, TrendMetric.weight),
        ),
        'expenditure': ExpenditureTile(
          load: loadExpenditure,
          homeLoads: homeLoads,
          onTap: () => openTrend(context, TrendMetric.expenditure),
        ),
        if (DisplayPrefs.showWater.value)
          'water': WaterTile(
            ml: waterMl,
            goalMl: waterGoalMl,
            usesImperialUnits: usesImperialUnits,
            onTap: () => openTrend(context, TrendMetric.water),
          ),
        if (DisplayPrefs.showFasting.value) 'fasting': fasting,
      };
      final added = {
        for (final id in homeTrendTileNames.keys)
          if (!addable([id], layout).contains(id)) id,
      };
      if (added.isEmpty) return _grid(arranged(own, layout), perRow);
      return HomeTrendTiles(
        ids: added,
        loadExpenditure: loadExpenditure,
        homeLoads: homeLoads,
        builder: (trends) =>
            _grid(arranged({...own, ...trends}, layout), perRow),
      );
    },
  );

  Widget _grid(List<Widget> tiles, int perRow) {
    if (tiles.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Dimens.spacing16,
        0,
        Dimens.spacing16,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < tiles.length; i += perRow)
            Padding(
              padding: const EdgeInsets.only(top: Dimens.spacing8),
              child: perRow == 1
                  ? tiles[i]
                  : IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: tiles[i]),
                          if (i + 1 < tiles.length) ...[
                            const SizedBox(width: Dimens.spacing8),
                            Expanded(child: tiles[i + 1]),
                          ],
                        ],
                      ),
                    ),
            ),
        ],
      ),
    );
  }
}

/// The weight trend now, its change over the last week, and the last
/// month of it; the last weigh-in while there is no trend.
class WeightTile extends StatefulWidget {
  final double weightKg;
  final BodyWeightUnit unit;
  final Future<List<WeightLogEntity>> Function() load;

  /// Home's opens the weight trend, the You tab's (S121) the weight
  /// history; a weigh-in without one, and always from the +.
  final String identifier;
  final String hint;
  final VoidCallback? onTap;

  /// A new value loads the weigh-ins again, the old trend shown meanwhile;
  /// a new key instead would flash [weightKg] and replace TalkBack's node.
  final Object? reload;

  const WeightTile({
    super.key,
    required this.weightKg,
    required this.unit,
    required this.load,
    this.reload,
    this.identifier = 'home-weight-chip',
    this.hint = 'Weigh in',
    this.onTap,
  });

  @override
  State<WeightTile> createState() => _WeightTileState();
}

class _WeightTileState extends State<WeightTile> {
  late var _entries = widget.load();

  @override
  void didUpdateWidget(WeightTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.reload, oldWidget.reload)) _entries = widget.load();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<WeightLogEntity>>(
    future: _entries,
    builder: (context, snapshot) {
      final now = DateTime.now();
      final trend = trendPoints(
        snapshot.data ?? const [],
        until: DateTime(now.year, now.month, now.day),
      );
      final kg = trend.isEmpty ? widget.weightKg : trend.last.weightKg;
      final value = weightText(kg, widget.unit);
      final kgPerWeek = trend.length > 7
          ? trend.last.weightKg - trend[trend.length - 8].weightKg
          : null;
      final month = trend.length > 30
          ? trend.sublist(trend.length - 30)
          : trend;
      void weighIn() => QuickWeightWidget.showWeightDialog(
        context,
        weightKg: widget.weightKg,
        bodyWeightUnit: widget.unit,
      );
      return TrendTile(
        id: widget.identifier,
        label: 'Weight trend',
        value: value,
        // The last 7 days by name, as Weight history's "per week" is over
        // its range; its own line, as it never fits beside the trend.
        note: kgPerWeek == null
            ? null
            : weeklyRateText(
                kgPerWeek,
                widget.unit,
              ).replaceFirst(' a week', ' in 7 days').replaceAll(' ', '\u00A0'),
        noteMuted: true,
        spokenLabel: weightSpoken(
          value,
          kgPerWeek,
          widget.unit,
        ).replaceFirst(' a week', ' in 7 days'),
        hint: widget.hint,
        onTap: widget.onTap ?? weighIn,
        onAction: weighIn,
        actionTooltip: 'Weigh in',
        chart: month.length < 2
            ? null
            : Sparkline(
                values: [for (final p in month) p.weightKg],
                color: chartAccent(context),
                bars: false,
              ),
      );
    },
  );
}

/// The expenditure estimate today and over the last month; nothing to
/// show before the first weigh-in.
class ExpenditureTile extends StatefulWidget {
  final Future<List<ExpenditureDay>> Function() load;
  final VoidCallback? onTap;

  /// Home's loads, for tests; the app's from the HomeBloc.
  final Stream<Object?>? homeLoads;

  const ExpenditureTile({
    super.key,
    required this.load,
    this.onTap,
    this.homeLoads,
  });

  @override
  State<ExpenditureTile> createState() => _ExpenditureTileState();
}

class _ExpenditureTileState extends State<ExpenditureTile> {
  late var _days = widget.load();

  // A weigh-in or a past day edited in the Diary reaches Home as a load.
  late final StreamSubscription<Object?> _homeLoads;

  @override
  void initState() {
    super.initState();
    _homeLoads = (widget.homeLoads ?? homeLoads()).listen(
      (_) => setState(() {
        _days = widget.load()..ignore();
      }),
    );
  }

  @override
  void dispose() {
    _homeLoads.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<ExpenditureDay>>(
    future: _days,
    builder: (context, snapshot) {
      final days = snapshot.data ?? const [];
      final month = days.length > 30 ? days.sublist(days.length - 30) : days;
      return TrendTile(
        id: 'home-expenditure-tile',
        label: 'Expenditure',
        hint: widget.onTap == null ? null : 'Open the expenditure trend',
        onTap: widget.onTap,
        value: days.isEmpty
            ? '—'
            : '${energyValue(context, days.last.expenditureKcal)}',
        suffix: days.isEmpty
            ? 'after a weigh-in'
            : '${energyUnit(context)} a day',
        spokenLabel: expenditureSpoken(
          days.isEmpty ? null : energyValue(context, days.last.expenditureKcal),
          energyUnit(context),
        ),
        chart: month.length < 2
            ? null
            : Sparkline(
                values: [for (final d in month) d.expenditureKcal],
                color: chartAccent(context),
                bars: false,
              ),
      );
    },
  );
}

class WaterTile extends StatelessWidget {
  final int ml;
  final int goalMl;

  /// Shown in fl oz, and logged in it (#1306).
  final bool usesImperialUnits;

  /// Opens the water trend; water is logged from the + (or the tap
  /// without one).
  final VoidCallback? onTap;

  const WaterTile({
    super.key,
    required this.ml,
    required this.goalMl,
    this.usesImperialUnits = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final palette = paletteOf(context);
    void logWater() => showDialog<void>(
      context: context,
      builder: (_) => LogWaterDialog(usesImperialUnits: usesImperialUnits),
    );
    String shown(int ml) => usesImperialUnits
        ? '${UnitCalc.mlToFlOz(ml.toDouble()).round()}'
        : '$ml';
    return TrendTile(
      id: 'home-water-chip',
      label: 'Water',
      value: shown(ml),
      suffix: '/ ${shown(goalMl)} ${usesImperialUnits ? 'fl oz' : 'ml'}',
      spokenLabel:
          'Water, ${shown(ml)} of ${shown(goalMl)} '
          '${usesImperialUnits ? 'fluid ounces' : 'milliliters'}',
      hint: onTap == null ? 'Log water' : 'Open the water trend',
      onTap: onTap ?? logWater,
      onAction: logWater,
      actionTooltip: 'Log water',
      chart: TileBar(
        value: goalMl <= 0 ? 0 : ml / goalMl,
        color: palette.protein,
      ),
    );
  }
}

/// The fast under way and how long is left of it, or that there is none.
class FastingTile extends StatelessWidget {
  const FastingTile({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => locator<FastingBloc>()..add(const FastingLoadRequested()),
    child: BlocBuilder<FastingBloc, FastingState>(
      builder: (context, state) => FastingTileView(state: state),
    ),
  );
}

class FastingTileView extends StatelessWidget {
  final FastingState state;

  const FastingTileView({super.key, required this.state});

  // Minutes resolution: seconds would twitch every tick.
  static String _hoursMinutes(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    return h == 0 ? '${m}m' : '${h}h ${m}m';
  }

  @override
  Widget build(BuildContext context) {
    final palette = paletteOf(context);
    final active = state is FastingActive ? state as FastingActive : null;
    return TrendTile(
      id: 'home-fasting-chip',
      label: 'Fasting',
      value: active == null ? 'Not fasting' : _hoursMinutes(active.remaining),
      suffix: active == null ? null : 'left',
      spokenLabel: fastingSpoken(active?.remaining),
      hint: 'Open fasting',
      onTap: () =>
          Navigator.of(context).pushNamed(NavigationOptions.fastingRoute),
      chart: active == null
          ? null
          : TileBar(
              value: active.target.inSeconds <= 0
                  ? 0
                  : active.elapsed.inSeconds / active.target.inSeconds,
              color: palette.textMuted,
            ),
    );
  }
}

/// "Weight trend, 87.1 kg, down 0.16 kg a week": [kgPerWeek] the week's
/// change, null before a week of trend.
String weightSpoken(String weight, double? kgPerWeek, BodyWeightUnit unit) =>
    'Weight trend, $weight'
    '${kgPerWeek == null ? '' : ', ${weeklyRateSpoken(kgPerWeek, unit)}'}';

/// "Expenditure, 3045 kcal a day", or that it waits for a weigh-in.
String expenditureSpoken(int? value, String unit) => value == null
    ? 'Expenditure, after a weigh-in'
    : 'Expenditure, $value $unit a day';

/// "Fasting, 11 hours 30 minutes left", or that no fast is under way.
String fastingSpoken(Duration? remaining) {
  if (remaining == null) return 'Fasting, no fast under way';
  String count(int n, String unit) => '$n $unit${n == 1 ? '' : 's'}';
  final h = remaining.inHours;
  final m = count(remaining.inMinutes.remainder(60), 'minute');
  return 'Fasting, ${h == 0 ? m : '${count(h, 'hour')} $m'} left';
}

/// A tile's thin progress bar.
class TileBar extends StatelessWidget {
  final double value;
  final Color color;

  const TileBar({super.key, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    final palette = paletteOf(context);
    // The tile's text says it already: no bare percentage read out too.
    return ExcludeSemantics(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: LinearProgressIndicator(
          value: value.clamp(0.0, 1.0),
          minHeight: 6,
          color: color,
          backgroundColor: palette.surfaceMuted,
        ),
      ),
    );
  }
}
