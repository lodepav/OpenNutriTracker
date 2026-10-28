import 'package:flutter/material.dart';
import 'package:opennutritracker/core/domain/entity/recipe_entity.dart';
import 'package:opennutritracker/core/domain/entity/recipe_ingredient_entity.dart';
import 'package:opennutritracker/core/utils/navigation_options.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/features/add_meal/presentation/bloc/bulk_add_bloc.dart';
import 'package:opennutritracker/features/meal_detail/util/meal_quantity_converter.dart';
import 'package:opennutritracker/features/recipes/presentation/screens/recipe_builder_screen.dart';
import 'package:opennutritracker/fork/dish/dish_breakdown_rows.dart';
import 'package:opennutritracker/fork/dish/dish_strings.dart';

/// True for the first row of a breakdown group, where "Save as recipe"
/// is offered once for the whole group.
bool isFirstOfDishGroup(List<BulkAddRow> rows, int index) {
  final group = rows[index].dishIngredient?.group;
  return group != null &&
      (index == 0 || !identical(rows[index - 1].dishIngredient?.group, group));
}

/// An unsaved recipe from a breakdown group (phase 1c.4), of the servings
/// it was asked for:
/// the rows as they stand, edits included, each converted to grams the way
/// bulk add's own save converts it. Skipped, unmatched and unreadable rows
/// are left out. Null when nothing is left.
///
/// The id is empty: upstream's builder reads that as "a copy", gives it a
/// new id and saves it as a new recipe. The builder recomputes the totals,
/// so none are filled in here.
RecipeEntity? recipeFromDishGroup(List<BulkAddRow> rows, Object group) {
  final members = [
    for (final row in rows)
      if (identical(row.dishIngredient?.group, group)) row,
  ];
  if (members.isEmpty) return null;
  return recipeFromRows(
    members,
    name: _capitalized(members.first.dishIngredient!.dish),
    description: DishStrings.recipeDescription,
    servings: members.first.dishIngredient!.servings,
  );
}

/// An unsaved recipe of [servings] from [rows], on the same terms as
/// [recipeFromDishGroup]. Null when no row is ready.
RecipeEntity? recipeFromRows(
  List<BulkAddRow> rows, {
  required String name,
  required String description,
  int servings = 1,
}) {
  final ingredients = [
    for (final row in rows)
      if (row.willBeLogged && row.quantityError == null) _ingredient(row),
  ];
  if (ingredients.isEmpty) return null;
  final now = DateTime.now();
  return RecipeEntity(
    id: '',
    name: name,
    description: description,
    ingredients: ingredients,
    totalWeightG: ingredients.fold(0, (sum, i) => sum + i.convertedAmountG),
    aggregatedNutrimentsPer100: MealNutrimentsEntity.empty(),
    createdAt: now,
    updatedAt: now,
    servingsCount: servings,
  );
}

RecipeIngredientEntity _ingredient(BulkAddRow row) {
  final grams = convertQuantityToBaseUnit(
    double.parse(row.amountText.trim().replaceAll(',', '.')),
    row.effectiveUnit,
    row.meal!,
  );
  return RecipeIngredientEntity(
    snapshotMeal: row.meal!,
    amount: grams,
    unit: 'g',
    convertedAmountG: grams,
  );
}

String _capitalized(String text) {
  final trimmed = text.trim();
  return trimmed.isEmpty
      ? trimmed
      : trimmed[0].toUpperCase() + trimmed.substring(1);
}

/// Opens upstream's recipe builder on [recipe], for review and saving.
Future<void> openDishRecipe(BuildContext context, RecipeEntity recipe) =>
    Navigator.of(context).pushNamed(
      NavigationOptions.recipeBuilderRoute,
      arguments: RecipeBuilderArguments(existing: recipe),
    );
