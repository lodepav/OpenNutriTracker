import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:logging/logging.dart';
import 'package:opennutritracker/core/domain/entity/recipe_entity.dart';
import 'package:opennutritracker/core/domain/entity/recipe_ingredient_entity.dart';
import 'package:opennutritracker/core/domain/usecase/save_recipe_usecase.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/add_meal/data/data_sources/sp_food_data_source.dart';
import 'package:opennutritracker/features/add_meal/data/dto/sp/sp_food_dto.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/fork/food/local_food_data_source.dart';

/// One ingredient: a food-table row by id, and its grams in the source.
typedef StarterIngredient = ({int foodId, double grams});

class StarterRecipe {
  /// Stable, so a restore or a second run updates rather than duplicates.
  final String id;
  final String name;
  final String description;
  final int servings;
  final List<StarterIngredient> ingredients;

  const StarterRecipe(
    this.id,
    this.name,
    this.description,
    this.servings,
    this.ingredients,
  );
}

const _credit =
    'From "The Cuisine of Latvia", Latvian Institute (data.gov.lv, CC0).';

/// The four CC0 Latvian recipes (D12, phase 1c.6), with the source's grams.
/// Each food id was chosen against the bundled table (BLS where it has a
/// European equivalent, USDA otherwise); `starter_recipes_test.dart` checks
/// every id still names the food it was chosen as. A range in the source
/// is taken at its middle. Servings are ours: the source gives none.
const starterRecipes = <StarterRecipe>[
  StarterRecipe(
    'fork-starter-grey-peas-with-bacon',
    'Grey peas with bacon',
    '$_credit Grey peas are entered as dried split peas. Weights are '
        'before cooking.',
    2,
    [
      (foodId: 172428, grams: 200), // Peas, green, split, mature seeds, raw
      (foodId: 10002256, grams: 60), // Pork streaky bacon, raw cured, smoked
      (foodId: 10000521, grams: 40), // Onion, raw
      (foodId: 10000390, grams: 2), // Common salt/table salt
    ],
  ),
  StarterRecipe(
    'fork-starter-pelmeni',
    'Pelmeni',
    '$_credit The ground meat is entered as half pork, half beef; the dried '
        'herbs and chili are left out. Weights are before cooking.',
    6,
    [
      (foodId: 169761, grams: 500), // Wheat flour, white, all-purpose
      (foodId: 2710707, grams: 125), // Water, tap
      (foodId: 2707152, grams: 50), // Egg, whole, raw
      (foodId: 10000390, grams: 3), // Common salt/table salt
      (foodId: 2514745, grams: 250), // Pork, ground, raw
      (foodId: 2705853, grams: 250), // Beef, ground, raw
      (foodId: 10000521, grams: 75), // Onion, raw
      (foodId: 169230, grams: 8), // Garlic, raw
      (foodId: 10000338, grams: 30), // Whole milk, 3.5 % fat
    ],
  ),
  StarterRecipe(
    'fork-starter-sklandu-rausi',
    // The one-word name too: a model writes "sklandrausis", which no word
    // rule takes to "sklandu rauši".
    'Sklandu rauši (sklandrausis)',
    '$_credit Rye pastry with potato and carrot filling. One serving is one '
        'tart. Weights are before baking.',
    12,
    [
      (foodId: 10000548, grams: 450), // Rye wholemeal flour
      (foodId: 2710707, grams: 200), // Water, tap
      (foodId: 10000841, grams: 50), // Pork lard
      (foodId: 169655, grams: 10), // Sugars, granulated
      (foodId: 10000390, grams: 5), // Common salt/table salt
      (foodId: 2707152, grams: 50), // Egg, whole, raw (to brush)
      (foodId: 10000325, grams: 250), // Potatoe, peeled, raw
      (foodId: 10000338, grams: 25), // Whole milk, 3.5 % fat
      (foodId: 173430, grams: 15), // Butter, without salt
      (foodId: 10000298, grams: 375), // Carrot, raw
      (foodId: 169655, grams: 50), // Sugars, granulated
      (foodId: 10001076, grams: 25), // Sour cream, min. 20 % fat
      (foodId: 2707152, grams: 100), // Egg, whole, raw
      (foodId: 169761, grams: 15), // Wheat flour, white, all-purpose
    ],
  ),
  StarterRecipe(
    'fork-starter-layered-rye-bread-dessert',
    'Layered rye bread dessert',
    '$_credit The cranberry jam is entered as sweetened cranberry sauce.',
    1,
    [
      (foodId: 10002238, grams: 90), // Rye bread
      (foodId: 169655, grams: 20), // Sugars, granulated
      (foodId: 173430, grams: 15), // Butter, without salt
      (foodId: 173961, grams: 50), // Cranberry sauce, canned, sweetened
      (foodId: 10000698, grams: 60), // Whipping cream, min. 30 % fat
    ],
  ),
];

