import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/domain/entity/tracked_day_entity.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/fork/report/nutrient_explorer.dart';
import 'package:opennutritracker/fork/report/weekly_report.dart';

IntakeEntity _eat(String food, int day, double grams, {double? fiber}) =>
    IntakeEntity(
      id: '$food-$day-$grams',
      unit: 'g',
      amount: grams,
      type: IntakeTypeEntity.lunch,
      meal: MealEntity(
        code: food,
        name: food,
        url: null,
        mealQuantity: null,
        mealUnit: 'g',
        servingQuantity: null,
        servingUnit: 'g',
        servingSize: null,
        nutriments: MealNutrimentsEntity(
          energyKcal100: 200,
          carbohydrates100: 30,
          fat100: 5,
          proteins100: 10,
          sugars100: null,
          saturatedFat100: null,
          fiber100: fiber,
        ),
        source: MealSourceEntity.custom,
      ),
      dateTime: DateTime(2026, 10, day, 12),
    );

TrackedDayEntity _day(int day, {double? fibreGoal}) => TrackedDayEntity(
  day: DateTime(2026, 10, day),
  calorieGoal: 2000,
  caloriesTracked: 1,
  proteinGoal: 100,
  fibreGoal: fibreGoal,
);

final _intakes = [
  _eat('Oats', 20, 100, fiber: 10),
  _eat('Oats', 21, 50, fiber: 10),
  _eat('Lentils', 21, 200, fiber: 8),
  _eat('Cola', 21, 300),
];

void main() {
  test('a mean over the logged days, and the foods it came from', () {
    final all = summarizeNutrients(_intakes, [
      _day(19),
      _day(20, fibreGoal: 40),
      _day(21),
    ], null);
    final energy = all.firstWhere((s) => s.nutrient.label == 'Energy');
    // 650 g at 200 kcal per 100 g over the two days logged.
    expect(energy.perDay, 650);
    expect(energy.goal, 2000);

    final fibre = all.firstWhere((s) => s.nutrient.label == 'Fibre');
    expect(fibre.perDay, (15 + 16) / 2);
    // The 20th's own goal and the panel's 30 g for the 21st, unset.
    expect(fibre.goal, 35);
    expect(
      [for (final f in fibre.foods) (f.name, f.amount)],
      [('Lentils', 16), ('Oats', 15)],
    );
    expect(fibre.foodsWithout, 1);

    final protein = all.firstWhere((s) => s.nutrient.label == 'Protein');
    expect(protein.goal, 100);
  });

  testWidgets('opened from the weekly report, a nutrient lists its foods', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: WeeklyReportCard(
              days: [
                TrackedDayEntity(
                  day: DateTime(2026, 10, 21),
                  calorieGoal: 2000,
                  caloriesTracked: 1300,
                ),
              ],
              rangeDays: 7,
              palette: AppPalette.light,
              clock: () => DateTime(2026, 10, 23, 9),
              load: (first, last) async {
                expect((first, last.day), (DateTime(2026, 10, 17), 23));
                return _intakes;
              },
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('nutrient-explorer')));
    await tester.pumpAndSettle();

    expect(find.text('650 kcal a day · goal 2000 kcal'), findsOneWidget);
    expect(find.text('33%'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('nutrient-Fibre')),
      200,
    );
    expect(find.text('1 food without a figure'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('nutrient-Fibre')));
    await tester.pumpAndSettle();

    expect(find.text('Fibre by food'), findsOneWidget);
    expect(find.text('Lentils'), findsOneWidget);
    expect(find.text('16 g in the range'), findsOneWidget);
    expect(find.text('52%'), findsOneWidget);
  });
}
