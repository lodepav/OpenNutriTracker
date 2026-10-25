import 'package:flutter/material.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/domain/entity/recipe_entity.dart';
import 'package:opennutritracker/core/domain/entity/recipe_ingredient_entity.dart';
import 'package:opennutritracker/core/presentation/widgets/app_card.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/fork/copy/copy_ui.dart' show mealLabel;
import 'package:opennutritracker/fork/display/display_prefs.dart';
import 'package:opennutritracker/fork/off/off_kinds.dart';
import 'package:opennutritracker/fork/units/energy_text.dart';
import 'package:opennutritracker/fork/widget/meal_picker_chip.dart';
import 'package:opennutritracker/generated/l10n.dart';

/// Seam S126: the recipe page after the canvas's Recipe B. Ingredients
/// first: the name, its tags, a strip of the totals for the portion
/// chosen, each ingredient with its kind and macros, and a stepper beside
/// Log at the bottom. A portion is a serving when the recipe has
/// servings, else the whole recipe; it steps by halves.
class RecipePortion {
  static const step = 0.5;

  final RecipeEntity recipe;
  final double count;

  const RecipePortion(this.recipe, this.count);

  bool get byServing => (recipe.servingsCount ?? 0) > 0;

  double get grams =>
      count *
      (byServing
          ? recipe.totalWeightG / recipe.servingsCount!
          : recipe.totalWeightG);

  /// "1½ servings", "½ recipe".
  String get label {
    final whole = count.truncate();
    final half = count - whole >= step;
    final number = '${whole == 0 && half ? '' : whole}${half ? '½' : ''}';
    final noun = byServing ? 'serving' : 'recipe';
    return count <= 1 ? '$number $noun' : '$number ${noun}s';
  }
}

String _grams(double g) =>
    g == g.roundToDouble() ? g.toInt().toString() : g.toStringAsFixed(1);

/// The name, the description, then the tags and how many ingredients.
class RecipeHeader extends StatelessWidget {
  final RecipeEntity recipe;

  const RecipeHeader({super.key, required this.recipe});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = theme.brightness == Brightness.dark
        ? AppPalette.dark
        : AppPalette.light;
    final description = recipe.description;
    final n = recipe.ingredients.length;
    Widget tag(String text) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: palette.surfaceMuted,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: theme.textTheme.bodySmall?.copyWith(color: palette.textMuted),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The whole name, which the app bar cuts short at a large font.
        Semantics(
          header: true,
          child: Text(
            recipe.name,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        if (description != null && description.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            description,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: palette.textMuted,
            ),
          ),
        ],
        const SizedBox(height: Dimens.spacing8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final t in recipe.tags) tag(t),
            tag(n == 1 ? '1 ingredient' : '$n ingredients'),
          ],
        ),
      ],
    );
  }
}

/// Energy and the macros in the macro order for [portion], then the
/// portion's weight and the energy per 100 g.
class RecipeTotalsStrip extends StatelessWidget {
  final RecipePortion portion;

