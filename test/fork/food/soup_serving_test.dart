// lib/fork/food/soup_serving.dart: which foods start at a bowl.
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/fork/food/soup_serving.dart';

void main() {
  test('a soup is one, a garnish, cube or powder for one is not', () {
    for (final name in [
      'Beetroot soup, with apple and horseradish',
      '"Borschtsch" (beetroot soup)',
      'Soup, borscht',
      'Chicken broth',
      'Fish consomme',
      'Chłodnik',
      'Miso soup',
    ]) {
      expect(isSoup(name), isTrue, reason: name);
    }
    for (final name in [
      'Beef bouillon/stock/soup (stock cubes, powder)',
      'Liver dumpling as soup garnish',
      'Vegetables as ingredient in soups',
      'Egg added to soups',
      'Cream of mushroom soup instant powder',
      'Soup, chicken noodle, dry, mix',
      'Bouillon potatoes (with meat stock)',
      'Soup pearls',
      'Beetroot, raw',
      null,
    ]) {
      expect(isSoup(name), isFalse, reason: name);
    }
  });
}
