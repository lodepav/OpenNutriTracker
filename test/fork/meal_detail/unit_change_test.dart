import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/fork/meal_detail/unit_change.dart';

MealEntity _food(double serving) => MealEntity(
  code: 'x',
  name: 'x',
  url: null,
  mealQuantity: null,
  mealUnit: 'g',
  servingQuantity: serving,
  servingUnit: 'g',
  servingSize: null,
  nutriments: MealNutrimentsEntity.empty(),
  source: MealSourceEntity.custom,
);

void main() {
  test('a unit change keeps what the amount weighs', () {
    final food = _food(180);
    expect(amountInUnit('180', 'g', 'serving', food), '1');
    expect(amountInUnit('1', 'serving', 'g', food), '180');
    expect(amountInUnit('30', 'g', 'serving', food), '0.2');
    expect(amountInUnit('1', 'oz', 'g', food), '28');
  });

  test('a small amount never keeps its number under the new unit', () {
    expect(amountInUnit('4', 'g', 'serving', _food(100)), '0.04');
    expect(amountInUnit('0.1', 'g', 'serving', _food(100)), '0.01');
  });

  test('what is no amount converts to nothing', () {
    expect(amountInUnit('', 'g', 'serving', _food(100)), isNull);
    expect(amountInUnit('0', 'g', 'serving', _food(100)), isNull);
  });
}