  const RecipeTotalsStrip({super.key, required this.portion});

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final theme = Theme.of(context);
    final palette = theme.brightness == Brightness.dark
        ? AppPalette.dark
        : AppPalette.light;
    final per100 = portion.recipe.aggregatedNutrimentsPer100;
    double of(double? value) => (value ?? 0) * portion.grams / 100;
    Widget cell(String value, String label, Color color) => Expanded(
      child: MergeSemantics(
        child: Column(
          children: [
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleLarge?.copyWith(
                color: color,
                fontWeight: FontWeight.w800,
              ),
            ),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                maxLines: 1,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: palette.textMuted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
    return AppCard(
      padding: const EdgeInsets.all(Dimens.spacing12),
      child: Column(
        children: [
          Row(
            children: [
              cell(
                '${energyValue(context, of(per100.energyKcal100))}',
                energyUnit(context),
                theme.colorScheme.onSurface,
              ),
              ...inMacroOrder(
                carbs: cell(
                  of(per100.carbohydrates100).round().toString(),
                  '${s.carbsLabel} g',
                  palette.carbs,
                ),
                fat: cell(
                  of(per100.fat100).round().toString(),
                  '${s.fatLabel} g',
                  palette.fat,
                ),
                protein: cell(
                  of(per100.proteins100).round().toString(),
                  '${s.proteinLabel} g',
                  palette.protein,
                ),
              ),
            ],
          ),
          const SizedBox(height: Dimens.spacing8),
          Text(
            '${portion.label}, ${_grams(portion.grams)} g · per 100 g '
            '${energyText(context, per100.energyKcal100 ?? 0)}',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: palette.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

/// One ingredient: its kind, its name over its macros in the whole
/// recipe, and its energy over its amount.
class RecipeIngredientRow extends StatelessWidget {
  final RecipeIngredientEntity ingredient;

  const RecipeIngredientRow({super.key, required this.ingredient});

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final theme = Theme.of(context);
    final palette = theme.brightness == Brightness.dark
        ? AppPalette.dark
        : AppPalette.light;
    final meal = ingredient.snapshotMeal;
    final n = meal.nutriments;
    double of(double? per100) =>
        (per100 ?? 0) * ingredient.convertedAmountG / 100;
    TextSpan macro(String letter, double? per100, Color color) => TextSpan(
      children: [
        TextSpan(
          text: letter,
          style: TextStyle(color: color, fontWeight: FontWeight.w700),
        ),
        TextSpan(text: ' ${of(per100).round()}'),
      ],
    );
    final macros = inMacroOrder(
      carbs: macro(
        s.carbsLabelShort.toUpperCase(),
        n.carbohydrates100,
        palette.carbs,
      ),
      fat: macro(s.fatLabelShort.toUpperCase(), n.fat100, palette.fat),
      protein: macro(
        s.proteinLabelShort.toUpperCase(),
        n.proteins100,
        palette.protein,
      ),
    );
    final amount = '${_grams(ingredient.amount)} ${ingredient.unit}';
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: palette.surfaceMuted,
              borderRadius: Dimens.borderRadiusS,
            ),
            child: switch (OffKinds.emojiFor(meal)) {
              final emoji? => ExcludeSemantics(
                child: Text(emoji, style: const TextStyle(fontSize: 18)),
              ),
              _ => Icon(
                Icons.eco_rounded,
                size: 20,
                color: theme.colorScheme.primary,
              ),
            },
          ),
          const SizedBox(width: Dimens.spacing12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    meal.name ?? '?',
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyLarge,
                  ),
                  Text.rich(
                    TextSpan(
                      children: [
                        for (final (i, m) in macros.indexed) ...[
                          if (i > 0) const TextSpan(text: ' · '),
                          m,
                        ],
                      ],
                    ),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: palette.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: Dimens.spacing8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                energyText(context, of(n.energyKcal100)),
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                amount,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: palette.textMuted,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The bottom bar: fewer, the portion, more and the meal, then Add with
/// its energy and meal, as Quick add words it.
class RecipeLogBar extends StatelessWidget {
  final RecipePortion portion;
  final ValueChanged<double> onCount;
  final IntakeTypeEntity meal;
  final ValueChanged<IntakeTypeEntity> onMeal;
  final VoidCallback onLog;

  const RecipeLogBar({
    super.key,
    required this.portion,
    required this.onCount,
    required this.meal,
    required this.onMeal,
    required this.onLog,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = theme.brightness == Brightness.dark
        ? AppPalette.dark
        : AppPalette.light;
    final count = portion.count;
    final kcal =
        (portion.recipe.aggregatedNutrimentsPer100.energyKcal100 ?? 0) *
        portion.grams /
        100;
    return Material(
      color: theme.colorScheme.surface,
      child: SafeArea(
        top: false,
        child: Container(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: palette.border)),
          ),
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            spacing: Dimens.spacing8,
            children: [
              Row(
                children: [
                  IconButton.outlined(
                    tooltip: 'Less',
                    icon: const Icon(Icons.remove_rounded),
                    onPressed: count > RecipePortion.step
                        ? () => onCount(count - RecipePortion.step)
                        : null,
                  ),
                  Expanded(
                    child: Text(
                      portion.label,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  IconButton.outlined(
                    tooltip: 'More',
                    icon: const Icon(Icons.add_rounded),
                    onPressed: () => onCount(count + RecipePortion.step),
                  ),
                  const SizedBox(width: Dimens.spacing8),
                  MealPickerChip(
                    key: const ValueKey('recipe-meal'),
                    type: meal,
                    onChanged: onMeal,
                  ),
                ],
              ),
              FilledButton(
                key: const ValueKey('recipe-log'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  shape: const StadiumBorder(),
                ),
                onPressed: onLog,
                child: Text(
                  'Add ${energyText(context, kcal)} to ${mealLabel(context, meal)}',
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
