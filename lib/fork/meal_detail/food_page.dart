import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:opennutritracker/core/domain/usecase/get_kcal_goal_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_macro_goal_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_tracked_day_usecase.dart';
import 'package:opennutritracker/core/presentation/widgets/app_card.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_service.dart';
import 'package:opennutritracker/fork/display/display_prefs.dart';
import 'package:opennutritracker/fork/off/off_kinds.dart';
import 'package:opennutritracker/fork/units/energy_text.dart';
import 'package:opennutritracker/generated/l10n.dart';

/// Seam S125: the food's page after the canvas's "Food page · A + B". A
/// header with the food's photo or kind, a ring of where the amount's
/// energy comes from, and the day's energy and macros after adding it,
/// the added part lighter and the figure red once over. The amount and
/// Add stay in upstream's bottom sheet, which gains the meal beside Add,
/// the amount on Add and the basket as an icon.

/// Energy per gram of each macro, for the ring's shares.
const _kcalPerG = (carbs: 4.0, fat: 9.0, protein: 4.0);

/// The food's photo, else its kind, else a plain icon; then its name and
/// where it comes from, with its energy per 100 g.
class FoodPageHeader extends StatelessWidget {
  final MealEntity meal;
  final VoidCallback? onPhotoTap;

  const FoodPageHeader({super.key, required this.meal, this.onPhotoTap});

