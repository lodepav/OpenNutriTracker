import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/fork/food/dish_name.dart';

MealEntity _meal(String name, String? backendSource) => MealEntity(
  code: name,
  name: name,
  url: null,
  mealQuantity: null,
  mealUnit: 'g',
  servingQuantity: null,
  servingUnit: null,
  servingSize: null,
  source: MealSourceEntity.custom,
  backendSource: backendSource,
  nutriments: MealNutrimentsEntity.empty(),
);

void main() {
  test('a fork dish shows without its list of other names', () {
    expect(
      shownDishName(
        _meal('Plov, chicken (chicken pilaf, pilau, palov)', 'fork_dishes'),
      ),
      'Plov, chicken',
    );
    expect(
      shownDishName(_meal('Poke bowl, chicken (chicken poke)', 'fork_dishes')),
      'Poke bowl, chicken',
    );
  });

  test('a fork dish without one keeps its name', () {
    expect(
      shownDishName(
        _meal('Chicken saganaki, with tomato and feta', 'fork_dishes'),
      ),
      'Chicken saganaki, with tomato and feta',
    );
  });

  test('another food\'s brackets are part of its name', () {
    for (final (name, source) in [
      ('Aubergine, fried without fat (pan)', 'bls'),
      ('Pizza (with extra cheese)', 'fdc_sr_legacy'),
      ('My stew (big pot)', null),
    ]) {
      expect(shownDishName(_meal(name, source)), name);
    }
  });
}
