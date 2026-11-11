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

/// A row the model called [query], matched to [matched] (or to itself).
BulkAddRow _row(String query, {String? matched, bool skipped = false}) =>
    BulkAddRow(
      resolved: ResolvedMealItem(
        parsed: ParsedMealItem(query: query, quantity: 100, unit: 'g'),
        candidates: [_food(matched ?? query)],
        selectedIndex: 0,
        confidence: 1,
      ),
      selectedIndex: 0,
      amountText: '100',
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
      expect(_ask(['coleslaw']), CookingFatAsk.salad);
      expect(_ask(['salāti']), CookingFatAsk.salad);
      expect(_ask(['салат оливье']), CookingFatAsk.salad);
    });

    test('a fried food beside a salad asks about cooking', () {
      expect(_ask(['egg, fried', 'salad']), CookingFatAsk.cooked);
    });

    test('from the food matched when the model\'s words do not say', () {
      final rows = [_row('potatoes', matched: 'Potatoes, roasted')];
      expect(cookingFatAskFor(rows), CookingFatAsk.cooked);
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
        'tomato sauce',
        'Sonnenblumenöl',
        'saulespuķu eļļa',
        'сливочное масло',
      ]) {
        expect(_ask(['egg, fried', fat]), isNull, reason: fat);
        expect(_ask(['salad', fat]), isNull, reason: fat);
      }
    });

    test('when a row\'s table food says fat was added', () {
      expect(_ask(['Asian stir fry vegetables, cooked, fat added']), isNull);
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
