import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:opennutritracker/core/domain/usecase/get_kcal_goal_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_macro_goal_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_tracked_day_usecase.dart';
import 'package:opennutritracker/core/presentation/widgets/app_card.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/meal_detail/presentation/widgets/meal_detail_nutriments_table.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_service.dart';
import 'package:opennutritracker/fork/display/day_totals_card.dart'
    show dayTotalLabel;
import 'package:opennutritracker/fork/display/display_prefs.dart';
import 'package:opennutritracker/fork/off/off_kinds.dart';
import 'package:opennutritracker/fork/trends/trends_widgets.dart'
    show keepUnits;
import 'package:opennutritracker/fork/units/energy_text.dart';

/// Seam S125: the food's page after the canvas's "Food page · A + B". A
/// header with the food's photo or kind, a ring of where the amount's
/// energy comes from, and the day's energy and macros after adding it,
/// the added part lighter. The amount and Add stay in upstream's bottom
/// sheet, which gains the meal beside Add, the amount on Add and the
/// basket as an icon; above 1.5x text the amount and the meal move onto
/// the page and only Add and the basket stay pinned ([FoodSheetPart]).

/// Which part of upstream's bottom sheet an instance shows: the whole of
/// it, the amount and meal on the page, or the pinned bar with Add.
enum FoodSheetPart { all, amount, addBar }

