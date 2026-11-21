// Nutrition out's disclosure uses the app's nutrient names and calls a diary
// row a food (the 2026-11-21 round 2 G6 critique, hc-disc-nutrition.png).
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/fork/health/weight_import_ui.dart';

void main() {
  test('Nutrition out names fibre and sugars, and each food', () {
    final text = nutritionOutDisclosure();
    expect(text, contains('fibre, sugars, saturated fat and sodium'));
    expect(text, contains('each food in your diary'));
    expect(text, isNot(contains('fiber')));
    expect(text, isNot(contains('entry')));
    expect(text, contains('Untick Nutrition out to stop.'));
  });
}
