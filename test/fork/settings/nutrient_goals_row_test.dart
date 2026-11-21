// The Nutrient goals row says what is set, as its neighbours do (round-3
// settings critique, 2026-11-21, G6). A goal left unset is the reference
// amount the overview and the editor show.
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/tracked_day_entity.dart';
import 'package:opennutritracker/fork/screens/settings/settings_screen.dart';

void main() {
  TrackedDayEntity day({double? fibre, double? sodium, double? b12}) =>
      TrackedDayEntity(
        day: DateTime(2026, 11, 21),
        calorieGoal: 2000,
        caloriesTracked: 0,
        fibreGoal: fibre,
        sodiumGoal: sodium,
        vitaminB12Goal: b12,
      );

  test('nothing set reads as the reference amounts', () {
    expect(nutrientGoalsText(null), 'Reference amounts');
    expect(nutrientGoalsText(day()), 'Reference amounts');
  });

  test('some set are counted out of the ten', () {
    expect(nutrientGoalsText(day(fibre: 30)), '1 of 10 set by you');
    expect(
      nutrientGoalsText(day(fibre: 30, sodium: 2300, b12: 2.4)),
      '3 of 10 set by you',
    );
  });

  test('all ten set', () {
    final all = TrackedDayEntity(
      day: DateTime(2026, 11, 21),
      calorieGoal: 2000,
      caloriesTracked: 0,
      fibreGoal: 30,
      satFatGoal: 20,
      sugarsGoal: 50,
      sodiumGoal: 2300,
      calciumGoal: 1000,
      ironGoal: 8,
      potassiumGoal: 3400,
      vitaminDGoal: 15,
      vitaminB12Goal: 2.4,
      magnesiumGoal: 400,
    );
    expect(nutrientGoalsText(all), 'All 10 set by you');
  });
}
