import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_portion_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/usecase/resolve_parsed_meals_usecase.dart';
import 'package:opennutritracker/features/add_meal/presentation/bloc/bulk_add_bloc.dart';
import 'package:opennutritracker/features/add_meal/util/meal_text_parser.dart';
import 'package:opennutritracker/fork/bulk/amount_question.dart';

MealEntity _food(
  String name, {
  double kcal100 = 100,
  String mealUnit = 'g',
  List<MealPortionEntity> portions = const [],
  double? serving,
  String? servingSize,
}) => MealEntity(
  code: name,
  name: name,
  url: null,
  mealQuantity: null,
  mealUnit: mealUnit,
  servingQuantity: serving,
  servingUnit: serving == null ? null : 'g',
  servingSize: servingSize,
  source: MealSourceEntity.fdc,
  portions: portions,
  nutriments: MealNutrimentsEntity(
    energyKcal100: kcal100,
    carbohydrates100: 0,
    fat100: 0,
    proteins100: 0,
    sugars100: null,
    saturatedFat100: null,
    fiber100: null,
  ),
);

MealPortionEntity _portion(String label, double grams) =>
    MealPortionEntity(label: label, gramWeight: grams, localized: true);

BulkAddRow _row(
  String amount,
  String unit, {
  MealEntity? food,
  String name = 'rice',
  String? parsedUnit = 'g',
  double? quantity,
  bool skipped = false,
}) => BulkAddRow(
  resolved: ResolvedMealItem(
    parsed: ParsedMealItem(
      query: name,
      quantity: quantity ?? double.tryParse(amount),
      unit: parsedUnit,
    ),
    candidates: [food ?? _food(name)],
    selectedIndex: 0,
    confidence: 1,
  ),
  selectedIndex: 0,
  amountText: amount,
  unit: unit,
  skipped: skipped,
  fromPhoto: true,
);

List<String> _labels(List<AmountChoice>? choices) => [
  for (final c in choices!) c.label,
];

AmountChoice _estimate(List<AmountChoice>? choices) =>
    choices!.singleWhere((c) => c.estimate);

