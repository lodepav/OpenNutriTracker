// lib/fork/food/garnish_serving.dart: what a garnish starts at.
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/fork/food/garnish_serving.dart';

void main() {
  test('a herb starts at a pinch, grated cheese at a spoon', () {
    for (final name in [
      'Dill weed, fresh',
      'Parsley, raw',
      'Coriander (cilantro) leaves, raw',
      'Onions, green, raw',
      'Onions, spring or scallions (includes tops and bulb), raw',
      'Green Onion',
      'Fresh cilantro',
      'Chives, raw',
      'Garlic, raw',
      'Garlic cloves',
    ]) {
      expect(garnishGrams(name), 5, reason: name);
    }
    expect(garnishGrams('Cheese, parmesan, grated'), 10);
    expect(garnishGrams('Grated parmesan cheese'), 10);
    expect(garnishOunces('Cheese, parmesan, grated'), closeTo(0.35, 0.01));
  });

  test('a food that holds a herb or grated cheese is the food', () {
    for (final name in [
      'Garlic bread',
      'Garlic powder',
      'Pickles, dill',
      'Lemon dill sauce',
      'Onions, raw',
      'Spices, dill seed',
      'Pasta, with grated cheese',
      'Cheese, parmesan, hard',
      'Mint chocolate chip ice cream',
      null,
    ]) {
      expect(garnishGrams(name), isNull, reason: name);
    }
  });
}
