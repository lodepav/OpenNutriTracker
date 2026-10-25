import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/recipe_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_store.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_ui.dart';
import 'package:opennutritracker/fork/meal_detail/missing_info.dart';

RecipeEntity _recipe(MealNutrimentsEntity n, {int? servings = 4}) =>
    RecipeEntity(
      id: 'r',
      name: 'Chili',
      description: null,
      ingredients: const [],
      totalWeightG: 1550,
      aggregatedNutrimentsPer100: n,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      servingsCount: servings,
    );

MealEntity _meal({double? kcal, double? carbs, double? fat, double? protein}) =>
    _recipe(
      MealNutrimentsEntity(
        energyKcal100: kcal,
        carbohydrates100: carbs,
        fat100: fat,
        proteins100: protein,
        sugars100: null,
        saturatedFat100: null,
        fiber100: null,
      ),
    ).toMealEntity();

void main() {
  test('a food with energy and all three macros can be logged', () {
    final meal = _meal(kcal: 120, carbs: 10, fat: 5, protein: 8);
    expect(missingForLog(meal, 'kJ'), isEmpty);
  });

  test(
    "an imported day's energy-only totals can't, and say what's missing",
    () {
      final meal = _meal(kcal: 1800);
      expect(missingForLog(meal, 'kJ'), ['carbs', 'fat', 'protein']);
      expect(
        missingForLogText(missingForLog(meal, 'kJ')),
        "Can't log this food: it has no carbs, fat or protein per 100 g. "
        'Edit it to add them.',
      );
    },
  );

  test('missing energy is named in the unit the user reads', () {
    final meal = _meal(carbs: 10, fat: 5, protein: 8);
    expect(missingForLog(meal, 'kJ'), ['energy (kJ)']);
    expect(
      missingForLogText(missingForLog(meal, 'kJ')),
      contains('no energy (kJ) per 100 g'),
    );
  });

  test('a recipe serving reads as one serving and its weight', () {
    final meal = _meal(kcal: 120, carbs: 10, fat: 5, protein: 8);
    expect(meal.servingSize, '1 serving (387.5 g)');
    expect(meal.servingQuantity, 387.5);
    final three = _recipe(
      MealNutrimentsEntity.empty(),
      servings: 5,
    ).toMealEntity();
    expect(three.servingSize, '1 serving (310 g)');
    expect(
      _recipe(
        MealNutrimentsEntity.empty(),
        servings: null,
      ).toMealEntity().servingSize,
      isNull,
    );
  });

  group('changedTargetSettings', () {
    const weekly = AdaptiveSettings(
      adaptiveTarget: true,
      activityMode: ActivityMode.weekly,
    );

    test('names each setting that differs', () {
      expect(
        changedTargetSettings(
          weekly.targetBasis,
          weekly.copyWith(countSteps: false, flatEnergy: true).targetBasis,
        ),
        ['steps', 'energy per kg'],
      );
      expect(
        changedTargetSettings(
          weekly.targetBasis,
          weekly.copyWith(activityMode: ActivityMode.daily).targetBasis,
        ),
        ['activity'],
      );
    });

    test('names none for the same settings or an older record', () {
      expect(
        changedTargetSettings(weekly.targetBasis, weekly.targetBasis),
        isEmpty,
      );
      expect(changedTargetSettings(null, weekly.targetBasis), isEmpty);
    });
  });
}
