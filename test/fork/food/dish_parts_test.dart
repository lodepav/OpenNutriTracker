// A dish row beside the foods it already holds (S206): khachapuri, "cheese
// bread with egg", came with a fried egg and cheese besides.
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/usecase/resolve_parsed_meals_usecase.dart';
import 'package:opennutritracker/features/add_meal/util/meal_text_parser.dart';
import 'package:opennutritracker/fork/food/dish_parts.dart';

ResolvedMealItem _item(String query, String? row) => ResolvedMealItem(
  parsed: ParsedMealItem(query: query),
  candidates: [
    if (row != null)
      MealEntity(
        code: row,
        name: row,
        brands: null,
        url: null,
        mealQuantity: null,
        mealUnit: 'g',
        servingQuantity: null,
        servingUnit: 'g',
        servingSize: null,
        nutriments: MealNutrimentsEntity.empty(),
        source: MealSourceEntity.fdc,
      ),
  ],
  selectedIndex: 0,
  confidence: row == null ? 0 : 1,
);

List<String> _kept(List<ResolvedMealItem> items) => [
  for (final item in withoutDishParts(items)) item.parsed.query,
];

void main() {
  test('a food the dish row names is left out', () {
    expect(
      _kept([
        _item(
          'khachapuri adjaruli',
          'Khachapuri, Adjarian, cheese bread with egg (adjaruli)',
        ),
        _item('fried egg', 'Egg, whole, fried'),
        _item('cheese', 'Cheese, NFS'),
        _item('tomato', 'Tomatoes, raw'),
      ]),
      ['khachapuri adjaruli', 'tomato'],
    );
    expect(
      _kept([
        _item(
          'spaghetti bolognese',
          'Restaurant, Italian, spaghetti with meat sauce',
        ),
        _item('spaghetti, cooked', 'Pasta, cooked'),
      ]),
      ['spaghetti bolognese'],
    );
  });

  test('two rows of one food leave each other alone', () {
    expect(
      _kept([
        _item('fried egg', 'Egg, whole, fried'),
        _item('boiled egg', 'Egg, whole, boiled or poached'),
      ]),
      ['fried egg', 'boiled egg'],
    );
  });

  test('a dish nothing matched is broken down, so its parts go', () {
    expect(
      _kept([
        _item('buckwheat with meat and mushrooms', null),
        _item('beef stew meat', 'Beef, stew meat'),
        _item('mushrooms', 'Mushrooms, raw'),
        _item('fresh dill', 'Dill weed, fresh'),
      ]),
      ['buckwheat with meat and mushrooms', 'fresh dill'],
    );
  });

  test('a short name, matched or not, is no dish', () {
    expect(
      _kept([
        _item('cheese bread', null),
        _item('egg', 'Egg, raw'),
        _item('cheese', 'Cheese, NFS'),
        _item('rye bread', 'Bread, rye'),
      ]),
      ['cheese bread', 'egg', 'cheese', 'rye bread'],
    );
  });

  test('a side the dish does not name stays', () {
    expect(
      _kept([
        _item('borscht', 'Borscht, with beef (boršs)'),
        _item('sour cream', 'Cream, sour, cultured'),
        _item('rye bread', 'Bread, rye'),
      ]),
      ['borscht', 'sour cream', 'rye bread'],
    );
  });

  test('a drink beside a dish made with it stays', () {
    expect(
      _kept([
        _item(
          'mashed potatoes',
          'Potatoes, mashed, home-prepared, whole milk added',
        ),
        _item('glass of milk', 'Milk, whole, 3.25% milkfat'),
      ]),
      ['mashed potatoes', 'glass of milk'],
    );
    expect(
      _kept([
        _item(
          'oatmeal',
          'Oatmeal, regular or quick, made with milk, no added fat',
        ),
        _item('milk', 'Milk, whole, 3.25% milkfat'),
      ]),
      ['oatmeal', 'milk'],
    );
  });
}
