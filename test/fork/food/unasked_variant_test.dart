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
}