  String _source() {
    final brand = meal.brands;
    if (brand != null && brand.trim().isNotEmpty) return brand.trim();
    return switch (meal.source) {
      MealSourceEntity.off => 'Open Food Facts',
      MealSourceEntity.fdc => 'Base food',
      MealSourceEntity.custom => 'Your food',
      MealSourceEntity.recipe => 'Recipe',
      MealSourceEntity.unknown => 'Food',
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = theme.brightness == Brightness.dark
        ? AppPalette.dark
        : AppPalette.light;
    final photo = meal.mainImageUrl ?? meal.thumbnailImageUrl;
    final Widget thumb;
    if (photo != null && photo.isNotEmpty) {
      thumb = Semantics(
        button: true,
        label: 'Photo of ${meal.name ?? 'the food'}',
        child: InkWell(
          onTap: onPhotoTap,
          borderRadius: Dimens.borderRadiusM,
          child: ClipRRect(
            borderRadius: Dimens.borderRadiusM,
            child: Image.network(
              photo,
              width: 56,
              height: 56,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => _kind(context, palette),
            ),
          ),
        ),
      );
    } else {
      thumb = _kind(context, palette);
    }
    final per100 = meal.nutriments.energyKcal100;
    return Row(
      children: [
        thumb,
        const SizedBox(width: Dimens.spacing12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text(
                  meal.name ?? '',
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                [
                  _source(),
                  if (per100 != null)
                    '${energyText(context, per100)} per 100 g',
                ].join(' · '),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: palette.textMuted,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _kind(BuildContext context, AppPalette palette) => Container(
    width: 56,
    height: 56,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: palette.surfaceMuted,
      borderRadius: Dimens.borderRadiusM,
    ),
    child: switch (OffKinds.emojiFor(meal)) {
      final emoji? => ExcludeSemantics(
        child: Text(emoji, style: const TextStyle(fontSize: 28)),
      ),
      _ => Icon(
        Icons.restaurant_rounded,
        color: Theme.of(context).colorScheme.primary,
      ),
    },
  );
}

/// The amount's energy in a ring split by where it comes from, beside
/// each macro's grams and share of the energy.
class FoodMacroRing extends StatelessWidget {
  final double kcal;
  final double carbs;
  final double fat;
  final double protein;

  const FoodMacroRing({
    super.key,
    required this.kcal,
    required this.carbs,
    required this.fat,
    required this.protein,
  });

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final theme = Theme.of(context);
    final palette = theme.brightness == Brightness.dark
        ? AppPalette.dark
        : AppPalette.light;
    final energy = (
      carbs: carbs * _kcalPerG.carbs,
      fat: fat * _kcalPerG.fat,
      protein: protein * _kcalPerG.protein,
    );
    final sum = energy.carbs + energy.fat + energy.protein;
    int share(double part) => sum > 0 ? (part / sum * 100).round() : 0;
    Widget line(String name, double grams, double part, Color color) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: Dimens.spacing8),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '${grams.round()} g ',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  TextSpan(text: '$name · ${share(part)}%'),
                ],
              ),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: palette.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
    return AppCard(
      padding: const EdgeInsets.all(Dimens.spacing16),
      child: Row(
        children: [
          SizedBox(
            width: 104,
            height: 104,
            child: CustomPaint(
              painter: _RingPainter(
                parts: inMacroOrder(
                  carbs: (energy.carbs, palette.carbs),
                  fat: (energy.fat, palette.fat),
                  protein: (energy.protein, palette.protein),
                ),
                track: palette.surfaceMuted,
              ),
              child: Center(
                child: MergeSemantics(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${energyValue(context, kcal)}',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        energyUnit(context),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: palette.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: Dimens.spacing16),
          Expanded(
            child: Column(
              children: inMacroOrder(
                carbs: line(s.carbsLabel, carbs, energy.carbs, palette.carbs),
                fat: line(s.fatLabel, fat, energy.fat, palette.fat),
                protein: line(
                  s.proteinLabel,
                  protein,
                  energy.protein,
                  palette.protein,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final List<(double, Color)> parts;
  final Color track;

  _RingPainter({required this.parts, required this.track});

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 12.0;
    final rect = Rect.fromCircle(
      center: size.center(Offset.zero),
      radius: size.shortestSide / 2 - stroke / 2,
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    canvas.drawArc(rect, 0, 2 * math.pi, false, paint..color = track);
    final sum = parts.fold(0.0, (a, p) => a + p.$1);
    if (sum <= 0) return;
    var start = -math.pi / 2;
    for (final (value, color) in parts) {
      final sweep = value / sum * 2 * math.pi;
      canvas.drawArc(rect, start, sweep, false, paint..color = color);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.track != track ||
      old.parts.length != parts.length ||
      [
        for (var i = 0; i < parts.length; i++) parts[i] != old.parts[i],
      ].any((changed) => changed);
}

/// What a day has logged and its goals, energy in kcal and macros in
/// grams.
typedef DayTotals = ({
  ({double kcal, double carbs, double fat, double protein}) eaten,
  ({double kcal, double carbs, double fat, double protein}) goal,
});

/// [day]'s tracked totals and goals; a day with nothing logged yet has
/// the goals its first log will set (the profile's, at its weekday shift).
Future<DayTotals> loadDayTotals(DateTime day) async {
  final tracked = await locator<GetTrackedDayUsecase>().getTrackedDay(day);
  final kcalGoal =
      tracked?.calorieGoal ??
      await forkGoalOnDay(
        await locator<GetKcalGoalUsecase>().getKcalGoal(),
        day,
      );
  final macros = locator<GetMacroGoalUsecase>();
  return (
    eaten: (
      kcal: tracked?.caloriesTracked ?? 0,
      carbs: tracked?.carbsTracked ?? 0,
      fat: tracked?.fatTracked ?? 0,
      protein: tracked?.proteinTracked ?? 0,
    ),
    goal: (
      kcal: kcalGoal,
      carbs: tracked?.carbsGoal ?? await macros.getCarbsGoal(kcalGoal),
      fat: tracked?.fatGoal ?? await macros.getFatsGoal(kcalGoal),
      protein: tracked?.proteinGoal ?? await macros.getProteinsGoal(kcalGoal),
    ),
  );
}

/// The day's energy and macros once the amount is added: each a figure
/// over its goal and a bar of what was eaten, the amount lighter after
/// it; red once over. Nothing until the day is read, or when it can't be.
/// The four columns in one row, or two rows of two at large text, where a
/// quarter of the width breaks "protein" (A6).
List<List<Widget>> _afterAddingRows(BuildContext context, List<Widget> cells) =>
    MediaQuery.textScalerOf(context).scale(10) > 13
    ? [cells.sublist(0, 2), cells.sublist(2)]
    : [cells];

class TodayAfterAdding extends StatefulWidget {
  final DateTime day;
  final double kcal;
  final double carbs;
  final double fat;
  final double protein;
  final Future<DayTotals> Function(DateTime day) load;

  const TodayAfterAdding({
    super.key,
    required this.day,
    required this.kcal,
    required this.carbs,
    required this.fat,
    required this.protein,
    this.load = loadDayTotals,
  });

  @override
  State<TodayAfterAdding> createState() => _TodayAfterAddingState();
}

class _TodayAfterAddingState extends State<TodayAfterAdding> {
  late Future<DayTotals> _totals = widget.load(widget.day);

  @override
  void didUpdateWidget(TodayAfterAdding old) {
    super.didUpdateWidget(old);
    if (old.day != widget.day) _totals = widget.load(widget.day);
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final theme = Theme.of(context);
    final palette = theme.brightness == Brightness.dark
        ? AppPalette.dark
        : AppPalette.light;
    return FutureBuilder<DayTotals>(
      future: _totals,
      builder: (context, snapshot) {
        final totals = snapshot.data;
        if (totals == null) return const SizedBox.shrink();
        Widget column({
          required String label,
          required String figure,
          required String goal,
          required double eaten,
          required double added,
          required double target,
          required Color color,
          required String spoken,
        }) {
          final over = target > 0 && eaten + added > target;
          final shown = over ? palette.fat : color;
          final scale = math.max(target, eaten + added);
          double part(double v) => scale > 0 ? (v / scale).clamp(0, 1) : 0;
          return Expanded(
            // Words, not "428 / 465 carbs g" (A5).
            child: Semantics(
              label: '$figure of $goal $spoken${over ? ', over' : ''}',
              excludeSemantics: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: figure,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: over
                                ? palette.fat
                                : theme.colorScheme.onSurface,
                          ),
                        ),
                        TextSpan(text: ' / $goal'),
                      ],
                    ),
                    // Wraps at large text rather than cut the goal (A6).
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: palette.textMuted,
                    ),
                  ),
                  const SizedBox(height: 4),
                  ExcludeSemantics(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: SizedBox(
                        height: 5,
                        child: ColoredBox(
                          color: palette.surfaceMuted,
                          child: Row(
                            children: [
                              // A part that rounds to nothing is left out:
                              // a zero flex would lay out unbounded.
                              for (final (flex, fill) in [
                                (part(eaten), shown),
                                (part(added), shown.withValues(alpha: 0.45)),
                                (
                                  (1 - part(eaten) - part(added)).clamp(0, 1),
                                  null,
                                ),
                              ])
                                if ((flex * 1000).round() > 0)
                                  Flexible(
                                    flex: (flex * 1000).round(),
                                    child: ColoredBox(
                                      color: fill ?? Colors.transparent,
                                      child: const SizedBox.expand(),
                                    ),
                                  ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    label,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: palette.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        Widget macro(
          String label,
          double eaten,
          double added,
          double goal,
          Color color,
        ) => column(
          label: '$label g',
          figure: '${(eaten + added).round()}',
          goal: '${goal.round()}',
          eaten: eaten,
          added: added,
          target: goal,
          color: color,
          spoken: 'grams ${label.toLowerCase()}',
        );

        final e = totals.eaten, g = totals.goal;
        return AppCard(
          padding: const EdgeInsets.all(Dimens.spacing16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Today after adding',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: Dimens.spacing8),
              for (final row in _afterAddingRows(context, [
                column(
                  label: energyUnit(context),
                  figure: '${energyValue(context, e.kcal + widget.kcal)}',
                  goal: '${energyValue(context, g.kcal)}',
                  eaten: e.kcal,
                  added: widget.kcal,
                  target: g.kcal,
                  color: theme.colorScheme.primary,
                  spoken: energyUnit(context),
                ),
                ...inMacroOrder(
                  carbs: macro(
                    s.carbsLabel,
                    e.carbs,
                    widget.carbs,
                    g.carbs,
                    palette.carbs,
                  ),
                  fat: macro(s.fatLabel, e.fat, widget.fat, g.fat, palette.fat),
                  protein: macro(
                    s.proteinLabel,
                    e.protein,
                    widget.protein,
                    g.protein,
                    palette.protein,
                  ),
                ),
              ]))
                Padding(
                  padding: const EdgeInsets.only(bottom: Dimens.spacing8),
                  child: Row(
                    spacing: Dimens.spacing12,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: row,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
