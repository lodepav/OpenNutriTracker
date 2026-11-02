import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/fork/amounts/amount_units.dart';
import 'package:opennutritracker/fork/amounts/own_portions.dart';

import 'amount_test_foods.dart';

void main() {
  group('the unit chips', () {
    List<String> units(options) => [for (final o in options) o.unit as String];

    test('portions first, then one weight for the profile', () {
      expect(
        units(amountUnitOptions(bread(), selected: 'g', imperial: false)),
        ['serving', 'serving#1', 'g'],
      );
      expect(
        units(amountUnitOptions(bread(), selected: 'oz', imperial: true)),
        ['serving', 'serving#1', 'oz'],
      );
    });

    test('a drink takes a volume, a food of unknown kind grams', () {
      expect(
        units(
          amountUnitOptions(
            rye(mealUnit: 'ml'),
            selected: 'ml',
            imperial: false,
          ),
        ),
        ['serving', 'ml'],
      );
      expect(
        units(
          amountUnitOptions(
            rye(serving: null, mealUnit: ''),
            selected: 'g/ml',
            imperial: false,
          ),
        ),
        ['g/ml'],
      );
    });

    test('the unit the page opened at is always among them', () {
      expect(
        units(amountUnitOptions(bread(), selected: 'oz', imperial: false)),
        ['serving', 'serving#1', 'g', 'oz'],
      );
    });

    test("the user's own portions come after the food's", () {
      final meal = withOwnPortions(bread(), const [
        OwnPortionEntity(label: 'thick slice', gramWeight: 45),
      ]);
      final options = amountUnitOptions(meal, selected: 'g', imperial: false);
      expect(units(options), ['serving', 'serving#1', 'serving#2', 'g']);
      expect(options[2].own, isTrue);
      expect(options[2].grams, 45);
    });
  });

  group('own portions', () {
    const slice = OwnPortionEntity(label: 'slice', gramWeight: 35);

    test('a food with only a serving keeps it first', () {
      final meal = withOwnPortions(rye(), const [slice]);
      expect(meal.portions.map((p) => p.gramWeight), [50, 35]);
    });

    test('a food with nothing but grams takes them alone', () {
      final meal = withOwnPortions(rye(serving: null), const [slice]);
      expect(meal.portions, [slice]);
    });

    test('applied again, they are not doubled; none leaves the food', () {
      final once = withOwnPortions(bread(), const [slice]);
      expect(withOwnPortions(once, const [slice]).portions.length, 3);
      expect(withOwnPortions(once, const []).portions.length, 2);
      expect(withOwnPortions(rye(), const []).portions, isEmpty);
    });

    test('are remembered by name, and found again where they now are', () {
      final meal = withOwnPortions(bread(), const [slice]);
      expect(rememberedUnitOf(meal, 'serving#2'), 'own:slice');
      expect(rememberedUnitOf(meal, 'serving#1'), 'serving#1');
      expect(rememberedUnitOf(meal, 'g'), 'g');
      expect(unitFromRemembered(meal, 'own:slice'), 'serving#2');
      // Without the food's portions, as from the diary, it is first.
      expect(
        unitFromRemembered(
          withOwnPortions(rye(serving: null), const [slice]),
          'own:slice',
        ),
        'serving',
      );
      expect(unitFromRemembered(bread(), 'own:slice'), isNull);
      expect(unitFromRemembered(bread(), 'g'), 'g');
    });
  });

  group('the stepper', () {
    test('moves by a portion, 10 g or an ounce', () {
      expect(amountStep('serving#1', 2), 1);
      expect(amountStep('serving', 0.5), 0.5);
      expect(amountStep('g', 64), 10);
      expect(amountStep('oz', 3), 1);
    });

    test('onto the grid, never below one step', () {
      expect(steppedAmount(64, 10, up: true), 70);
      expect(steppedAmount(64, 10, up: false), 60);
      expect(steppedAmount(70, 10, up: true), 80);
      expect(steppedAmount(70, 10, up: false), 60);
      expect(steppedAmount(1, 1, up: true), 2);
      expect(steppedAmount(1, 1, up: false), 1);
      expect(steppedAmount(1.5, 0.5, up: false), 1);
    });
  });

  group('a weight that is a number of portions', () {
    test('64 g of bread is 2 slices', () {
      final meal = bread();
      final options = amountUnitOptions(meal, selected: 'g', imperial: false);
      final fits = portionThatFits(meal, options, 'g', 64)!;
      expect(fits.option.unit, 'serving');
      expect(fits.count, 2);
    });

    test('within 5%, and halves count', () {
      final meal = bread();
      final options = amountUnitOptions(meal, selected: 'g', imperial: false);
      expect(portionThatFits(meal, options, 'g', 66)?.count, 2);
      expect(portionThatFits(meal, options, 'g', 48)?.count, 1.5);
      expect(portionThatFits(meal, options, 'g', 75), isNull);
      expect(portionThatFits(meal, options, 'g', 10), isNull);
    });

    test("the user's own portion first", () {
      final meal = withOwnPortions(bread(), const [
        OwnPortionEntity(label: 'my slice', gramWeight: 64),
      ]);
      final options = amountUnitOptions(meal, selected: 'g', imperial: false);
      final fits = portionThatFits(meal, options, 'g', 64)!;
      expect(fits.option.own, isTrue);
      expect(fits.count, 1);
    });

    test('not offered for an amount already in portions', () {
      final meal = bread();
      final options = amountUnitOptions(meal, selected: 'g', imperial: false);
      expect(portionThatFits(meal, options, 'serving', 2), isNull);
    });
  });
}
