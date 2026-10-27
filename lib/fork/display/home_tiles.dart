import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:opennutritracker/core/domain/entity/body_weight_unit_entity.dart';
import 'package:opennutritracker/core/domain/entity/weight_log_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_weight_log_usecase.dart';
import 'package:opennutritracker/core/presentation/widgets/app_card.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/calc/unit_calc.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/core/utils/navigation_options.dart';
import 'package:opennutritracker/features/fasting/presentation/bloc/fasting_bloc.dart';
import 'package:opennutritracker/fork/display/display_prefs.dart';
import 'package:opennutritracker/fork/display/home_trend_tiles.dart';
import 'package:opennutritracker/fork/layout/home_layout.dart';
import 'package:opennutritracker/fork/layout/layout_store.dart';
import 'package:opennutritracker/features/home/presentation/widgets/log_water_dialog.dart';
import 'package:opennutritracker/features/home/presentation/widgets/quick_weight_widget.dart';
import 'package:opennutritracker/features/trends/presentation/trends_page.dart'
    show openTrendFromHome;
import 'package:opennutritracker/fork/adaptive/adaptive_service.dart';
import 'package:opennutritracker/fork/adaptive/trend_points.dart';
import 'package:opennutritracker/fork/report/rate_text.dart';
import 'package:opennutritracker/fork/trends/trend_stats.dart' show TrendMetric;
import 'package:opennutritracker/fork/trends/trends_widgets.dart'
    show Sparkline;
import 'package:opennutritracker/fork/units/energy_text.dart';
import 'package:opennutritracker/fork/units/weight_text.dart' show weightText;
import 'package:opennutritracker/generated/l10n.dart';

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
          onTap: () => openTrend(context, TrendMetric.expenditure),
        ),
        if (DisplayPrefs.showWater.value)
          'water': WaterTile(
            ml: waterMl,
            goalMl: waterGoalMl,
            onTap: () => openTrend(context, TrendMetric.water),
          ),
        if (DisplayPrefs.showFasting.value) 'fasting': fasting,
      };
      final added = {
        for (final id in homeTrendTileNames.keys)
          if (!addable([id], layout).contains(id)) id,
      };
      if (added.isEmpty) return _grid(arranged(own, layout));
      return HomeTrendTiles(
        ids: added,
        loadExpenditure: loadExpenditure,
        homeLoads: homeLoads,
        builder: (trends) => _grid(arranged({...own, ...trends}, layout)),
      );
    },
  );

  Widget _grid(List<Widget> tiles) {
    if (tiles.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Dimens.spacing16,
        0,
        Dimens.spacing16,
        0,
      ),
      child: Column(
        children: [
          for (var i = 0; i < tiles.length; i += 2)
            Padding(
              padding: const EdgeInsets.only(top: Dimens.spacing8),
              child: IntrinsicHeight(
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

/// One tile: its title, its value with a smaller note after it, and a
/// chart or bar under them.
class HomeTile extends StatelessWidget {
  final String identifier;
  final String title;
  final String value;
  final String? note;
  final Color? valueColor;
  final Widget? below;
  final VoidCallback? onTap;
  final String? hint;

  /// A + in the corner that logs (a weigh-in, water), [actionTooltip] its
  /// name; beside the card rather than in it, a button in a button being
  /// one target to a screen reader.
  final VoidCallback? onAction;
  final String? actionTooltip;

  const HomeTile({
    super.key,
    required this.identifier,
    required this.title,
    required this.value,
    this.note,
    this.valueColor,
    this.below,
    this.onTap,
    this.hint,
    this.onAction,
    this.actionTooltip,
  });

  @override
  Widget build(BuildContext context) {
    final palette = paletteOf(context);
    final textTheme = Theme.of(context).textTheme;
    final card = Semantics(
      identifier: identifier,
      button: onTap != null,
      hint: hint,
      child: AppCard(
        onTap: onTap,
        padding: const EdgeInsets.all(Dimens.spacing12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              // Clear of the + in the corner.
              padding: EdgeInsetsDirectional.only(
                end: onAction == null ? 0 : 32,
              ),
              child: Text(
                title,
                style: textTheme.labelMedium?.copyWith(
                  color: palette.textMuted,
                ),
              ),
            ),
            const SizedBox(height: 2),
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: value,
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: valueColor ?? palette.textStrong,
                    ),
                  ),
                  if (note != null)
                    TextSpan(
                      text: ' $note',
                      style: textTheme.labelSmall?.copyWith(
                        color: palette.textMuted,
                      ),
                    ),
                ],
              ),
            ),
            if (below != null) ...[
              const SizedBox(height: Dimens.spacing8),
              below!,
            ],
          ],
        ),
      ),
    );
    if (onAction == null) return card;
    return Stack(
      fit: StackFit.passthrough,
      children: [
        card,
        PositionedDirectional(
          top: 0,
          end: 0,
          child: IconButton(
            key: Key('$identifier-add'),
            tooltip: actionTooltip,
            icon: const Icon(Icons.add_rounded),
            onPressed: onAction,
          ),
        ),
      ],
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

  const WeightTile({
    super.key,
    required this.weightKg,
    required this.unit,
    required this.load,
    this.identifier = 'home-weight-chip',
    this.hint = 'Log a weigh-in',
    this.onTap,
  });

  @override
  State<WeightTile> createState() => _WeightTileState();
}

