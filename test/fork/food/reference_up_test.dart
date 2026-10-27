import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/fork/food/reference_up.dart';

MealEntity _meal(String name, MealSourceEntity source) => MealEntity(
  code: name,
  name: name,
  url: null,
  mealQuantity: null,
  mealUnit: 'g',
  servingQuantity: null,
  servingUnit: 'g',
  servingSize: null,
  nutriments: MealNutrimentsEntity.empty(),
  source: source,
);

MealEntity _off(String name) => _meal(name, MealSourceEntity.off);
MealEntity _ref(String name) => _meal(name, MealSourceEntity.fdc);

List<String?> _names(List<MealEntity> meals) => [for (final m in meals) m.name];

void main() {
  test('the first three reference rows come second, fourth and sixth', () {
    final merged = [
      for (var i = 1; i <= 8; i++) _off('o$i'),
      for (var i = 1; i <= 4; i++) _ref('r$i'),
    ];
    expect(_names(referenceUp(merged)), [
      'o1', 'r1', 'o2', 'r2', 'o3', 'r3', //
      'o4', 'o5', 'o6', 'o7', 'o8', 'r4',
    ]);
  });

  test('a reference row already higher keeps its place', () {
    final merged = [_ref('r1'), _off('o1'), _off('o2'), _ref('r2')];
    expect(_names(referenceUp(merged)), ['r1', 'o1', 'o2', 'r2']);
  });

  test('the user\'s own meals and recipes stay above', () {
    final merged = [
      _meal('mine', MealSourceEntity.custom),
      _meal('recipe', MealSourceEntity.recipe),
      _off('o1'),
      _off('o2'),
      _ref('r1'),
    ];
    expect(_names(referenceUp(merged)), ['mine', 'recipe', 'o1', 'r1', 'o2']);
  });

  test('a list without remote rows is left as it is', () {
    final mine = [_meal('mine', MealSourceEntity.custom)];
    expect(referenceUp(mine), same(mine));
    expect(referenceUp(const []), isEmpty);
  });
}
