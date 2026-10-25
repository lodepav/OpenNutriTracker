import 'package:flutter/material.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/domain/entity/recipe_entity.dart';
import 'package:opennutritracker/core/domain/entity/recipe_ingredient_entity.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/add_meal/util/food_emoji_resolver.dart';
import 'package:opennutritracker/features/meal_detail/presentation/bloc/meal_detail_bloc.dart';
import 'package:opennutritracker/fork/basket/basket_ui.dart';
import 'package:opennutritracker/fork/copy/copy_ui.dart' show mealLabel;
import 'package:opennutritracker/fork/display/display_prefs.dart';
import 'package:opennutritracker/fork/off/off_kinds.dart';
import 'package:opennutritracker/fork/recipe/recipe_page.dart';

/// Seam S130: the recipes list after the canvas's "Recipes list · B". One
/// dense row per recipe: its kind, the ingredients and one serving's
/// macros, its energy, and a button that logs one serving.

/// The kind the recipe's name says ("Greek yogurt parfait"), else the
/// kind of the ingredient that brings the most energy.
String? recipeEmoji(RecipeEntity recipe) {
  final named = _nameKind(recipe.name);
  if (named != null) return named;
  final byEnergy = [...recipe.ingredients]
    ..sort((a, b) => _energy(b).compareTo(_energy(a)));
  for (final ingredient in byEnergy) {
    final meal = ingredient.snapshotMeal;
    final emoji = OffKinds.emojiFor(meal) ?? resolveFoodEmoji(meal.name);
    if (emoji != null) return emoji;
  }
  return null;
}

/// The longest run of the name's words that names a food, the first
/// such when two are as long: "Greek yogurt parfait" is yogurt.
String? _nameKind(String name) {
  final words = name
      .toLowerCase()
      .split(RegExp(r'[^a-z]+'))
      .where((w) => w.isNotEmpty)
      .toList();
  for (var length = words.length; length > 0; length--) {
    for (var start = 0; start + length <= words.length; start++) {
      final kind = resolveFoodEmoji(
        words.sublist(start, start + length).join(' '),
      );
      if (kind != null) return kind;
    }
  }
  return null;
}

double _energy(RecipeIngredientEntity ingredient) =>
    ingredient.convertedAmountG *
    (ingredient.snapshotMeal.nutriments.energyKcal100 ?? 0) /
    100;

/// One serving's energy and macros, or the whole recipe's when it has no
/// servings.
({double kcal, double carbs, double fat, double protein}) servingValues(
  RecipeEntity recipe,
) {
  final grams = RecipePortion(recipe, 1).grams;
  final per100 = recipe.aggregatedNutrimentsPer100;
  double of(double? value) => (value ?? 0) * grams / 100;
  return (
    kcal: of(per100.energyKcal100),
    carbs: of(per100.carbohydrates100),
    fat: of(per100.fat100),
    protein: of(per100.proteins100),
  );
}

/// "C 38 · F 6 · P 18" in the macro order, each letter in its colour.
List<InlineSpan> macroSpans(
  BuildContext context,
  ({double kcal, double carbs, double fat, double protein}) values,
) {
  final palette = Theme.of(context).brightness == Brightness.dark
      ? AppPalette.dark
      : AppPalette.light;
  // Spoken as "29 grams carbs", not "C 29" (A5).
  List<InlineSpan> one(String letter, String name, double grams, Color color) {
    final g = grams.round();
    return [
      TextSpan(
        text: letter,
        semanticsLabel: '$g ${g == 1 ? 'gram' : 'grams'} $name',
        style: TextStyle(color: color, fontWeight: FontWeight.w700),
      ),
      TextSpan(text: '\u00A0$g', semanticsLabel: ''),
    ];
  }

  final parts = inMacroOrder(
    carbs: one('C', 'carbs', values.carbs, palette.carbs),
    fat: one('F', 'fat', values.fat, palette.fat),
    protein: one('P', 'protein', values.protein, palette.protein),
  );
  return [
    for (var i = 0; i < parts.length; i++) ...[
      if (i > 0) const TextSpan(text: ' · ', semanticsLabel: ', '),
      ...parts[i],
    ],
  ];
}

/// The four meals in a sheet; null when it is closed.
Future<IntakeTypeEntity?> pickMeal(BuildContext context) =>
    showModalBottomSheet<IntakeTypeEntity>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final type in IntakeTypeEntity.values)
              ListTile(
                leading: Icon(type.getIconData()),
                title: Text(mealLabel(context, type)),
                onTap: () => Navigator.of(context).pop(type),
              ),
          ],
        ),
      ),
    );

/// Logs one serving of [recipe] today to [meal], or to the meal the user
/// picks when none is given.
Future<void> logRecipeServing(
  BuildContext context,
  RecipeEntity recipe, {
  IntakeTypeEntity? meal,
}) async {
  final type = meal ?? await pickMeal(context);
  if (type == null || !context.mounted) return;
  final portion = RecipePortion(recipe, 1);
  final written = await locator<MealDetailBloc>().addIntake(
    context,
    'g',
    portion.grams.toString(),
    type,
    recipe.toMealEntity(),
    DateTime.now(),
  );
  if (written == null || !context.mounted) return;
  refreshAfterLogging();
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        '${portion.label} of ${recipe.name} added to '
        '${mealLabel(context, type)}',
      ),
    ),
  );
}
