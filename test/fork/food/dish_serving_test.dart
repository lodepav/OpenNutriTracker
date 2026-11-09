// lib/fork/food/dish_serving.dart: which foods start at a plate.
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/fork/food/dish_serving.dart';

void main() {
  test('a cooked main dish is one, its sauce, spice or a sausage is not', () {
    for (final name in [
      'Pilaf (rice, with onions and butter)',
      'Spaghetti Bolognese',
      'Beef goulash',
      'Lamb ragout, with carrots',
      'Chickpea-tomato stew',
      'Lasagna, meatless, with vegetables',
      'Macaroni and cheese',
      'Chicken curry',
    ]) {
      expect(isMainDish(name), isTrue, reason: name);
    }
    for (final name in [
      'Bolognese sauce',
      'Curry powder',
      'Curry-Bratwurst, grilled',
      'Babyfood, macaroni and cheese, toddler',
      'Brown bread casserole, with chocolate',
      'Pilaf mix, dry',
      'Spaghetti, cooked',
      null,
    ]) {
      expect(isMainDish(name), isFalse, reason: name);
    }
  });
}
