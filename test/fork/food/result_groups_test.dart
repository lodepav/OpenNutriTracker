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

  test('basic foods keep the Food search\'s order', () {
    final pickled = _meal('Tomato, green, pickled', MealSourceEntity.fdc);
    final raw = _meal('Tomatoes, raw', MealSourceEntity.fdc);
    final s = sectionResults([pickled, raw], basicOrder: [raw, pickled]);
    expect(s.basic, [raw, pickled]);
  });

  test('a product named for none of the words goes last', () {
    final byBrand = _off('Complete Sleep Formula', 'RAW');
    final cashews = _off('Cashews', 'A');
    final s = sectionResults([byBrand, cashews], query: 'cashews, raw');
    expect(s.products, [
      [cashews],
      [byBrand],
    ]);
  });

  test('a plural is the same product as its singular', () {
    final a = _off('Chicken Breasts', 'A');
    final b = _off('chicken breast', 'B');
    final c = _off('Cherries', 'C');
    final d = _off('cherry', 'D');
    final glass = _off('Glass', 'E');
    final s = sectionResults([a, b, c, d, glass]);
    expect(s.products, [
      [a, b],
      [c, d],
      [glass],
    ]);
  });

  test('a product far outside its group\'s range is listed last', () {
    MealEntity rice(String brand, double kcal) => MealEntity(
      code: brand,
      name: 'Cooked Basmati Rice',
      brands: brand,
      url: null,
      mealQuantity: null,
      mealUnit: 'g',
      servingQuantity: null,
      servingUnit: 'g',
      servingSize: null,
      nutriments: MealNutrimentsEntity(
        energyKcal100: kcal,
        carbohydrates100: null,
        fat100: null,
        proteins100: null,
        sugars100: null,
        saturatedFat100: null,
        fiber100: null,
      ),
      source: MealSourceEntity.off,
    );
    final odd = rice('Heb', 345);
    final a = rice('A', 125), b = rice('B', 131), c = rice('C', 140);
    expect(sectionResults([a, odd, b, c]).products.single, [a, b, c, odd]);
  });

  test('a group\'s range leaves out values far from the middle', () {
    expect(typicalRange([]), isNull);
    expect(typicalRange([125, 345]), (low: 125.0, high: 345.0));
    expect(typicalRange([125, 131, 140, 146, 345]), (low: 125.0, high: 146.0));
    expect(typicalRange([95, 567, 586, 633, 643]), (low: 567.0, high: 643.0));
  });
}
