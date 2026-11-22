import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/fork/screens/add_meal/add_meal_screen.dart';

void main() {
  test('the planning search names the meal, and its day on a line of its own',
      () {
    final title = planningTitle('Lunch', DateTime(2026, 11, 24), 'en-US');
    expect(title.meal, 'Planning lunch');
    expect(title.day, 'Tue, Nov 24');
  });
}
