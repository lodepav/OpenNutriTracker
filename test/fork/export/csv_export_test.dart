import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/domain/entity/tracked_day_entity.dart';
import 'package:opennutritracker/core/domain/entity/weight_log_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_service.dart';
import 'package:opennutritracker/fork/export/csv_export.dart';

IntakeEntity _intake(String name, DateTime at, {double amount = 150}) =>
    IntakeEntity(
      id: name,
      unit: 'g',
      amount: amount,
      type: IntakeTypeEntity.breakfast,
      meal: MealEntity(
        code: name,
        name: name,
        url: null,
        mealQuantity: null,
        mealUnit: 'g',
        servingQuantity: null,
        servingUnit: 'g',
        servingSize: null,
        nutriments: const MealNutrimentsEntity(
          energyKcal100: 380,
          carbohydrates100: 60,
          fat100: 7,
          proteins100: 13,
          sugars100: null,
          saturatedFat100: null,
          fiber100: 10,
          sodium100: 6,
        ),
        source: MealSourceEntity.custom,
      ),
      dateTime: at,
    );

void main() {
  test('a field with a comma, a quote or a line break is quoted', () {
    expect(csvField('Oats'), 'Oats');
    expect(csvField('Oats, rolled'), '"Oats, rolled"');
    expect(csvField('6" sub'), '"6"" sub"');
    expect(csvField(null), '');
    expect(csvField(570.0), '570');
    expect(csvField(19.54), '19.5');
  });

  test('foods: each entry on its logical day, oldest first', () {
    final csv = foodsCsv([
      _intake('Late snack', DateTime(2026, 10, 23, 1, 30)),
      _intake('Oats, rolled', DateTime(2026, 10, 22, 8, 5)),
      _intake('Soup', DateTime(2026, 10, 22)),
    ], 3 * 60);
    expect(csv.split('\r\n'), [
      'date,time,meal,food,amount,unit,kcal,protein_g,carbs_g,fat_g,'
          'fibre_g,sugar_g,saturated_fat_g,sodium_mg',
      // Midnight is before the 03:00 start, so the 21st; and no time.
      '2026-10-21,,breakfast,Soup,150,g,570,19.5,90,10.5,15,,,9',
      '2026-10-22,08:05,breakfast,"Oats, rolled",150,g,570,19.5,90,10.5,15,,,9',
      '2026-10-22,01:30,breakfast,Late snack,150,g,570,19.5,90,10.5,15,,,9',
      '',
    ]);
  });

  test('days: eaten against goals, weight and expenditure, by date', () {
    final csv = daysCsv(
      trackedDays: [
        TrackedDayEntity(
          day: DateTime(2026, 10, 22),
          calorieGoal: 2140,
          caloriesTracked: 2050.4,
          proteinGoal: 150,
          proteinTracked: 140,
        ),
      ],
      weights: [WeightLogEntity(date: DateTime(2026, 10, 23), weightKg: 80.2)],
      expenditure: [
        ExpenditureDay(
          date: DateTime(2026, 10, 22),
          expenditureKcal: 2640,
          settled: true,
        ),
      ],
    );
    expect(csv.split('\r\n').skip(1).toList(), [
      '2026-10-22,2050.4,2140,140,150,,,,,,2640',
      '2026-10-23,,,,,,,,,80.2,',
      '',
    ]);
  });

  testWidgets('a failed export says so', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CsvExportTile(share: () async => throw StateError('no')),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('fork-csv-export')));
    await tester.pump();
    expect(find.text('Could not export the diary'), findsOneWidget);
  });
}
