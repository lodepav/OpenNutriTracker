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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final palette = isDark ? AppPalette.dark : AppPalette.light;
    final style = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: palette.textMuted);
    final per = 'per 100 ${meal.isLiquid ? 'ml' : 'g'}';
    // Shown with no-break spaces, so "per 100 g" never splits.
    final perShown = per.replaceAll(' ', '\u00a0');
    String grams(double? v) => v == null ? '–' : '${v.round()}';
    return MacroOrderBuilder(
      builder: (context) {
        final macros = inMacroOrder(
          carbs: ('C', 'carbs', n.carbohydrates100),
          fat: ('F', 'fat', n.fat100),
          protein: ('P', 'protein', n.proteins100),
        );
        return Text.rich(
          TextSpan(
            children: [
              TextSpan(text: energyText(context, kcal)),
              for (final (letter, _, value) in macros) ...[
                const TextSpan(text: ' · '),
                TextSpan(
                  text: letter,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                TextSpan(text: ' ${grams(value)}'),
              ],
              TextSpan(text: ' $perShown'),
            ],
          ),
          style: style,
          semanticsLabel: [
            energyText(context, kcal),
            for (final (_, name, value) in macros)
              '${grams(value)} grams $name',
            per,
          ].join(', '),
        );
      },
    );
  }
}
