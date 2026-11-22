import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/features/add_meal/util/food_emoji_resolver.dart';

// G3 sweep: an almond is a tree nut, not the peanut 🥜 draws.
void main() {
  test('almonds draw a tree nut, peanuts the peanut', () {
    expect(resolveFoodEmoji('Almonds, raw'), '🌰');
    expect(resolveFoodEmoji('Almond'), '🌰');
    expect(resolveFoodEmoji('Peanuts, dry roasted'), '🥜');
  });
}
