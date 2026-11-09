// A row that is another food served with the one a name asks for (S205):
// "melted butter" found Brussels sprouts with melted butter.
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/fork/food/served_with.dart';

MealEntity _row(String name) => MealEntity(
  code: name,
  name: name,
  brands: null,
  url: null,
  mealQuantity: null,
  mealUnit: 'g',
  servingQuantity: null,
  servingUnit: 'g',
  servingSize: null,
  nutriments: MealNutrimentsEntity.empty(),
  source: MealSourceEntity.fdc,
);

List<String?> _kept(List<String> names, String query) => [
  for (final m in withoutServedWith([for (final n in names) _row(n)], query))
    m.name,
];

void main() {
  test('a food only in the row\'s "with" part is left out', () {
    expect(
      _kept([
        'Brussels sprouts, stewed, with melted butter',
        'Butter, salted',
      ], 'melted butter'),
      ['Butter, salted'],
    );
    expect(
      _kept([
        'Meatballs, NS as to type of meat, with sauce',
        'Ravioli, meat-filled, with cream sauce',
      ], 'meat sauce'),
      isEmpty,
    );
  });

  test('the food itself, with its sides, stays', () {
    expect(
      _kept(['Pork shish kabob with vegetables'], 'pork with vegetables'),
      ['Pork shish kabob with vegetables'],
    );
    expect(_kept(['Coffee, with milk'], 'coffee with milk'), [
      'Coffee, with milk',
    ]);
    expect(_kept(['Egg, whole, cooked, scrambled'], 'scrambled eggs'), [
      'Egg, whole, cooked, scrambled',
    ]);
  });

  test('a fork dish answers to the other names in its brackets', () {
    const dish = 'Sauteed cabbage with sausage (sautēti kāposti ar desu)';
    expect(_kept([dish], 'sautēti kāposti ar desu'), [dish]);
  });

  test('a one-word name is left alone', () {
    expect(_kept(['Potatoes, mashed, with butter'], 'butter'), [
      'Potatoes, mashed, with butter',
    ]);
  });

  test('a product holding no word of the name is left out', () {
    MealEntity off(String name) => MealEntity(
      code: name,
      name: name,
      brands: 'Brand',
      url: null,
      mealQuantity: null,
      mealUnit: 'g',
      servingQuantity: null,
      servingUnit: 'g',
      servingSize: null,
      nutriments: MealNutrimentsEntity.empty(),
      source: MealSourceEntity.off,
    );
    final kept = withoutUnrelatedProducts([
      off('Black beans'),
      off('Cheesy tomato bake'),
      off('Cheese and tomato casserole'),
      _row('Casserole, NFS'),
    ], 'baked casserole with cheese and tomato');
    expect(
      [for (final m in kept) m.name],
      ['Cheese and tomato casserole', 'Casserole, NFS'],
    );
    expect(
      withoutUnrelatedProducts([
        off('Creamy oat fraiche'),
      ], 'buckwheat with mushrooms and cream'),
      isEmpty,
    );
  });

  test('a row with none of the dish\'s "with" part is only part of it', () {
    final kept = withoutMissingSides([
      _row('Braised Red Cabbage'),
      _row('Cabbage, stewed, with sausage'),
    ], 'braised cabbage with sausage');
    expect([for (final m in kept) m.name], ['Cabbage, stewed, with sausage']);
    expect(
      withoutMissingSides([_row('Coffee, brewed')], 'coffee'),
      hasLength(1),
    );
  });
}
