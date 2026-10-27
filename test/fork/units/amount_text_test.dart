import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/fork/units/amount_text.dart';

IntakeEntity _logged(double amount, String? mealUnit) => IntakeEntity(
  id: 'apple',
  unit: 'serving',
  amount: amount,
  type: IntakeTypeEntity.lunch,
  meal: MealEntity(
    code: 'apple',
    name: 'Apple',
    url: null,
    mealQuantity: null,
    mealUnit: mealUnit,
    servingQuantity: 200,
    servingUnit: 'g',
    servingSize: null,
    nutriments: const MealNutrimentsEntity(
      energyKcal100: 61,
      carbohydrates100: null,
      fat100: null,
      proteins100: null,
      sugars100: null,
      saturatedFat100: null,
      fiber100: null,
    ),
    source: MealSourceEntity.custom,
  ),
  dateTime: DateTime(2026, 10, 27),
);

void main() {
  test('one amount reads the same on every list', () {
    // 200 g is 7.05 oz: one decimal, as Home and Recently both show it.
    expect(amountText(_logged(200, 'g'), true), '7.1 oz');
    expect(amountText(_logged(200, 'g'), false), '200 g');
    expect(amountText(_logged(12.5, 'g'), false), '12.5 g');
    expect(amountText(_logged(250, 'ml'), true), '8.5 fl.oz');
    expect(amountText(_logged(100, 'g/ml'), true), '100 g');
  });
}
