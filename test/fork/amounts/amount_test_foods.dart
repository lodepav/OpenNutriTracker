import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_portion_entity.dart';

const nutriments = MealNutrimentsEntity(
  energyKcal100: 247,
  carbohydrates100: 41,
  fat100: 3.4,
  proteins100: 13,
  sugars100: 6,
  saturatedFat100: 0.7,
  fiber100: 7,
);

/// Bread with two portions from the food table: a slice and a roll.
MealEntity bread({List<MealPortionEntity>? portions, String mealUnit = 'g'}) =>
    MealEntity(
      code: 'bread',
      name: 'Bread, whole-wheat',
      url: null,
      mealQuantity: '100',
      mealUnit: mealUnit,
      servingQuantity: 32,
      servingUnit: 'g',
      servingSize: '1 slice (32 g)',
      nutriments: nutriments,
      source: MealSourceEntity.fdc,
      portions:
          portions ??
          const [
            MealPortionEntity(
              label: '1 slice (32 g)',
              gramWeight: 32,
              localized: true,
            ),
            MealPortionEntity(label: '1 roll', gramWeight: 60, localized: true),
          ],
    );

/// A packaged food with only a serving, as Open Food Facts gives it.
MealEntity rye({double? serving = 50, String mealUnit = 'g'}) => MealEntity(
  code: '4000000000001',
  name: 'Rye bread',
  url: null,
  mealQuantity: '500',
  mealUnit: mealUnit,
  servingQuantity: serving,
  servingUnit: serving == null ? null : 'g',
  servingSize: serving == null ? null : '$serving g',
  nutriments: nutriments,
  source: MealSourceEntity.off,
);
