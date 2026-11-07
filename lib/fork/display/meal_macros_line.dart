import 'package:flutter/material.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/fork/display/display_prefs.dart';
import 'package:opennutritracker/fork/units/energy_text.dart';

/// A food's energy and macros per 100 g (or ml) on one line under its name
/// in search and recents (seam S83), so foods compare without opening them:
/// "120 kcal · P 4 · F 3 · C 20 per 100 g", macros in the user's order.
/// Nothing when the food has no energy.
class MealMacrosLine extends StatelessWidget {
  final MealEntity meal;

  const MealMacrosLine({super.key, required this.meal});

  @override
  Widget build(BuildContext context) {
    final n = meal.nutriments;
    final kcal = n.energyKcal100;
    if (kcal == null) return const SizedBox.shrink();
    return MacrosLine(
      lead: energyText(context, kcal),
      carbs: n.carbohydrates100,
      fat: n.fat100,
      protein: n.proteins100,
      tail: 'per 100 ${meal.isLiquid ? 'ml' : 'g'}',
    );
  }
}

/// Macros in grams on one muted line, "C 20 · F 3 · P 4" in the user's
/// order, after [lead] and before [tail] when given; a logged food's row
/// shows its own (seam S115). Each macro is in a muted shade of its colour
/// (D38), so the line reads the same in search, the Diary and Log with AI.
class MacrosLine extends StatelessWidget {
  final String? lead;
  final double? carbs;
  final double? fat;
  final double? protein;
  final String? tail;

  /// Cut short at this many lines, the [tail] going first.
  final int? maxLines;

  const MacrosLine({
    super.key,
    this.lead,
    required this.carbs,
    required this.fat,
    required this.protein,
    this.tail,
    this.maxLines,
  });

  @override
  Widget build(BuildContext context) {
    final palette = paletteOf(context);
    final style = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: palette.textMuted);
    String grams(double? v) => v == null ? '–' : '${v.round()}';
    return MacroOrderBuilder(
      builder: (context) {
        final macros = inMacroOrder(
          carbs: ('C', 'carbs', carbs, palette.carbsColor),
          fat: ('F', 'fat', fat, palette.fatColor),
          protein: ('P', 'protein', protein, palette.proteinColor),
        );
        return Text.rich(
          TextSpan(
            children: [
              if (lead != null) TextSpan(text: '$lead · '),
              for (final (i, (letter, _, value, color)) in macros.indexed) ...[
                if (i > 0) const TextSpan(text: ' · '),
                TextSpan(
                  style: TextStyle(color: mutedMacroColor(color, palette)),
                  children: [
                    TextSpan(
                      text: letter,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    TextSpan(text: ' ${grams(value)}'),
                  ],
                ),
              ],
              // Shown with no-break spaces, so "per 100 g" never splits;
              // on one line, cut where it must.
              if (tail != null)
                TextSpan(
                  text: maxLines == 1
                      ? ' $tail'
                      : ' ${tail!.replaceAll(' ', '\u00a0')}',
                ),
            ],
          ),
          style: style,
          maxLines: maxLines,
          overflow: maxLines == null ? null : TextOverflow.ellipsis,
          semanticsLabel: [
            ?lead,
            for (final (_, name, value, _) in macros)
              '${grams(value)} ${grams(value) == '1' ? 'gram' : 'grams'} $name',
            ?tail,
          ].join(', '),
        );
      },
    );
  }
}

/// The macros as [MacrosLine] colours them, "C 20 · F 3 · P 4" in the
/// user's order, for a line that keeps its own style: the Diary's meal
/// header.
List<InlineSpan> macroSpans(
  AppPalette palette, {
  required double carbs,
  required double fat,
  required double protein,
}) {
  final macros = inMacroOrder(
    carbs: ('C', carbs, palette.carbsColor),
    fat: ('F', fat, palette.fatColor),
    protein: ('P', protein, palette.proteinColor),
  );
  return [
    for (final (i, (letter, value, color)) in macros.indexed) ...[
      if (i > 0) const TextSpan(text: ' · '),
      TextSpan(
        text: '$letter ${value.round()}',
        style: TextStyle(color: mutedMacroColor(color, palette)),
      ),
    ],
  ];
}

/// [macro] halfway to the muted text colour: quiet beside a food's name
/// and still its own colour, readable as small text on the cards it sits
/// on (4.6:1 or more on the light theme's surface, 6.5:1 on the dark).
Color mutedMacroColor(Color macro, AppPalette palette) =>
    Color.lerp(macro, palette.textMuted, 0.5)!;
