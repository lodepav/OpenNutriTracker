import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/fork/food/sauce_serving.dart';

void main() {
  test('a sauce starts at a ladle at most, not a can', () {
    expect(sauceDefault('Gravy, beef, canned, ready-to-serve', 233), 60);
    expect(sauceDefault('Roast pork gravy', 250), 60);
    expect(sauceDefault('Salad dressing, ranch', 30), 30);
    expect(sauceDefault('Mayonnaise, regular', 9), 9);
    expect(sauceDefault('Tomato products, canned, sauce', 245), 60);
  });

  test('a food served in a sauce is the food, at its serving', () {
    expect(isSauce('Ham or pork with gravy'), isFalse);
    expect(isSauce('Chicken, with sauce, skin eaten'), isFalse);
    expect(sauceDefault('Ham or pork with gravy', 183), 183);
    expect(isSauce('Potatoes, boiled'), isFalse);
    expect(isSauce(null), isFalse);
  });
}
