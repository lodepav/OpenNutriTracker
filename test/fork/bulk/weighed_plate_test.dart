import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/features/add_meal/data/model_meal_photo_interpreter.dart';
import 'package:opennutritracker/features/add_meal/domain/meal_items_api.dart';
import 'package:opennutritracker/features/add_meal/domain/meal_photo_interpreter.dart';
import 'package:opennutritracker/features/add_meal/util/meal_text_parser.dart';
import 'package:opennutritracker/fork/bulk/note_weights.dart';
import 'package:opennutritracker/fork/bulk/weighed_plate.dart';
import 'package:opennutritracker/fork/dish/dish_breakdown_rows.dart';

class _Api implements MealItemsApi {
  final List<ParsedMealItem> reply;
  String? system;

  _Api(this.reply);

  @override
  Future<MealTextParseResult> requestItems({
    required MealContent content,
    required String system,
  }) async {
    this.system = system;
    return MealTextParseResult(items: reply, errors: const []);
  }
}

ParsedMealItem _g(String query, double grams) =>
    ParsedMealItem(query: query, quantity: grams, unit: 'g');

void main() {
  group('noteWeights', () {
    for (final note in [
      'chicken, rice, broccoli. 150g total',
      'chicken, rice, broccoli - 150g',
      'chicken, rice, broccoli 150g:',
      '150g: chicken, rice, broccoli',
      'plov - 150g',
      '150g',
      '150 g total',
      '0.15 kg',
      '150 grams',
      'chicken, rice, broccoli = 150g',
      'chicken, rice, broccoli (150g)',
      'chicken, rice, broccoli, 150g',
      'chicken, rice, broccoli\n150g',
      'weighed 150g',
      'whole plate 150g',
      'bowl - 150g',
    ]) {
      test('"$note" is a 150 g plate', () {
        final w = noteWeights(note)!;
        expect(w.totalGrams, 150);
        expect(w.foods, isEmpty);
      });
    }

    for (final note in [
      'chicken 50g, rice 80g',
      'chicken - 50g, rice - 80g',
      'chicken: 50g, rice: 80g',
      'chicken 50g\nrice 80g',
      '- chicken 50g\n- rice 80g',
      'chicken 50g, rice 80g.',
    ]) {
      test('"$note" weighs each food', () {
        final w = noteWeights(note)!;
        expect(w.totalGrams, isNull);
        expect(w.foods, [
          (name: 'chicken', grams: 50.0),
          (name: 'rice', grams: 80.0),
        ]);
      });
    }

    test('a total beside a food\'s own weight keeps both', () {
      final w = noteWeights('total 400g, chicken 150g, potatoes, sauce')!;
      expect(w.totalGrams, 400);
      expect(w.foods, [(name: 'chicken', grams: 150.0)]);
    });

    test('a total after the foods\' own weights keeps them all', () {
      final w = noteWeights(
        'chicken 120g, rice 100g, spinach 30g - 250g total',
      )!;
      expect(w.totalGrams, 250);
      expect(w.foods, [
        (name: 'chicken', grams: 120.0),
        (name: 'rice', grams: 100.0),
        (name: 'spinach', grams: 30.0),
      ]);
    });

    test('a weight after a list with no separator is the last food\'s', () {
      final w = noteWeights('chicken, rice, spinach 350g')!;
      expect(w.totalGrams, isNull);
      expect(w.foods, [(name: 'spinach', grams: 350.0)]);
    });

    test('one food and its weight is that food\'s', () {
      final w = noteWeights('plov 350g')!;
      expect(w.totalGrams, isNull);
      expect(w.foods, [(name: 'plov', grams: 350.0)]);
    });

    test('counts and names alone state no weight', () {
      expect(noteWeights('2 eggs'), isNull);
      expect(noteWeights('200g rice, 2 eggs'), isNull);
      expect(noteWeights('sulguni'), isNull);
      expect(noteWeights(null), isNull);
    });
  });

  group('weighedPlateItems', () {
    test('a total is split by the model\'s grams and adds up exactly', () {
      final items = weighedPlateItems([
        const ParsedMealItem(query: 'dish=Chicken bowl'),
        _g('chicken breast, grilled', 100),
        _g('rice, white, cooked', 100),
        _g('spinach, raw', 33),
      ], const NoteWeights(totalGrams: 350));
      expect(items.map((i) => i.quantity), [150, 150, 50]);
      final first = items.first as DishIngredientItem;
      expect(first.dish, 'Chicken bowl');
      expect(first.dishGrams, 350);
      expect(
        items.every(
          (i) => identical((i as DishIngredientItem).group, first.group),
        ),
        isTrue,
      );
    });

    test(
      'a food the note weighs keeps its weight; the rest share the remainder',
      () {
        final items = weighedPlateItems(
          [
            _g('pork chop, fried', 200),
            _g('potatoes, boiled', 100),
            _g('sauce', 100),
          ],
          const NoteWeights(
            totalGrams: 400,
            foods: [(name: 'chop', grams: 150)],
          ),
        );
        expect(items.map((i) => i.quantity), [150, 125, 125]);
      },
    );

    test('stated weights are kept; a food the model missed is added', () {
      final items = weighedPlateItems(
        [
          _g('chicken breast, grilled', 80),
          _g('rice, white, cooked', 300),
          _g('carrots, raw', 10),
        ],
        const NoteWeights(
          foods: [
            (name: 'grilled chicken', grams: 120),
            (name: 'rice', grams: 100),
            (name: 'carrot', grams: 40),
            (name: 'beans', grams: 30),
          ],
        ),
      );
      expect(items.map((i) => (i.query, i.quantity)), [
        ('chicken breast, grilled', 120),
        ('rice, white, cooked', 100),
        ('carrots, raw', 40),
        ('beans', 30),
      ]);
      expect((items.first as DishIngredientItem).dishGrams, 290);
    });

    test(
      'without a total, the model\'s grams for an unweighed food are dropped',
      () {
        final items = weighedPlateItems([
          _g('chicken', 100),
          _g('rice', 200),
          const ParsedMealItem(query: 'egg', quantity: 2),
        ], const NoteWeights(foods: [(name: 'chicken', grams: 120)]));
        expect(items.map((i) => (i.quantity, i.unit)), [
          (120, 'g'),
          (null, null),
          (2, null),
        ]);
      },
    );

    test('one food is a plain row at the plate\'s weight', () {
      final items = weighedPlateItems([
        const ParsedMealItem(query: 'spaghetti bolognese'),
      ], const NoteWeights(totalGrams: 380));
      expect(items.single, isNot(isA<DishIngredientItem>()));
      expect((items.single.quantity, items.single.unit), (380, 'g'));
    });
  });

  test('a note with a weight takes the weighed-plate request', () async {
    final api = _Api([_g('chicken', 1), _g('rice', 1)]);
    final result = await ModelMealPhotoInterpreter(api).interpret(
      MealPhoto(bytes: Uint8List(1), mediaType: 'image/jpeg'),
      note: 'chicken, rice - 300g',
    );
    expect(api.system, startsWith(weighedPlatePrompt));
    expect(result.items.map((i) => i.quantity), [150, 150]);
  });
}
