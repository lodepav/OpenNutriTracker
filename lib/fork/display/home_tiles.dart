import 'dart:math' as math;

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
import 'package:opennutritracker/features/home/presentation/widgets/log_water_dialog.dart';
import 'package:opennutritracker/features/home/presentation/widgets/quick_weight_widget.dart';
import 'package:opennutritracker/features/profile/presentation/utils/profile_display_format.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_service.dart';
import 'package:opennutritracker/fork/adaptive/trend_points.dart';
import 'package:opennutritracker/fork/report/rate_text.dart';
import 'package:opennutritracker/fork/units/energy_text.dart';
import 'package:opennutritracker/generated/l10n.dart';

/// Home's 2×2 tiles (seam S119, MacroFactor's dashboard), in place of the
/// weight, water and fasting chips: the weight trend and its weekly rate,
/// the expenditure estimate, the water drunk and the fast under way. Each
/// opens what its chip did.
class HomeTiles extends StatelessWidget {
  final double weightKg;
  final BodyWeightUnit bodyWeightUnit;
  final int waterMl;
  final int waterGoalMl;
  final Future<List<WeightLogEntity>> Function() loadWeights;
  final Future<List<ExpenditureDay>> Function() loadExpenditure;

  /// The fasting tile, swapped out in tests for want of its bloc.
  final Widget fasting;

  const HomeTiles({
    super.key,
    required this.weightKg,
    required this.bodyWeightUnit,
    required this.waterMl,
    required this.waterGoalMl,
    this.loadWeights = _weights,
    this.loadExpenditure = _expenditure,
    this.fasting = const FastingTile(),
  });

  // Async, so a store not there is a failed future: the tile shows what
  // it has without it.
  static Future<List<WeightLogEntity>> _weights() async =>
      locator<GetWeightLogUsecase>().getAllEntries();

  static Future<List<ExpenditureDay>> _expenditure() async =>
      AdaptiveService.fromLocator().expenditureHistory();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      Dimens.spacing16,
      Dimens.spacing8,
      Dimens.spacing16,
      0,
    ),
    child: Column(
      children: [
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: WeightTile(
                  // Reloaded once a weigh-in changes today's weight.
                  key: ValueKey(weightKg),
                  weightKg: weightKg,
                  unit: bodyWeightUnit,
                  load: loadWeights,
                ),
              ),
              const SizedBox(width: Dimens.spacing8),
              Expanded(child: ExpenditureTile(load: loadExpenditure)),
            ],
          ),
        ),
        const SizedBox(height: Dimens.spacing8),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: WaterTile(ml: waterMl, goalMl: waterGoalMl),
              ),
              const SizedBox(width: Dimens.spacing8),
              Expanded(child: fasting),
            ],
          ),
        ),
      ],
    ),
  );
}

/// One tile: its title, its value with a smaller note after it, and a
/// chart or bar under them.
class HomeTile extends StatelessWidget {
  final String identifier;
  final String title;
  final String value;
  final String? note;
  final Widget? below;
  final VoidCallback? onTap;
  final String? hint;

  const HomeTile({
    super.key,
    required this.identifier,
    required this.title,
    required this.value,
    this.note,
    this.below,
    this.onTap,
    this.hint,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final palette = isDark ? AppPalette.dark : AppPalette.light;
    final textTheme = Theme.of(context).textTheme;
    return Semantics(
      identifier: identifier,
      button: onTap != null,
      hint: hint,
      child: AppCard(
        onTap: onTap,
        padding: const EdgeInsets.all(Dimens.spacing12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: textTheme.labelMedium?.copyWith(color: palette.textMuted),
            ),
            const SizedBox(height: 2),
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: value,
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: palette.textStrong,
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
  }
}

/// The weight trend now, its change over the last week, and the last
/// month of it; the last weigh-in while there is no trend.
class WeightTile extends StatefulWidget {
  final double weightKg;
  final BodyWeightUnit unit;
  final Future<List<WeightLogEntity>> Function() load;

  /// The You tab's (S121) opens the weight history instead of a weigh-in.
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
      final value = formatBodyWeight(
        kg,
        widget.unit,
        kgLabel: s.kgLabel,
        lbLabel: s.lbsLabel,
        stLabel: s.stLabel,
      );
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
      return HomeTile(
        identifier: widget.identifier,
        title: 'Weight trend',
        value: value,
        note: note,
        hint: widget.hint,
        onTap: widget.onTap ?? () => QuickWeightWidget.showWeightDialog(
          context,
          weightKg: widget.weightKg,
          bodyWeightUnit: widget.unit,
        ),
        below: month.length < 2
            ? null
            : Sparkline(
                values: [for (final p in month) p.weightKg],
                color: Theme.of(context).colorScheme.primary,
              ),
      );
    },
  );
}

/// The expenditure estimate today and over the last month; nothing to
/// show before the first weigh-in.
class ExpenditureTile extends StatefulWidget {
  final Future<List<ExpenditureDay>> Function() load;

  const ExpenditureTile({super.key, required this.load});

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
        value: days.isEmpty
            ? '—'
            : '${energyValue(context, days.last.expenditureKcal)}',
        note: days.isEmpty ? 'after a weigh-in' : '${energyUnit(context)}/day',
        below: month.length < 2
            ? null
            : Sparkline(
                values: [for (final d in month) d.expenditureKcal],
                color: Theme.of(context).colorScheme.primary,
              ),
      );
    },
  );
}

class WaterTile extends StatelessWidget {
  final int ml;
  final int goalMl;

  const WaterTile({super.key, required this.ml, required this.goalMl});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final palette = isDark ? AppPalette.dark : AppPalette.light;
    return HomeTile(
      identifier: 'home-water-chip',
      title: 'Water',
      value: '$ml',
      note: '/ $goalMl ml',
      hint: 'Log water',
      onTap: () => showDialog<void>(
        context: context,
        builder: (_) => const LogWaterDialog(),
      ),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final palette = isDark ? AppPalette.dark : AppPalette.light;
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final palette = isDark ? AppPalette.dark : AppPalette.light;
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

/// A line through [values], left to right, filling the tile's width.
class Sparkline extends StatelessWidget {
  final List<double> values;
  final Color color;

  const Sparkline({super.key, required this.values, required this.color});

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox(
      height: 28,
      width: double.infinity,
      child: CustomPaint(painter: _SparklinePainter(values, color)),
    ),
  );
}

class _SparklinePainter extends CustomPainter {
  final List<double> values;
  final Color color;

  _SparklinePainter(this.values, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final low = values.reduce(math.min);
    final high = values.reduce(math.max);
    final span = high - low;
    final path = Path();
    for (final (i, v) in values.indexed) {
      final x = size.width * i / (values.length - 1);
      // A flat line sits in the middle.
      final y = span == 0
          ? size.height / 2
          : size.height - 2 - (size.height - 4) * (v - low) / span;
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_SparklinePainter old) =>
      old.values != values || old.color != color;
}
