// Fork cases for textStatesAUnit (S169): an amount inside a phrase.
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/features/add_meal/util/meal_text_parser.dart';

void main() {
  group('a unit inside a phrase is a stated unit', () {
    for (final text in [
      'a 330 ml can of coke and a cheeseburger',
      '1 apple and 30 g almonds',
      'pelēkie zirņi ar speķi, 300 g',
      'a 1.5l bottle of water',
      'kefīrs 500 ml',
      '一碗200克米饭',
    ]) {
      test(text, () => expect(textStatesAUnit(text), isTrue));
    }
  });

  group('a letter that only looks like a unit is not one', () {
    for (final text in [
      'ein Glas Milch',
      '2 large eggs',
      '3 lemons and a glass of milk',
      'vitamin B12 tablet',
      'a bowl of borscht with sour cream',
    ]) {
      test(text, () => expect(textStatesAUnit(text), isFalse));
    }
  });

  test('the model\'s unit is kept for an amount inside a phrase', () {
    // Live Haiku 5.5 answered 330 ml; dropping the unit logged 330 servings.
    final result = validateParsedMealItems(const [
      ParsedMealItem(query: 'coke', quantity: 330, unit: 'ml'),
    ], statedIn: 'a 330 ml can of coke and a cheeseburger');

    expect(result.items.single.unit, 'ml');
    expect(result.items.single.quantity, 330);
  });
}