final _log = Logger('StarterRecipes');

/// Saves [starterRecipes] once per install, from the food-table rows they
/// name, through upstream's save so the builder computes the nutrition.
/// Once, not on every start: a starter the user deleted stays deleted.
class StarterRecipeSeeder {
  static const _boxName = 'fork_flags';
  static const _seededKey = 'starterRecipesSeeded';

  final Future<bool> Function() _isSeeded;
  final Future<void> Function() _markSeeded;
  final Future<LocalFoodTable> Function() _table;
  final SaveRecipeUseCase _save;

  StarterRecipeSeeder({
    required Future<bool> Function() isSeeded,
    required Future<void> Function() markSeeded,
    required Future<LocalFoodTable> Function() table,
    required SaveRecipeUseCase save,
  }) : _isSeeded = isSeeded,
       _markSeeded = markSeeded,
       _table = table,
       _save = save;

  /// The flag sits in a box of the fork's own, so upstream's boxes and
  /// their backup format stay untouched.
  factory StarterRecipeSeeder.fromLocator() {
    Future<Box<bool>> box() => Hive.openBox<bool>(_boxName);
    return StarterRecipeSeeder(
      isSeeded: () async => (await box()).get(_seededKey) ?? false,
      markSeeded: () async => (await box()).put(_seededKey, true),
      table: () => (locator<SpFoodDataSource>() as LocalFoodDataSource).table,
      save: locator<SaveRecipeUseCase>(),
    );
  }

  /// Never throws: a startup chore must not stop the app starting.
  Future<void> run() async {
    try {
      if (await _isSeeded()) return;
      final table = await _table();
      final byId = {for (final food in table.foods) food.foodId: food};
      final now = DateTime.now();
      for (final starter in starterRecipes) {
        final recipe = _recipeFrom(starter, byId, now);
        if (recipe == null) {
          _log.warning('Skipped ${starter.id}: a food id is not in the table');
          continue;
        }
        await _save.save(recipe);
      }
      await _markSeeded();
    } catch (e, stackTrace) {
      _log.warning('Starter recipes not saved', e, stackTrace);
    }
  }

  static RecipeEntity? _recipeFrom(
    StarterRecipe starter,
    Map<int?, SpFoodDTO> byId,
    DateTime now,
  ) {
    final ingredients = <RecipeIngredientEntity>[];
    for (final (:foodId, :grams) in starter.ingredients) {
      final food = byId[foodId];
      if (food == null) return null;
      ingredients.add(
        RecipeIngredientEntity(
          snapshotMeal: MealEntity.fromSpFood(food),
          amount: grams,
          unit: 'g',
          convertedAmountG: grams,
        ),
      );
    }
    return RecipeEntity(
      id: starter.id,
      name: starter.name,
      description: starter.description,
      ingredients: ingredients,
      // Both recomputed by the save.
      totalWeightG: 0,
      aggregatedNutrimentsPer100: MealNutrimentsEntity.empty(),
      createdAt: now,
      updatedAt: now,
      servingsCount: starter.servings,
    );
  }
}