void main() {
  group('which row', () {
    test('the one with the most energy among those a size may scale', () {
      final rows = [
        _row('150', 'g', name: 'rice'),
        _row('120', 'g', name: 'chicken', food: _food('chicken', kcal100: 200)),
        _row('300', 'g', name: 'salad', food: _food('salad', kcal100: 20)),
      ];
      final question = amountQuestionFor(rows, imperial: false)!;
      expect(question.isFor(rows[1]), isTrue);
      expect(question.food, 'chicken');
    });

    test('not one left out, nor one the user set', () {
      final rows = [
        _row('500', 'g', name: 'rice', skipped: true),
        _row('120', 'g', name: 'chicken'),
        _row('150', 'g', name: 'pasta'),
      ];
      final question = amountQuestionFor(
        rows,
        imperial: false,
        pinned: (row) => identical(row, rows[2]),
      )!;
      expect(question.isFor(rows[1]), isTrue);
    });

    test('none on a weighed plate, nor when every count is stated', () {
      final rows = [_row('150', 'g'), _row('100', 'g', name: 'chicken')];
      expect(amountQuestionFor(rows, note: '150 g', imperial: false), isNull);
      final eggs = [_row('2', 'serving', name: 'egg', parsedUnit: null)];
      expect(amountQuestionFor(eggs, note: '2 eggs', imperial: false), isNull);
      expect(amountQuestionFor(const [], imperial: false), isNull);
    });

    test('stands while its row is there with its match', () {
      final rows = [_row('150', 'g')];
      final question = amountQuestionFor(rows, imperial: false)!;
      expect(question.standsIn(rows), isTrue);
      expect(question.standsIn([rows[0].copyWith(amountText: '90')]), isTrue);
      expect(question.standsIn([_row('150', 'g')]), isFalse);
      expect(question.standsIn([rows[0].copyWith(selectedIndex: 1)]), isFalse);
    });
  });

  group('the food as asked', () {
    test('lower case, acronyms kept, long names cut at a comma', () {
      expect(questionFood('Chicken Breast'), 'chicken breast');
      expect(questionFood('BBQ Sauce'), 'BBQ sauce');
      expect(
        questionFood('Chicken, broilers or fryers, breast, roasted'),
        'chicken',
      );
      expect(questionFood('Rice, white'), 'rice, white');
    });
  });

  group('rounding', () {
    test('to 5 below 100, 10 to 300, 25 above; ounces to a half', () {
      expect(friendlyAmount(72, 'g'), 70);
      expect(friendlyAmount(112.5, 'g'), 110);
      expect(friendlyAmount(225, 'ml'), 230);
      expect(friendlyAmount(340, 'g'), 350);
      expect(friendlyAmount(2.65, 'oz'), 2.5);
      expect(friendlyAmount(7.95, 'fl.oz'), 8);
    });

    test('four counts, always the estimate', () {
      expect(countChoices(1), [0.5, 1, 2, 3]);
      expect(countChoices(2), [1, 2, 3, 4]);
      expect(countChoices(0.5), [0.5, 1, 2, 3]);
      expect(countChoices(1.5), [1, 1.5, 2, 3]);
      expect(countChoices(3), [2, 3, 4, 5]);
      expect(countChoices(12), [11, 12, 13, 14]);
      expect(countChoices(2.5), [2, 2.5, 3, 4]);
    });

    test('a piece is one counted thing, not a measure nor many', () {
      expect(pieceWord('1 slice (32 g)'), 'slice');
      expect(pieceWord('1 large egg'), 'large egg');
      expect(pieceWord('1 medium (7" long)'), 'medium');
      expect(pieceWord('1 cup, chopped'), isNull);
      expect(pieceWord('1 package'), isNull);
      expect(pieceWord('1 serving'), isNull);
      expect(pieceWord('100 g'), isNull);
    });
  });

  group('chips', () {
    test('grams at about ½, ¾, 1 and 1½, the estimate as it is', () {
      final choices = amountChoices(_row('150', 'g'), imperial: false);
      expect(_labels(choices), ['75 g', '110 g', '150 g', '230 g']);
      expect(_estimate(choices).text, '150');
      expect(_estimate(choices).unit, 'g');
      expect(choices![0].spoken, '75 grams');
      expect(choices[0].unit, 'g');
    });

    test('millilitres for a drink', () {
      final row = _row('250', 'ml', food: _food('milk', mealUnit: 'ml'));
      expect(_labels(amountChoices(row, imperial: false)), [
        '130 ml',
        '190 ml',
        '250 ml',
        '375 ml',
      ]);
    });

    test('a chip that rounds onto another goes', () {
      final choices = amountChoices(_row('8', 'g'), imperial: false);
      expect(_labels(choices), ['5 g', '8 g', '10 g']);
    });

    test('ounces where an imperial profile shows the row in them; the '
        'estimate keeps the row\'s grams', () {
      final choices = amountChoices(_row('150', 'g'), imperial: true);
      expect(_labels(choices), ['2.5 oz', '4 oz', '5.3 oz', '8 oz']);
      expect(choices![0].spoken, '2.5 ounces');
      expect(choices[0].unit, 'oz');
      expect(_estimate(choices).unit, 'g');
      expect(_estimate(choices).text, '150');
    });

    test('counts on a row in pieces', () {
      final bread = _food(
        'bread',
        portions: [_portion('1 slice (32 g)', 32), _portion('1 cup', 45)],
      );
      final choices = amountChoices(
        _row('2', 'serving', food: bread, name: 'bread', parsedUnit: null),
        imperial: false,
      );
      expect(_labels(choices), ['1 slice', '2 slices', '3 slices', '4 slices']);
      expect(_estimate(choices).text, '2');
      expect(choices![1].spoken, '2 slices');

      final one = amountChoices(
        _row('1', 'serving', food: bread, name: 'bread', parsedUnit: null),
        imperial: false,
      );
      expect(_labels(one).first, '½ slice');
      expect(one!.first.spoken, 'half a slice');
    });

    test('grams on a row in a measure, in the row\'s weight', () {
      final rice = _food('rice', portions: [_portion('1 cup', 160)]);
      final choices = amountChoices(
        _row('1', 'serving', food: rice, parsedUnit: null),
        imperial: false,
      );
      expect(_labels(choices), ['80 g', '120 g', '160 g', '240 g']);
      expect(choices![0].unit, 'g');
      expect(_estimate(choices).unit, 'serving');
      expect(_estimate(choices).text, '1');
    });

    test('counts on a row in grams of a counted food, the nearest '
        'chosen', () {
      final egg = _food('egg', portions: [_portion('1 large', 50)]);
      final choices = amountChoices(
        _row('110', 'g', food: egg, name: 'egg'),
        imperial: false,
      );
      expect(_labels(choices), ['1 large', '2 large', '3 large', '4 large']);
      expect(_estimate(choices).label, '2 large');
      // confirming keeps the row's own grams
      expect(_estimate(choices).unit, 'g');
      expect(_estimate(choices).text, '110');
      expect(choices![2].unit, 'serving');
      expect(choices[2].text, '3');

      final sausage = _food('sausage', serving: 75, servingSize: '1 sausage');
      expect(
        _labels(
          amountChoices(
            _row('150', 'g', food: sausage, name: 'sausage'),
            imperial: false,
          ),
        ),
        ['1 sausage', '2 sausages', '3 sausages', '4 sausages'],
      );
    });

    test('a medium piece before others', () {
      final apple = _food(
        'apple',
        portions: [
          _portion('1 small', 150),
          _portion('1 medium', 200),
          _portion('1 cup, sliced', 110),
        ],
      );
      final choices = amountChoices(
        _row('400', 'g', food: apple, name: 'apple'),
        imperial: false,
      );
      expect(_estimate(choices).label, '2 medium');
      expect(choices!.last.unit, 'serving#1');
    });
  });
}
