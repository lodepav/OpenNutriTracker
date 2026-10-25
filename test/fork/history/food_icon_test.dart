import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/utils/custom_icons.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/fork/history/food_icon.dart';

IntakeEntity _entry(
  String code,
  String name, [
  IntakeTypeEntity type = IntakeTypeEntity.snack,
]) => IntakeEntity(
  id: code,
  unit: 'g',
  amount: 100,
  type: type,
  meal: MealEntity(
    code: code,
    name: name,
    url: null,
    mealQuantity: null,
    mealUnit: 'g',
    servingQuantity: null,
    servingUnit: 'g',
    servingSize: null,
    nutriments: const MealNutrimentsEntity(
      energyKcal100: 100,
      carbohydrates100: 10,
      fat100: 1,
      proteins100: 10,
      sugars100: null,
      saturatedFat100: null,
      fiber100: null,
    ),
    source: MealSourceEntity.unknown,
  ),
  dateTime: DateTime(2026, 5, 1, 12),
);

IconData? _food(String name) =>
    importedFoodIcon(_entry('history-food-2026-05-01-1', name));

void main() {
  test('an imported food shows the kind its name says', () {
    expect(_food('Whey Protein Chocolate'), Icons.blender_rounded);
    expect(_food('Green tea'), Icons.emoji_food_beverage_rounded);
    expect(_food('Beef soup'), Icons.ramen_dining_rounded);
    expect(_food('Sweet potato fries'), Icons.fastfood_rounded);
    expect(_food('Steak, grilled'), Icons.kebab_dining_rounded);
    expect(_food('Multi fruit juice'), Icons.local_drink_rounded);
    expect(_food('Bananas'), CustomIcons.food_apple_outline);
    expect(_food('Tomatoes, raw'), Icons.eco_rounded);
    expect(_food('Olive oil'), isNull);
  });

  test('totals show their meal, a whole day nothing', () {
    expect(
      importedFoodIcon(
        _entry(
          'history-2026-05-01-lunch',
          'Logged in MacroFactor',
          IntakeTypeEntity.lunch,
        ),
      ),
      IntakeTypeEntity.lunch.getIconData(),
    );
    expect(
      importedFoodIcon(_entry('history-2026-05-01-day', 'Day logged in X')),
      isNull,
    );
  });

  test('an entry logged here keeps its icon', () {
    expect(importedFoodIcon(_entry('123', 'Banana')), isNull);
  });
}
