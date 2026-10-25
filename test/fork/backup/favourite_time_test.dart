import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/data/dbo/favourite_meal_dbo.dart';
import 'package:opennutritracker/core/data/dbo/meal_dbo.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';

// In a zone whose clocks go back on 25 October 2026 (`just test_dst` runs
// it under Europe/Berlin), both moments are the same local 02:30.
void main() {
  test('a favourite starred in the repeated hour keeps its moment', () {
    final meal = MealDBO.fromMealEntity(
      MealEntity(
        code: 'c1',
        name: 'Lunchbox',
        url: null,
        mealQuantity: '100',
        mealUnit: 'g',
        servingQuantity: null,
        servingUnit: null,
        servingSize: null,
        nutriments: MealNutrimentsEntity(
          energyKcal100: 0,
          carbohydrates100: null,
          fat100: null,
          proteins100: null,
          sugars100: null,
          saturatedFat100: null,
          fiber100: null,
        ),
        source: MealSourceEntity.custom,
      ),
    );
    for (final utc in [
      DateTime.utc(2026, 10, 25, 0, 30),
      DateTime.utc(2026, 10, 25, 1, 30),
    ]) {
      final starred = FavouriteMealDBO(meal: meal, addedAt: utc.toLocal());
      final back = FavouriteMealDBO.fromJson(
        jsonDecode(jsonEncode(starred.toJson())) as Map<String, dynamic>,
      );
      expect(back.addedAt, starred.addedAt, reason: '$utc');
    }
  });
}
