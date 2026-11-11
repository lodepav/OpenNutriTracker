import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/usecase/resolve_parsed_meals_usecase.dart';
import 'package:opennutritracker/features/add_meal/presentation/bloc/bulk_add_bloc.dart';
import 'package:opennutritracker/features/add_meal/util/meal_text_parser.dart';
import 'package:opennutritracker/fork/bulk/cooking_fat.dart';
import 'package:opennutritracker/fork/bulk/put_row.dart';
import 'package:opennutritracker/fork/dish/dish_breakdown_rows.dart';

MealEntity _food(String name) => MealEntity(
  code: name,
  name: name,
  url: null,
  mealQuantity: null,
  mealUnit: 'g',
  servingQuantity: null,
  servingUnit: null,
  servingSize: null,
  source: MealSourceEntity.fdc,
  nutriments: MealNutrimentsEntity(
    energyKcal100: 100,
    carbohydrates100: 0,
    fat100: 0,
    proteins100: 0,
    sugars100: null,
    saturatedFat100: null,
    fiber100: null,
  ),
);

/// A row the model called [query], matched to [matched] (or to a plain
/// table food).
BulkAddRow _row(
  String query, {
  String? matched,
  bool skipped = false,
  String grams = '100',
}) => BulkAddRow(
  resolved: ResolvedMealItem(
    parsed: ParsedMealItem(
      query: query,
      quantity: double.tryParse(grams),
      unit: 'g',
    ),
    candidates: [_food(matched ?? 'Plain food')],
    selectedIndex: 0,
    confidence: 1,
  ),
  selectedIndex: 0,
  amountText: grams,
  unit: 'g',
  skipped: skipped,
  fromPhoto: true,
);

CookingFatAsk? _ask(List<String> queries, {String? note}) =>
    cookingFatAskFor([for (final q in queries) _row(q)], note: note);