class _WeightTileState extends State<WeightTile> {
  late final _entries = widget.load();

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
      final s = S.of(context);
      final value = weightText(kg, widget.unit);
      String? note;
      if (trend.length > 7) {
        final kgPerWeek =
            trend.last.weightKg - trend[trend.length - 8].weightKg;
        // Stones are too coarse for a week's change: pounds.
        note = widget.unit == BodyWeightUnit.kg
            ? '· ${signedRate(kgPerWeek)} ${s.kgLabel}/wk'
            : '· ${signedRate(UnitCalc.kgToLbs(kgPerWeek))} ${s.lbsLabel}/wk';
      }
      final month = trend.length > 30
          ? trend.sublist(trend.length - 30)
          : trend;
      void weighIn() => QuickWeightWidget.showWeightDialog(
        context,
        weightKg: widget.weightKg,
        bodyWeightUnit: widget.unit,
      );
      return HomeTile(
        identifier: widget.identifier,
        title: 'Weight trend',
        value: value,
        note: note,
        hint: widget.hint,
        onTap: widget.onTap ?? weighIn,
        onAction: weighIn,
        actionTooltip: 'Log a weigh-in',
        below: month.length < 2
            ? null
            : Sparkline(
                values: [for (final p in month) p.weightKg],
                color: Theme.of(context).colorScheme.primary,
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

  const ExpenditureTile({super.key, required this.load, this.onTap});

  @override
  State<ExpenditureTile> createState() => _ExpenditureTileState();
}

class _ExpenditureTileState extends State<ExpenditureTile> {
  late final _days = widget.load();

  @override
  Widget build(BuildContext context) => FutureBuilder<List<ExpenditureDay>>(
    future: _days,
    builder: (context, snapshot) {
      final days = snapshot.data ?? const [];
      final month = days.length > 30 ? days.sublist(days.length - 30) : days;
      return HomeTile(
        identifier: 'home-expenditure-tile',
        title: 'Expenditure',
        hint: widget.onTap == null ? null : 'Open the expenditure trend',
        onTap: widget.onTap,
        value: days.isEmpty
            ? '—'
            : '${energyValue(context, days.last.expenditureKcal)}',
        note: days.isEmpty ? 'after a weigh-in' : '${energyUnit(context)}/day',
        below: month.length < 2
            ? null
            : Sparkline(
                values: [for (final d in month) d.expenditureKcal],
                color: Theme.of(context).colorScheme.primary,
                bars: false,
              ),
      );
    },
  );
}

class WaterTile extends StatelessWidget {
  final int ml;
  final int goalMl;

  /// Opens the water trend; water is logged from the + (or the tap
  /// without one).
  final VoidCallback? onTap;

  const WaterTile({
    super.key,
    required this.ml,
    required this.goalMl,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final palette = paletteOf(context);
    void logWater() => showDialog<void>(
      context: context,
      builder: (_) => const LogWaterDialog(),
    );
    return HomeTile(
      identifier: 'home-water-chip',
      title: 'Water',
      value: '$ml',
      note: '/ $goalMl ml',
      hint: onTap == null ? 'Log water' : 'Open the water trend',
      onTap: onTap ?? logWater,
      onAction: logWater,
      actionTooltip: 'Log water',
      below: TileBar(
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
    return HomeTile(
      identifier: 'home-fasting-chip',
      title: 'Fasting',
      value: active == null ? 'Not fasting' : _hoursMinutes(active.remaining),
      note: active == null ? null : 'left',
      hint: 'Open fasting',
      onTap: () =>
          Navigator.of(context).pushNamed(NavigationOptions.fastingRoute),
      below: active == null
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
