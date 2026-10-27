import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/fork/food/result_groups.dart';

MealEntity _meal(String? name, MealSourceEntity source, {String? brand}) =>
    MealEntity(
      code: '$name$brand',
      name: name,
      brands: brand,
      url: null,
      mealQuantity: null,
      mealUnit: 'g',
      servingQuantity: null,
      servingUnit: 'g',
      servingSize: null,
      nutriments: MealNutrimentsEntity.empty(),
      source: source,
    );

MealEntity _off(String? name, [String? brand]) =>
    _meal(name, MealSourceEntity.off, brand: brand);

void main() {
  test('splits own foods, basic foods and products, in the given order', () {
    final mine = _meal('My rice', MealSourceEntity.custom);
    final recipe = _meal('Pilaf', MealSourceEntity.recipe);
    final usda = _meal('Rice, cooked', MealSourceEntity.fdc);
    final product = _off('Cooked Basmati Rice', 'A');
    final s = sectionResults([product, usda, mine, recipe]);
    expect(s.own, [mine, recipe]);
    expect(s.basic, [usda]);
    expect(s.products, [
      [product],
    ]);
  });

  test('products whose names hold the same words are one group, whatever '
      'the brand, case or order', () {
    final a = _off('Cooked Basmati Rice', 'A');
    final dry = _off('Basmati rice', 'F');
    final b = _off('basmati rice, cooked', 'B');
    final c = _off('Basmati Rice Cooked');
    final s = sectionResults([a, dry, b, c]);
    expect(s.products, [
      [a, b, c],
      [dry],
    ]);
  });

  test('products without a name are never grouped', () {
    final s = sectionResults([_off(null, 'A'), _off('', 'B')]);
    expect(s.products, hasLength(2));
  });

  test('a basic food is never grouped with a product of its name', () {
    final s = sectionResults([
      _meal('Rice, cooked', MealSourceEntity.fdc),
      _meal('Rice, cooked', MealSourceEntity.fdc),
      _off('Rice, cooked', 'A'),
    ]);
    expect(s.basic, hasLength(2));
    expect(s.products.single, hasLength(1));
  });
}