void main() {
  group('asked', () {
    test('for a fried, roasted, sautéed, pan-seared or stir-fried food', () {
      for (final food in [
        'egg, fried',
        'potatoes, roasted',
        'roast pork',
        'mushrooms, sautéed',
        'onions, sauteed',
        'salmon, pan-seared',
        'chicken breast, pan fried',
        'vegetables, stir-fried',
        'beef stir fry',
      ]) {
        expect(
          _ask([food, 'rice, white, cooked']),
          CookingFatAsk.cooked,
          reason: food,
        );
      }
    });

    test('in the words of the other languages a dish may be named in', () {
      for (final food in [
        'Bratkartoffeln, gebraten',
        'ceptas kartupeļi',
        'kepta žuvis',
        'kotlet smażony',
        'жареная картошка',
      ]) {
        expect(_ask([food]), CookingFatAsk.cooked, reason: food);
      }
    });

    test('a salad with nothing to dress it asks about dressing', () {
      expect(_ask(['salad, mixed greens', 'bread']), CookingFatAsk.salad);
      expect(_ask(['salāti']), CookingFatAsk.salad);
      expect(_ask(['green salad']), CookingFatAsk.salad);
      expect(_ask(['side salad']), CookingFatAsk.salad);
    });

    test('a fried food beside a salad asks about cooking', () {
      expect(_ask(['egg, fried', 'salad']), CookingFatAsk.cooked);
    });

    test('for a fried food the table weighs fried without fat', () {
      final rows = [
        _row('fried aubergine', matched: 'Aubergine, fried without fat (pan)'),
      ];
      expect(cookingFatAskFor(rows), CookingFatAsk.cooked);
      for (final table in [
        'Bakłażan smażony bez tłuszczu',
        'Aubergine, gebraten ohne Fettzugabe',
      ]) {
        expect(
          cookingFatAskFor([_row('fried aubergine', matched: table)]),
          CookingFatAsk.cooked,
          reason: table,
        );
      }
      // "no salt" is no word on the fat
      final fries = [
        _row('fried potatoes', matched: 'Potatoes, home fries, no salt'),
      ];
      expect(cookingFatAskFor(fries), isNull);
    });

    test('for fried potatoes matched to a plain potato', () {
      final rows = [_row('fried potatoes', matched: 'Potato, boiled')];
      expect(cookingFatAskFor(rows), CookingFatAsk.cooked);
    });

    test('for the table\'s green salad without dressing', () {
      final rows = [
        _row('green salad', matched: 'Salad, green, without dressing'),
      ];
      expect(cookingFatAskFor(rows), CookingFatAsk.salad);
      expect(_ask(['salad, no dressing']), CookingFatAsk.salad);
      expect(_ask(['Salat ohne Dressing']), CookingFatAsk.salad);
      expect(_ask(['салат без масла']), CookingFatAsk.salad);
    });

    test('about the salad beside home fries', () {
      final rows = [
        _row('fried potatoes', matched: 'Potatoes, home fries'),
        _row('green salad', matched: 'Salad, green, without dressing'),
      ];
      expect(cookingFatAskFor(rows), CookingFatAsk.salad);
    });

    test('for more when the fat rows come to under 10 g', () {
      expect(
        cookingFatAskFor([_row('green salad'), _row('olive oil', grams: '8')]),
        CookingFatAsk.saladMore,
      );
      expect(
        cookingFatAskFor([
          _row('egg, fried'),
          _row('butter', grams: '5'),
          _row('olive oil', grams: '4'),
          _row('butter', grams: '20', skipped: true),
        ]),
        CookingFatAsk.cookedMore,
      );
    });

    test('from the dish a food belongs to', () {
      final row = BulkAddRow(
        resolved: ResolvedMealItem(
          parsed: DishIngredientItem(
            query: 'rice',
            quantity: 200,
            unit: 'g',
            dish: 'Fried rice',
            group: Object(),
          ),
          candidates: [_food('rice')],
          selectedIndex: 0,
          confidence: 1,
        ),
        selectedIndex: 0,
        amountText: '200',
        unit: 'g',
        fromPhoto: true,
      );
      expect(cookingFatAskFor([row]), CookingFatAsk.cooked);
    });
  });

  group('not asked', () {
    test('when a fat, oil, butter, dressing, mayonnaise or sauce is there', () {
      for (final fat in [
        'olive oil',
        'butter',
        'vinaigrette',
        'ranch dressing',
        'mayonnaise',
        'hollandaise',
        'sauce béarnaise',
        'fettuccine alfredo',
        'pesto',
        'tartar sauce',
        'Sauce, cheese',
        'garlic sauce',
        'butter sauce',
        'Sonnenblumenöl',
        'saulespuķu eļļa',
        'сливочное масло',
      ]) {
        expect(_ask(['egg, fried', fat]), isNull, reason: fat);
        expect(_ask(['salad', fat]), isNull, reason: fat);
      }
    });

    test('fried fish with tartar sauce', () {
      expect(_ask(['fish, fried', 'tartar sauce']), isNull);
    });

    test('when the model\'s words say fat was added', () {
      expect(_ask(['Asian stir fry vegetables, cooked, fat added']), isNull);
    });

    test('when a fried food is matched to a table food that holds its fat', () {
      final rows = [_row('fried potatoes', matched: 'Potatoes, home fries')];
      expect(cookingFatAskFor(rows), isNull);
      final roasted = [_row('potatoes', matched: 'Potatoes, roasted')];
      expect(cookingFatAskFor(roasted), isNull);
      final added = [
        _row('chicken, fried', matched: 'Chicken breast, cooked, fat added'),
      ];
      expect(cookingFatAskFor(added), isNull);
    });

    test('french fries alone: the table\'s hold their frying fat', () {
      expect(_ask(['french fries']), isNull);
      expect(_ask(['French fries, fast food']), isNull);
    });

    test('nothing cooked in fat and no salad', () {
      expect(_ask(['rice, white, cooked', 'chicken breast, grilled']), isNull);
      expect(_ask(['soup, lentil']), isNull);
      expect(_ask(['almonds, dry roasted']), isNull);
    });

    test('a sauce or gravy by itself is no fat', () {
      expect(
        _ask(['eggs, fried', 'baked beans in tomato sauce']),
        CookingFatAsk.cooked,
      );
      final rows = [
        _row('chicken with gravy'),
        _row('roasted potatoes', matched: 'Potato, baked'),
      ];
      expect(cookingFatAskFor(rows), CookingFatAsk.cooked);
      expect(_ask(['жареная картошка', 'томатный соус']), CookingFatAsk.cooked);
      expect(_ask(['pork, fried', 'Soße']), CookingFatAsk.cooked);
    });

    test('a nut butter, buttermilk or olives are no fat', () {
      expect(_ask(['egg, fried', 'peanut butter']), CookingFatAsk.cooked);
      expect(_ask(['egg, fried', 'buttermilk']), CookingFatAsk.cooked);
      expect(_ask(['жареная картошка', 'маслины']), CookingFatAsk.cooked);
    });

    test('on a weighed plate', () {
      expect(_ask(['egg, fried'], note: '250 g'), isNull);
    });

    test('for rows left out', () {
      expect(cookingFatAskFor([_row('egg, fried', skipped: true)]), isNull);
      expect(
        cookingFatAskFor([_row('egg, fried'), _row('butter', skipped: true)]),
        CookingFatAsk.cooked,
      );
    });

    test('with 10 g of fat rows or more together, or a fat row with no '
        'weight', () {
      expect(
        cookingFatAskFor([
          _row('green salad'),
          _row('mayonnaise', grams: '25'),
        ]),
        isNull,
      );
      expect(
        cookingFatAskFor([
          _row('egg, fried'),
          _row('olive oil', grams: '5'),
          _row('butter', grams: '5'),
        ]),
        isNull,
      );
      expect(
        cookingFatAskFor([_row('egg, fried'), _row('butter', grams: 'some')]),
        isNull,
      );
    });

    test('for a salad dressed by definition', () {
      for (final salad in [
        'coleslaw',
        'potato salad',
        'pasta salad',
        'egg salad',
        'Caesar salad',
        'Russian salad',
        'салат оливье',
        'Kartoffelsalat',
        'sałatka jarzynowa',
      ]) {
        expect(_ask([salad]), isNull, reason: salad);
      }
      // greens with grilled chicken or tuna are still dressed at the table
      expect(_ask(['grilled chicken salad']), CookingFatAsk.salad);
      expect(_ask(['tuna salad']), CookingFatAsk.salad);
      // and it is no fat beside a plain salad
      expect(_ask(['coleslaw', 'green salad']), CookingFatAsk.salad);
    });

    test('schnitzel, bacon and coleslaw', () {
      final rows = [
        _row('pork schnitzel, fried', matched: 'Pork schnitzel, breaded'),
        _row('bacon, fried', matched: 'Bacon, pan-fried'),
        _row('coleslaw', matched: 'Coleslaw'),
      ];
      expect(cookingFatAskFor(rows), isNull);
    });

    test('eggs, hash browns and a little butter', () {
      final rows = [
        _row('eggs', matched: 'Egg, whole, cooked'),
        _row(
          'fried hash browns',
          matched: 'Potatoes, hash brown, home-prepared',
        ),
        _row('butter', grams: '5'),
      ];
      expect(cookingFatAskFor(rows), isNull);
    });

    test('for the foods fried by definition', () {
      for (final food in [
        'Potato rösti',
        'Corn fritters',
        'Shrimp tempura',
        'Chicken nuggets',
        'Croquettes, potato',
        'Doughnut, glazed',
        'Potato crisps',
        'Kartupeļu čipsi',
        'Картофельные чипсы',
        'Kartoffelpuffer',
      ]) {
        expect(
          cookingFatAskFor([_row('fried $food', matched: food)]),
          isNull,
          reason: food,
        );
      }
    });

    test('for no rows', () {
      expect(cookingFatAskFor(const []), isNull);
    });
  });

  test('a chip is the one at the row\'s grams', () {
    expect(cookingFatChipOf('5'), 0);
    expect(cookingFatChipOf('10'), 1);
    expect(cookingFatChipOf('20'), 2);
    expect(cookingFatChipOf('15'), isNull);
    expect(cookingFatText(10), '10');
  });

  group('a row put', () {
    final state = BulkAddLoadedState(
      rows: [_row('egg, fried')],
      parseErrors: const [],
      usesImperialUnits: false,
      source: BulkAddReadSource.photo,
    );
    final oil = _row('sunflower oil');

    test('is added after the others, then changed in place', () {
      final added = putRow(state, PutRowEvent(oil.resolved, oil));
      expect(added.rows, [state.rows.single, oil]);
      final changed = putRow(
        added,
        PutRowEvent(oil.resolved, oil.copyWith(amountText: '20')),
      );
      expect(changed.rows.length, 2);
      expect(changed.rows.last.amountText, '20');
    });

    test('is taken off; nothing to take off leaves the state', () {
      final added = putRow(state, PutRowEvent(oil.resolved, oil));
      expect(putRow(added, PutRowEvent(oil.resolved, null)).rows, state.rows);
      expect(putRow(state, PutRowEvent(oil.resolved, null)), same(state));
    });

    test('of another item is refused', () {
      expect(
        putRow(state, PutRowEvent(oil.resolved, _row('butter'))),
        same(state),
      );
    });
  });
}