/// Whether the food page puts the amount on the page and pins only Add:
/// above 1.5x text, as Home, Trends and the Diary change their layouts, and
/// on a short window (a phone in landscape), where the whole sheet would
/// leave the page a strip.
bool foodPageInline(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(10) > 15 ||
    MediaQuery.sizeOf(context).height < 500;

/// [child], telling [onHeight] its height whenever a layout changes it: the
/// pinned sheet's, so the page's end scrolls clear of it.
class ReportHeight extends SingleChildRenderObjectWidget {
  final ValueChanged<double> onHeight;

  const ReportHeight({super.key, required this.onHeight, super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderReportHeight(onHeight);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) =>
      (renderObject as _RenderReportHeight).onHeight = onHeight;
}

class _RenderReportHeight extends RenderProxyBox {
  ValueChanged<double> onHeight;
  double? _reported;

  _RenderReportHeight(this.onHeight);

  @override
  void performLayout() {
    super.performLayout();
    final height = size.height;
    if (height == _reported) return;
    _reported = height;
    // after the frame: a rebuild can't be asked for during layout
    WidgetsBinding.instance.addPostFrameCallback((_) => onHeight(height));
  }
}

/// Energy per gram of each macro, for the ring's shares.
const _kcalPerG = (carbs: 4.0, fat: 9.0, protein: 4.0);

/// [part]'s share of [total] energy as a whole percent; 0 when there is
/// no energy to share.
int macroEnergyShare(double part, double total) =>
    total > 0 ? (part / total * 100).round() : 0;

/// A macro's line as read aloud: "Protein, 19 g, 79% of energy", or
/// "Fat, not known" when the food lacks it.
String macroSpokenLabel(String name, double? grams, int share) => grams == null
    ? '$name, not known'
    : '$name, ${grams.round()} g, $share% of energy';

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
    final palette = paletteOf(context);
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
              // decoded at the size shown, not the photo's own
              // shortcut: decoded 56 dp wide, so a landscape photo's short
              // side is a little under the square; decode by the short
              // side if it looks soft.
              cacheWidth: (56 * MediaQuery.devicePixelRatioOf(context)).round(),
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
    final energy = per100 == null
        ? null
        : '${energyText(context, per100)} per 100 ${meal.isLiquid ? 'ml' : 'g'}';
    return Row(
      children: [
        thumb,
        const SizedBox(width: Dimens.spacing12),
        Expanded(
          // One heading read as sentences, not the lines run together (A5).
          child: Semantics(
            header: true,
            label: [meal.name ?? '', _source(), ?energy].join('. '),
            excludeSemantics: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  meal.name ?? '',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  [_source(), ?energy].join(' · '),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: palette.textMuted,
                  ),
                ),
              ],
            ),
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
/// each macro's grams and share of the energy. A value the food lacks is
/// null and shows as missing, not as 0.
class FoodMacroRing extends StatelessWidget {
  final double? kcal;
  final double? carbs;
  final double? fat;
  final double? protein;

  const FoodMacroRing({
    super.key,
    required this.kcal,
    required this.carbs,
    required this.fat,
    required this.protein,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = paletteOf(context);
    final energy = (
      carbs: (carbs ?? 0) * _kcalPerG.carbs,
      fat: (fat ?? 0) * _kcalPerG.fat,
      protein: (protein ?? 0) * _kcalPerG.protein,
    );
    final sum = energy.carbs + energy.fat + energy.protein;
    int share(double part) => macroEnergyShare(part, sum);
    final large = MediaQuery.textScalerOf(context).scale(10) > 15;
    Widget line(String name, double? grams, double part, Color color) =>
        Semantics(
          container: true,
          label: macroSpokenLabel(name, grams, share(part)),
          excludeSemantics: true,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: Dimens.spacing8),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: grams == null
                              ? '$missingNutrientPlaceholder '
                              : '${grams.round()} g ',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        TextSpan(
                          // No-break spaces keep "· 74%" with its macro; above
                          // 1.5x that run is too wide, so the share has a line.
                          text: grams == null
                              ? name
                              : large
                              ? '$name\n${share(part)}%'
                              : '$name\u00A0·\u00A0${share(part)}%',
                        ),
                      ],
                    ),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: palette.textMuted,
                    ),
                  ),
                ),
              ],
            ),
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
              // A square inside the stroke, so a large font shrinks the
              // figure rather than touching the ring.
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: MergeSemantics(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          switch (kcal) {
                            final kcal? => '${energyValue(context, kcal)}',
                            null => missingNutrientPlaceholder,
                          },
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
          ),
          const SizedBox(width: Dimens.spacing16),
          Expanded(
            child: Column(
              children: inMacroOrder(
                carbs: line('Carbs', carbs, energy.carbs, palette.carbs),
                fat: line('Fat', fat, energy.fat, palette.fat),
                protein: line(
                  'Protein',
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

/// The four columns in one row, two rows of two at large text, where a
/// quarter of the width breaks "Protein", and one a line above 1.5x, as the
/// Diary's totals (A6).
List<List<Widget>> _afterAddingRows(BuildContext context, List<Widget> cells) {
  final scale = MediaQuery.textScalerOf(context).scale(10);
  if (scale > 15) {
    return [
      for (final cell in cells) [cell],
    ];
  }
  return scale > 13 ? [cells.sublist(0, 2), cells.sublist(2)] : [cells];
}

/// The day's energy and macros once the amount is added: each a figure
/// over its goal and a bar of what was eaten, the amount lighter after
/// it. Goals are targets, so passing one is not coloured, as in the Diary.
/// Nothing until the day is read, or when it can't be.
class TodayAfterAdding extends StatefulWidget {
  final DateTime day;
  final double kcal;
  final double carbs;
  final double fat;
  final double protein;
  final Future<DayTotals> Function(DateTime day) load;

  /// In its own card with its title, as on the food page; false for the
  /// bars alone, under a heading of the caller's (D36).
  final bool framed;

  const TodayAfterAdding({
    super.key,
    required this.day,
    required this.kcal,
    required this.carbs,
    required this.fat,
    required this.protein,
    this.load = loadDayTotals,
    this.framed = true,
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
    final theme = Theme.of(context);
    final palette = paletteOf(context);
    return FutureBuilder<DayTotals>(
      future: _totals,
      builder: (context, snapshot) {
        final totals = snapshot.data;
        if (totals == null) return const SizedBox.shrink();
        Widget column({
          required String name,
          required String unit,
          required int value,
          required int goal,
          required double barGoal,
          required double eaten,
          required double added,
          required Color color,
          int flex = 4,
        }) {
          // in [eaten]'s unit: [goal] is shown in the profile's (kJ or kcal)
          final scale = math.max(barGoal, eaten + added);
          double part(double v) => scale > 0 ? (v / scale).clamp(0, 1) : 0;
          final nameText = Text(
            name,
            style: theme.textTheme.labelSmall?.copyWith(
              color: palette.textMuted,
            ),
          );
          // One line, smaller if it must, as the Diary's totals.
          final figure = FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text.rich(
              maxLines: 1,
              TextSpan(
                children: [
                  TextSpan(
                    text: '$value',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: palette.textStrong,
                    ),
                  ),
                  TextSpan(
                    text: keepUnits(goal > 0 ? ' / $goal $unit' : ' $unit'),
                  ),
                ],
              ),
              style: theme.textTheme.bodySmall?.copyWith(
                color: palette.textMuted,
              ),
            ),
          );
          final bar = ExcludeSemantics(
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
                        (part(eaten), color),
                        (part(added), color.withValues(alpha: 0.45)),
                        ((1 - part(eaten) - part(added)).clamp(0, 1), null),
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
          );
          // Stacked, a name under its bar read as the next figure's label.
          final stacked = MediaQuery.textScalerOf(context).scale(10) > 15;
          return Expanded(
            flex: flex,
            // Words, "Fat 96 of 86 g, 10 g over" (A5).
            child: Semantics(
              // its own node, not merged into the page around it
              container: true,
              label: dayTotalLabel(
                name: name,
                value: value,
                goal: goal,
                unit: unit,
              ),
              excludeSemantics: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: stacked
                    ? [
                        Row(
                          children: [
                            nameText,
                            const SizedBox(width: Dimens.spacing8),
                            Expanded(child: figure),
                          ],
                        ),
                        const SizedBox(height: 4),
                        bar,
                      ]
                    : [
                        figure,
                        const SizedBox(height: 4),
                        bar,
                        const SizedBox(height: 4),
                        nameText,
                      ],
              ),
            ),
          );
        }

        Widget macro(
          String name,
          double eaten,
          double added,
          double goal,
          Color color,
        ) => column(
          name: name,
          unit: 'g',
          value: (eaten + added).round(),
          goal: goal.round(),
          barGoal: goal,
          eaten: eaten,
          added: added,
          color: color,
        );

        final e = totals.eaten, g = totals.goal;
        final body = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.framed) ...[
              // its own heading, read before the totals it heads
              Semantics(
                container: true,
                header: true,
                child: Text(
                  DateUtils.isSameDay(widget.day, DateTime.now())
                      ? 'Today after adding'
                      : 'That day after adding',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: Dimens.spacing8),
            ],
            for (final row in _afterAddingRows(context, [
              column(
                name: 'Energy',
                unit: energyUnit(context),
                value: energyValue(context, e.kcal + widget.kcal),
                goal: energyValue(context, g.kcal),
                barGoal: g.kcal,
                eaten: e.kcal,
                added: widget.kcal,
                color: theme.colorScheme.primary,
                // the longest figure, kept at the macros' size (as the Diary)
                flex: 5,
              ),
              ...inMacroOrder(
                carbs: macro(
                  'Carbs',
                  e.carbs,
                  widget.carbs,
                  g.carbs,
                  palette.carbs,
                ),
                fat: macro('Fat', e.fat, widget.fat, g.fat, palette.fat),
                protein: macro(
                  'Protein',
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
        );
        if (!widget.framed) return body;
        return AppCard(
          padding: const EdgeInsets.all(Dimens.spacing16),
          child: body,
        );
      },
    );
  }
}
