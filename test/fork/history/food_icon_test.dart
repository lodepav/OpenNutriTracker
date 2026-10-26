import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
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

String? _food(String name) =>
    importedFoodEmoji(_entry('history-food-2026-05-01-1', name));

void main() {
  test('an imported food shows the kind its name says, in color', () {
    expect(_food('Whey Protein Chocolate'), '🥤');
    expect(_food('Green tea'), '🍵');
    expect(_food('Beef soup'), '🍜');
    expect(_food('Sweet potato fries'), '🍟');
    expect(_food('Steak, grilled'), '🍖');
    expect(_food('Multi fruit juice'), '🥛');
    expect(_food('Bananas'), '🍎');
    expect(_food('Tomatoes, raw'), '🥗');
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

  test('an entry logged here keeps its icon; totals have no food emoji', () {
    expect(importedFoodIcon(_entry('123', 'Banana')), isNull);
    expect(importedFoodEmoji(_entry('123', 'Banana')), isNull);
    expect(
      importedFoodEmoji(_entry('history-2026-05-01-lunch', 'Banana')),
      isNull,
    );
  });
}
