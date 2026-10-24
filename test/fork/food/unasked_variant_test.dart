import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/fork/food/unasked_variant.dart';

void main() {
  test('a variant the query did not name trails', () {
    expect(unaskedVariant('Bacon, meatless', 'bacon'), unaskedVariantPenalty);
    expect(
      unaskedVariant('Vegan schnitzel', 'schnitzel'),
      unaskedVariantPenalty,
    );
    expect(
      unaskedVariant('Baby Toddler sweet potatoes', 'baby potatoes'),
      unaskedVariantPenalty,
    );
  });

  test('the variant the query names, and plain rows, keep their score', () {
    expect(unaskedVariant('Vegan schnitzel', 'vegan schnitzel'), 0);
    expect(unaskedVariant('Pork schnitzel, fried', 'schnitzel'), 0);
    // USDA's "unprepared" is the raw row a recipe wants, not a variant.
    expect(unaskedVariant('Pork, cured, bacon, unprepared', 'pork bacon'), 0);
    expect(unaskedVariant(null, 'bacon'), 0);
  });

  test('a row that is only the skin trails, unless the query says skin', () {
    for (final name in [
      'Potatoes, raw, skin',
      'Potatoes, boiled, cooked in skin, skin, with salt',
      'Chicken, skin (drumsticks and thighs), raw',
    ]) {
      expect(unaskedVariant(name, 'potatoes'), unaskedVariantPenalty);
    }
    expect(unaskedVariant('Potatoes, raw, skin', 'potato skin'), 0);
    for (final name in [
      'Potatoes, boiled, cooked in skin, flesh, with salt',
      'Chicken thigh, grilled, skin eaten',
      'Chicken thigh, skin removed before cooking',
      'Potatoes, flesh and skin, raw',
    ]) {
      expect(unaskedVariant(name, 'potatoes'), 0, reason: name);
    }
  });

  test('a pickled or turkey row trails, unless the query says so', () {
    expect(
      unaskedVariant('Tomato, green, pickled', 'tomato'),
      unaskedVariantPenalty,
    );
    expect(
      unaskedVariant('Bacon, turkey, unprepared', 'bacon'),
      unaskedVariantPenalty,
    );
    expect(unaskedVariant('Tomato, green, pickled', 'pickled tomato'), 0);
    expect(unaskedVariant('Cucumber, pickled', 'pickles'), 0);
    expect(unaskedVariant('Bacon, turkey, unprepared', 'turkey bacon'), 0);
    // A row titled turkey is the food asked for.
    expect(unaskedVariant('Turkey, ground, cooked', 'turkey'), 0);
  });

  test('a row named for lacking what the query names trails', () {
    expect(
      unaskedVariant(
        'Pizza, with meat other than pepperoni, stuffed crust',
        'pepperoni pizza',
      ),
      unaskedVariantPenalty,
    );
    expect(
      unaskedVariant('Coffee, without milk', 'coffee with milk'),
      unaskedVariantPenalty,
    );
    expect(
      unaskedVariant('Pizza, no cheese, thin crust', 'cheese pizza'),
      unaskedVariantPenalty,
    );
    expect(
      unaskedVariant('Pizza, with pepperoni, thin crust', 'pepperoni pizza'),
      0,
    );
    expect(unaskedVariant('Pizza, no cheese, thin crust', 'pizza'), 0);
  });
}
