import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/recipe_entity.dart';
import 'package:opennutritracker/core/domain/entity/recipe_ingredient_entity.dart';
import 'package:opennutritracker/core/domain/usecase/compute_recipe_nutrition_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/save_recipe_usecase.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/features/recipes/presentation/bloc/recipe_builder_bloc.dart';

class _Save implements SaveRecipeUseCase {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

MealEntity _food(String name, double kcal100) => MealEntity(
  code: name,
  name: name,
  url: null,
  mealQuantity: null,
  mealUnit: 'g',
  servingQuantity: null,
  servingUnit: 'g',
  servingSize: null,
  nutriments: MealNutrimentsEntity(
    energyKcal100: kcal100,
    carbohydrates100: 0,
    fat100: 0,
    proteins100: 0,
    sugars100: 0,
    saturatedFat100: 0,
    fiber100: 0,
  ),
  source: MealSourceEntity.fdc,
);

RecipeIngredientEntity _grams(MealEntity food, double g) =>
    RecipeIngredientEntity(
      snapshotMeal: food,
      amount: g,
      unit: 'g',
      convertedAmountG: g,
    );

void main() {
  // The shape recipeFromDishGroup hands the builder: an empty id, totals
  // left for the builder to compute.
  test('upstream\'s builder opens a breakdown recipe as a new recipe with '
      'its nutrition computed', () async {
    final bloc = RecipeBuilderBloc(ComputeRecipeNutritionUseCase(), _Save());
    final now = DateTime(2026, 10, 22);
    bloc.add(
      InitializeBuilderEvent(
        existing: RecipeEntity(
          id: '',
          name: 'Khachapuri',
          description: null,
          ingredients: [
            _grams(_food('flour', 364), 100),
            _grams(_food('cheese', 300), 100),
          ],
          totalWeightG: 200,
          aggregatedNutrimentsPer100: MealNutrimentsEntity.empty(),
          createdAt: now,
          updatedAt: now,
          servingsCount: 1,
        ),
      ),
    );
    await pumpEventQueue();

    expect(bloc.state.isExistingRecipe, isFalse);
    expect(bloc.state.id, isNot(''));
    expect(bloc.state.totalWeightG, 200);
    expect(
      bloc.state.aggregatedNutrimentsPer100.energyKcal100,
      closeTo(332, 0.01),
    );
    await bloc.close();
  });
}
