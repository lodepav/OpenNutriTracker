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
      'plov 150g',
      'fries with pork 150g',
      'fries with pork - 150g',
      'fries with pork\n150g',
      '150g chicken, rice, broccoli',
      '150g chicken and rice',
      'chicken, rice, broccoli 150g',
      'chicken and rice 150g',
      'chicken\nrice 150g',
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

    test('a weight before one food is that food\'s', () {
      final w = noteWeights('200g rice')!;
      expect(w.totalGrams, isNull);
      expect(w.foods, [(name: 'rice', grams: 200.0)]);
    });

    test('a weight in the middle of the note is that food\'s', () {
      final w = noteWeights('rice, chicken 150g, spinach')!;
      expect(w.totalGrams, isNull);
      expect(w.foods, [(name: 'chicken', grams: 150.0)]);
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
    });

    test('without a total, an unweighed food keeps the model\'s grams', () {
      final items = weighedPlateItems([
        _g('chicken', 100),
        _g('rice', 200),
        const ParsedMealItem(query: 'egg', quantity: 2),
      ], const NoteWeights(foods: [(name: 'chicken', grams: 120)]));
      expect(items.map((i) => (i.quantity, i.unit)), [
        (120, 'g'),
        (200, 'g'),
        (2, null),
      ]);
    });

    test('a weight in the middle of a name is that food\'s', () {
      final w = noteWeights('panini with 200g beef')!;
      expect(w.totalGrams, isNull);
      expect(w.foods, [(name: 'beef', grams: 200.0)]);
      expect(
        noteWeights('burger with 180g beef patty, onion rings, cheddar')!.foods,
        [(name: 'beef patty', grams: 180.0)],
      );
      expect(noteWeights('burgers ar 180g liellopa')!.foods, [
        (name: 'liellopa', grams: 180.0),
      ]);
    });

    test('one food\'s weight among several is not the split dish\'s', () {
      final items = weighedPlateItems([
        const ParsedMealItem(query: 'dish=Panini'),
        _g('beef, ground, cooked', 200),
        _g('bread, ciabatta', 180),
      ], noteWeights('panini with 200g beef')!);
      expect(items.map((i) => (i.query, i.quantity)), [
        ('beef, ground, cooked', 200),
        ('bread, ciabatta', 180),
      ]);
      final chicken = weighedPlateItems([
        const ParsedMealItem(query: 'dish=Chicken rice'),
        _g('chicken breast, grilled', 150),
        _g('rice, white, cooked', 180),
      ], noteWeights('chicken 150g, rice')!);
      expect(chicken.first.quantity, 150);
    });

    test('bones take their share of the weight and are not logged', () {
      final items = weighedPlateItems([
        const ParsedMealItem(query: 'dish=BBQ ribs'),
        _g('pork, spareribs, cooked', 260),
        _g('coleslaw', 100),
        _g('Bones', 140),
      ], noteWeights('bbq pork ribs 500g')!);
      expect(items.map((i) => (i.query, i.quantity)), [
        ('pork, spareribs, cooked', 260),
        ('coleslaw', 100),
      ]);
      expect(items.every((i) => i is DishIngredientItem), isTrue);
      // Only the meat left is a plain row, at its share and not the plate's.
      final wings = weighedPlateItems([
        _g('chicken wings, fried', 165),
        _g('bones', 135),
      ], noteWeights('chicken wings 300g')!);
      expect(wings.map((i) => (i.query, i.quantity)), [
        ('chicken wings, fried', 165),
      ]);
    });

    test('a dish named and weighed adds up to its weight, split or not', () {
      // Haiku's reply to this note and its photo.
      final items = weighedPlateItems([
        const ParsedMealItem(query: 'dish=Dirty fries with pork'),
        _g('potatoes, french fried', 280),
        _g('pork, cooked, pulled', 150),
      ], noteWeights('dirty fries with pork 430g')!);
      expect(items.map((i) => i.quantity), [280, 150]);
      expect(items.every((i) => i.unit == 'g'), isTrue);
    });

    test('a weight before a dish the model splits is the whole dish\'s', () {
      final items = weighedPlateItems([
        const ParsedMealItem(query: 'dish=Plov'),
        _g('rice, white, cooked', 200),
        _g('lamb, cooked', 100),
      ], noteWeights('300g plov')!);
      expect(items.map((i) => i.quantity), [200, 100]);
    });

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

  group('a note with no amount (D25)', () {
    final photo = MealPhoto(bytes: Uint8List(1), mediaType: 'image/jpeg');

    test('takes the estimate, at the model\'s grams', () async {
      final api = _Api([_g('chicken plov', 350)]);
      final result = await ModelMealPhotoInterpreter(
        api,
      ).interpret(photo, note: 'chicken plov');
      expect(api.system, startsWith(estimatedPlatePrompt));
      expect(result.items.single, isNot(isA<DishIngredientItem>()));
      expect(
        (result.items.single.quantity, result.items.single.unit),
        (350, 'g'),
      );
    });

    test('several foods are one dish, each at its grams', () async {
      final api = _Api([
        const ParsedMealItem(query: 'dish=Chicken and rice'),
        _g('chicken breast, grilled', 120),
        _g('rice, white, cooked', 180),
      ]);
      final result = await ModelMealPhotoInterpreter(
        api,
      ).interpret(photo, note: 'chicken and rice');
      expect(
        [for (final i in result.items) (i.query, i.quantity)],
        [('chicken breast, grilled', 120), ('rice, white, cooked', 180)],
      );
      expect(result.items.map((i) => (i as DishIngredientItem).dish).toSet(), {
        'Chicken and rice',
      });
    });

    test('a count of patties is the dish\'s part, not a count of dishes', () {
      for (final note in [
        'smash burger with 3 patties',
        '3 patty smash burger',
        '3-patty burger',
        'burgers ar 2x kotletēm',
      ]) {
        expect(noteStatesNoAmount(note), isTrue, reason: note);
      }
      expect(noteStatesNoAmount('2 burgers with 3 patties'), isFalse);
      final w = noteWeights('smash burger with 3 patties 400g')!;
      expect(w.totalGrams, 400);
      expect(estimatedPlatePrompt, contains('with 3 patties'));
      expect(weighedPlatePrompt, contains('with 3 patties'));
    });

    test('a count or a weight in the note is not estimated', () {
      expect(noteStatesNoAmount('chicken plov'), isTrue);
      expect(noteStatesNoAmount('2 pork cutlets'), isFalse);
      expect(noteStatesNoAmount('half a pizza'), isFalse);
      expect(noteStatesNoAmount('plov 300g'), isFalse);
      expect(noteStatesNoAmount('  '), isFalse);
      expect(noteStatesNoAmount(null), isFalse);
    });

    test('a size is no amount: the model weighs the food by it', () {
      expect(
        noteStatesNoAmount('23 cm meat assortment wholegrain pizza'),
        isTrue,
      );
      expect(noteStatesNoAmount('a 12 inch tortilla'), isTrue);
      expect(noteStatesNoAmount('30cm pizza'), isTrue);
      expect(noteStatesNoAmount('2 30 cm pizzas'), isFalse);
      expect(estimatedPlatePrompt, contains('"a 23 cm pizza"'));
      // a named dish is split into its foods, its broth too
      expect(estimatedPlatePrompt, contains('a pizza is its crust'));
      expect(estimatedPlatePrompt, isNot(contains('Do not split')));
      // the oil on a salad is not seen, and is most of its energy
      expect(
        estimatedPlatePrompt,
        contains('A salad or slaw lists its dressing'),
      );
      // and so is the butter or oil a dish was cooked in
      expect(estimatedPlatePrompt, contains('Fat a food was cooked in'));
      // a soup's base is its liquid, not the soup, or its solids count twice
      expect(estimatedPlatePrompt, contains('never the soup itself'));
    });

    test(
      'with no note the plate is estimated too, and its grams kept (D42)',
      () async {
        final api = _Api([_g('rice', 200)]);
        final result = await ModelMealPhotoInterpreter(api).interpret(photo);
        expect(api.system, startsWith(noNotePlatePrompt));
        expect(result.items.single.quantity, 200);
        expect(result.items.single.unit, 'g');
      },
    );
  });
}
