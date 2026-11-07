import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/fork/food/drink_serving.dart';

void main() {
  test('a drink is one a glass or mug of is the usual amount', () {
    for (final name in [
      'apple juice',
      'Juice, apple and grape blend',
      'Black Tea',
      'Tea, hot, leaf, black',
      'coffee',
      'Cola',
      'kefir',
      'Beer',
    ]) {
      expect(isDrink(name), isTrue, reason: name);
    }
  });

  test('a food a drink names is not the drink', () {
    for (final name in [
      'tea cake',
      'Coffee cake',
      'ground coffee',
      'Tea bags',
      'Instant coffee',
      'Rice, cooked in water',
      'Chicken with beer sauce',
      'jam',
      null,
    ]) {
      expect(isDrink(name), isFalse, reason: name);
    }
  });
}
