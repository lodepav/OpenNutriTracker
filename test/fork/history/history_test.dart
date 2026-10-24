import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/body_weight_unit_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/domain/entity/weight_log_entity.dart';
import 'package:opennutritracker/fork/body/measurement_store.dart';
import 'package:opennutritracker/fork/history/history_file.dart';
import 'package:opennutritracker/fork/history/history_import.dart';
import 'package:opennutritracker/fork/history/table_reader.dart';

Uint8List _bytes(String text) => Uint8List.fromList(utf8.encode(text));

Uint8List _zip(Map<String, Uint8List> files) {
  final archive = Archive();
  for (final MapEntry(:key, :value) in files.entries) {
    archive.add(ArchiveFile.bytes(key, value));
  }
  return Uint8List.fromList(ZipEncoder().encodeBytes(archive));
}

/// A one-sheet workbook: text in shared strings, numbers as numbers.
Uint8List _xlsx(String sheet, List<List<Object>> rows) {
  final strings = <String>[];
  String cell(Object v, String ref) {
    if (v is num) return '<c r="$ref"><v>$v</v></c>';
    strings.add('$v');
    return '<c r="$ref" t="s"><v>${strings.length - 1}</v></c>';
  }

  final body = [
    for (final (r, row) in rows.indexed)
      '<row r="${r + 1}">${[for (final (c, v) in row.indexed) cell(v, '${String.fromCharCode(65 + c)}${r + 1}')].join()}</row>',
  ].join();
  return _zip({
    'xl/workbook.xml': _bytes(
      '<workbook><sheets><sheet name="$sheet" sheetId="1"/></sheets></workbook>',
    ),
    'xl/sharedStrings.xml': _bytes(
      '<sst>${[for (final s in strings) '<si><t>${s.replaceAll('&', '&amp;')}</t></si>'].join()}</sst>',
    ),
    'xl/worksheets/sheet1.xml': _bytes(
      '<worksheet><sheetData>$body</sheetData></worksheet>',
    ),
  });
}

void main() {
  test('MyFitnessPal: meals summed by day and meal, US dates; weights in '
      'the unit given when the header has none', () {
    final file = readHistory([
      ...readTables(
        'Nutrition-Summary.csv',
        _bytes(
          'Date,Meal,Calories,Fat (g),Saturated Fat,Carbohydrates (g),'
          'Protein (g),Note\n'
          '01/05/2024,Breakfast,400,10,3,50,20,\n'
          '01/05/2024,Breakfast,"1,100",30,9,120,60,"big, late"\n'
          '01/05/2024,Snacks,150,5,1,20,4,\n'
          '01/13/2024,Dinner,800,30,10,60,50,\n',
        ),
      ),
      ...readTables(
        'Measurement-Summary.csv',
        _bytes('Date,Weight\n01/05/2024,180.5\n01/13/2024,179\n'),
      ),
    ], unit: BodyWeightUnit.lb);

    final jan5 = file.food[DateTime(2024, 1, 5)]!;
    expect(jan5[IntakeTypeEntity.breakfast]!.kcal, 1500);
    expect(jan5[IntakeTypeEntity.breakfast]!.fat, 40);
    expect(jan5[IntakeTypeEntity.snack]!.protein, 4);
    expect(file.food[DateTime(2024, 1, 13)]!.keys, [IntakeTypeEntity.dinner]);
    expect(file.weightsKg[DateTime(2024, 1, 5)], closeTo(81.87, 0.01));
    expect(file.weightUnitStated, isFalse);
    expect(file.foodTable, 'Nutrition-Summary.csv');
    expect(file.weightTable, 'Measurement-Summary.csv');
  });

  test('MacroFactor workbook: day numbers as dates; not the target, the '
      'expenditure or the trend', () {
    final tables = readTables(
      'MacroFactor.xlsx',
      _xlsx('Quick Export', [
        [
          'Date',
          'Expenditure',
          'Trend Weight (kg)',
          'Weight (kg)',
          'Target Calories (kcal)',
          'Calories (kcal)',
          'Protein (g)',
          'Fat (g)',
          'Carbs (g)',
        ],
        [45292, 2600, 80.4, 80.9, 2100, 2050, 160, 70, 200],
        [45293, 2610, 80.3, '', 2100, 0, '', '', ''],
      ]),
    );
    final file = readHistory(tables, unit: BodyWeightUnit.lb);

    final day = file.food[DateTime(2024, 1, 1)]![null]!;
    expect(day.kcal, 2050);
    expect(day.protein, 160);
    expect(day.carbs, 200);
    expect(file.food.keys, [DateTime(2024, 1, 1)]); // 0 kcal: not logged
    expect(file.weightsKg, {DateTime(2024, 1, 1): 80.9});
    expect(file.weightUnitStated, isTrue);
    expect(file.weightUnit, BodyWeightUnit.kg);
    expect(file.foodTable, 'Quick Export');
  });

  test('Cronometer zip: the daily summary, and weight among biometrics in '
      'the unit of each row', () {
    final tables = readTables(
      'cronometer.zip',
      _zip({
        'dailysummary.csv': _bytes(
          'Date,Energy (kcal),Protein (g),Carbs (g),Net Carbs (g),Fat (g)\n'
          '2024-03-02,1900.5,120,210,180,60\n',
        ),
        'biometrics.csv': _bytes(
          'Day,Group,Metric,Unit,Amount\n'
          '2024-03-02,Weight,Weight,lbs,176\n'
          '2024-03-02,Blood,Blood Pressure,mmHg,120\n'
          '2024-03-03,Weight,Weight,kg,79.5\n',
        ),
      }),
    );
    final file = readHistory(tables);

    final day = file.food[DateTime(2024, 3, 2)]![null]!;
    expect(day.kcal, 1900.5);
    expect(day.carbs, 210); // not net carbs
    expect(file.weightsKg[DateTime(2024, 3, 2)], closeTo(79.83, 0.01));
    expect(file.weightsKg[DateTime(2024, 3, 3)], 79.5);
  });

  test('a European sheet: semicolons, decimal commas, day-first dates, kJ', () {
    final file = readHistory(
      readTables(
        'export.csv',
        _bytes(
          '﻿Datum;x\nDate;Energy (kJ);Protein (g);Gewicht\n'
          '05.01.2024;8368;95,5;80,2\n'
          '06.01.2024;1.046,0;10;\n',
        ),
      ),
    );

    expect(file.food[DateTime(2024, 1, 5)]![null]!.kcal, closeTo(2000, 0.1));
    expect(file.food[DateTime(2024, 1, 5)]![null]!.protein, 95.5);
    expect(file.food[DateTime(2024, 1, 6)]![null]!.kcal, closeTo(250, 0.1));
    expect(file.weightsKg, isEmpty); // "Gewicht" is no weight header
  });

  test('a scale weight column is the weight', () {
    final file = readHistory(
      readTables(
        'scale.csv',
        _bytes('Date,Calories,Scale Weight (kg)\n2024-01-01,2000,80.4\n'),
      ),
    );
    expect(file.weightsKg, {DateTime(2024, 1, 1): 80.4});
  });

  test('nothing to read gives an empty history', () {
    expect(
      readHistory(readTables('x.csv', _bytes('Name,Value\nA,1\n'))).isEmpty,
      isTrue,
    );
  });

  group('plan', () {
    final file = readHistory(
      readTables(
        'MacroFactor.csv',
        _bytes(
          'Date,Calories (kcal),Protein (g),Weight (kg)\n'
          '2026-10-20,2000,150,80\n'
          '2026-10-21,2100,160,79.8\n'
          '2026-10-22,2200,170,79.6\n'
          '2026-10-24,2300,180,79.4\n',
        ),
      ),
    );

    test('the app\'s own days and weigh-ins kept, the future left out, '
        'ids from the day', () {
      final plan = planImport(
        file,
        existing: HistoryExisting(
          loggedDays: {DateTime(2026, 10, 21)},
          weighIns: [
            WeightLogEntity(date: DateTime(2026, 10, 22), weightKg: 79),
          ],
        ),
        today: DateTime(2026, 10, 23),
        source: 'MacroFactor',
      );

      expect(plan.intakes.keys, [
        DateTime(2026, 10, 20),
        DateTime(2026, 10, 22),
      ]);
      final entry = plan.intakes[DateTime(2026, 10, 20)]!.single;
      expect(entry.id, 'history-2026-10-20-day');
      expect(entry.totalKcal, 2000);
      expect(entry.totalProteinsGram, 150);
      expect(entry.dateTime, DateTime(2026, 10, 20));
      expect(entry.meal.name, 'Day logged in MacroFactor');
      expect(plan.weights.map((w) => w.date), [
        DateTime(2026, 10, 20),
        DateTime(2026, 10, 21),
      ]);
      expect(plan.keptDays, 1);
      expect(plan.keptWeighIns, 1);
    });

    testWidgets('the preview asks the unit a header does not state, and '
        'imports the plan', (tester) async {
      final tables = readTables(
        'weights.csv',
        _bytes('Date,Weight\n2026-10-20,176\n'),
      );
      HistoryPlan plan(HistoryFile f) => planImport(
        f,
        existing: const HistoryExisting(),
        today: DateTime(2026, 10, 23),
        source: 'weights',
      );
      HistoryPlan? imported;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async => imported = await showDialog(
                context: context,
                builder: (_) => HistoryImportDialog(
                  file: readHistory(tables),
                  reread: (unit) => readHistory(tables, unit: unit),
                  plan: plan,
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.textContaining('1 to add'), findsOneWidget);
      expect(find.byKey(const ValueKey('history-unit')), findsOneWidget);

      await tester.tap(find.text('lb'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('history-import')));
      await tester.pumpAndSettle();
      expect(imported!.weights.single.weightKg, closeTo(79.83, 0.01));
    });
  });

  group('MacroFactor food log', () {
    // The columns of MacroFactor's food export that matter here, in its
    // order, with its header spellings.
    const header =
        '"Date","Time","Food Name","Serving Size","Serving Qty",'
        '"Serving Weight (g)","Calories (kcal)","Fat (g)","Carbs (g)",'
        '"Protein (g)","B6, Pyridoxine (mg)","Isoleucine (g)",'
        '"Saturated Fat (g)","Sodium (mg)","Sugars (g)","Sugars Added (g)"\n';
    final file = readHistory(
      readTables(
        'MacroFactor-20261024101932.csv',
        _bytes(
          '\u{FEFF}$header'
          '"2025-05-16","08:00","Milk Lactose Free","serving","3.0","100.0",'
          '"135","5","14","10","0.3","0.5","3.0","117.0","14.1","2"\n'
          '"2025-05-16","19:30","Rice","cup","1.0","200.0","260","1","56",'
          '"5",,,,,,\n'
          '"2025-05-17","01:30","Toast","slice","2","30","160","2","30","6",'
          ',,,,,\n',
        ),
      ),
    );

    test('reads each food, its time, grams and nutrients; serving weights '
        'are not weigh-ins', () {
      expect(file.weightsKg, isEmpty);
      expect(file.foods.map((f) => f.name), [
        'Milk Lactose Free',
        'Rice',
        'Toast',
      ]);
      final milk = file.foods.first;
      expect(milk.minute, 8 * 60);
      expect(milk.grams, 300);
      expect(milk.nutrients, {
        'vitaminB6': 0.3,
        'saturatedFat': 3.0,
        'sodium': 117.0,
        'sugars': 14.1,
      });
      // What the reading before this fix took for the day's weigh-in.
      expect(file.misreadKg[DateTime(2025, 5, 16)], contains(200.0));
      expect(file.food[DateTime(2025, 5, 16)]![null]!.kcal, 395);
    });

    test('each food at its time in the meal its time suggests, before the '
        'day start on the day before', () {
      final plan = planImport(
        file,
        existing: const HistoryExisting(dayStartMinutes: 4 * 60),
        today: DateTime(2026, 10, 24),
        source: 'MacroFactor',
      );
      final may16 = plan.intakes[DateTime(2025, 5, 16)]!;
      expect(may16.map((i) => i.meal.name), [
        'Milk Lactose Free',
        'Rice',
        'Toast',
      ]);
      final milk = may16.first;
      expect(milk.dateTime, DateTime(2025, 5, 16, 8));
      expect(milk.type, IntakeTypeEntity.breakfast);
      expect(milk.amount, 300);
      expect(milk.totalKcal, closeTo(135, 1e-9));
      expect(milk.totalProteinsGram, closeTo(10, 1e-9));
      expect(milk.meal.nutriments.sodium100, closeTo(39, 1e-9));
      expect(milk.id, 'history-food-2025-05-16-1');
      expect(isImportedHistory(milk), isFalse);
      expect(wasImported(milk), isTrue);
      expect(may16[1].type, IntakeTypeEntity.dinner);
      expect(may16[2].dateTime, DateTime(2025, 5, 17, 1, 30));
      expect(plan.intakes.keys, [DateTime(2025, 5, 16)]);
    });

    test('replaces an earlier import\'s totals and removes the weigh-ins it '
        'misread; the same file again adds nothing', () {
      final earlier = planImport(
        readHistory(
          readTables('old.csv', _bytes('Date,Calories\n2025-05-16,395\n')),
        ),
        existing: const HistoryExisting(),
        today: DateTime(2026, 10, 24),
        source: 'MacroFactor',
      ).intakes;
      final misread = WeightLogEntity(
        date: DateTime(2025, 5, 16),
        weightKg: 200,
      );
      final real = WeightLogEntity(date: DateTime(2025, 5, 17), weightKg: 80);
      final plan = planImport(
        file,
        existing: HistoryExisting(
          importedDays: earlier,
          weighIns: [misread, real],
        ),
        today: DateTime(2026, 10, 24),
        source: 'MacroFactor',
      );
      expect(plan.replaced.keys, [DateTime(2025, 5, 16)]);
      expect(plan.intakes[DateTime(2025, 5, 16)], hasLength(2));
      expect(plan.misread, [misread]);

      final again = planImport(
        file,
        existing: HistoryExisting(importedDays: plan.intakes),
        today: DateTime(2026, 10, 24),
        source: 'MacroFactor',
      );
      expect(again.intakes, isEmpty);
      expect(again.keptDays, 2);
    });
  });

  test('MacroFactor workbook sheets: the day\'s micronutrients, body fat '
      'and measurements, custom foods; totals never replace foods', () {
    final file = readHistory(
      readTables(
        'MacroFactor.zip',
        _zip({
          'Calories & Macros.csv': _bytes(
            'Date,Calories (kcal),Fat (g),Carbs (g),Protein (g)\n'
            '2025-05-16,2709,100,282,168\n',
          ),
          'Micronutrients.csv': _bytes(
            'Date,Fiber (g),Sodium (mg),Sugars (g),Isoleucine (g)\n'
            '2025-05-16,11.4,2489.5,85,3\n',
          ),
          'Scale Weight.csv': _bytes(
            'Date,Weight (kg),Fat Percent\n2025-05-16,93.85,15.7\n',
          ),
          'Body Metrics.csv': _bytes(
            'Date,Left Bicep (cm),Right Bicep (cm),Visual Body Fat '
            'Assessment,Waist (cm)\n2025-05-16,31,32,14,93\n',
          ),
          'Custom Foods.csv': _bytes(
            'Food Name,Serving Size,Serving Qty,Serving Weight (g),'
            'Calories (kcal),Fat (g),Carbs (g),Protein (g)\n'
            'Pea Protein Isolate,,,,,,,\n'
            'Butter Chicken,serving,1.0,159.5,221,10,13,18\n',
          ),
        }),
      ),
    );
    expect(file.weightsKg, {DateTime(2025, 5, 16): 93.85});
    expect(file.measurements[DateTime(2025, 5, 16)], {
      BodyMetric.bodyFat: 15.7,
      BodyMetric.arm: 32,
      BodyMetric.waist: 93,
    });
    expect(file.customFoods.single.name, 'Butter Chicken');

    final plan = planImport(
      file,
      existing: const HistoryExisting(customFoodNames: {'pea protein'}),
      today: DateTime(2026, 10, 24),
      source: 'MacroFactor',
    );
    final day = plan.intakes[DateTime(2025, 5, 16)]!.single;
    expect(day.totalKcal, 2709);
    expect(day.meal.nutriments.sodium100, 2489.5);
    expect(day.meal.nutriments.fiber100, 11.4);
    final chicken = plan.customFoods.single;
    expect(chicken.nutriments.energyKcal100, closeTo(221 / 159.5 * 100, 1e-9));
    expect(plan.measurements.keys, [DateTime(2025, 5, 16)]);

    // Over a day an import wrote food by food, the totals are kept out.
    final food = planImport(
      readHistory(
        readTables(
          'foods.csv',
          _bytes(
            'Date,Time,Food Name,Calories (kcal)\n2025-05-16,08:00,Egg,80\n',
          ),
        ),
      ),
      existing: const HistoryExisting(),
      today: DateTime(2026, 10, 24),
      source: 'MacroFactor',
    ).intakes;
    final again = planImport(
      file,
      existing: HistoryExisting(
        importedDays: food,
        measurements: [
          Measurement(
            id: 'm',
            date: DateTime(2025, 5, 16),
            metric: BodyMetric.waist,
            value: 92,
          ),
        ],
        customFoodNames: {'butter chicken'},
      ),
      today: DateTime(2026, 10, 24),
      source: 'MacroFactor',
    );
    expect(again.intakes, isEmpty);
    expect(again.keptDays, 1);
    expect(again.measurements[DateTime(2025, 5, 16)]!.keys, {
      BodyMetric.bodyFat,
      BodyMetric.arm,
    });
    expect(again.customFoods, isEmpty);
  });

  test('two food logs: each adds the days the one before did not give, '
      'and both are named', () {
    const header = 'Date,Time,Food Name,Calories (kcal)\n';
    final file = readHistory([
      ...readTables(
        'a.csv',
        _bytes('${header}2025-05-16,08:00,Egg,80\n2025-05-16,12:00,Soup,200\n'),
      ),
      ...readTables(
        'b.csv',
        _bytes('${header}2025-05-16,09:00,Toast,160\n2025-05-17,08:00,Tea,5\n'),
      ),
      ...readTables('c.csv', _bytes('${header}2025-05-17,10:00,Jam,50\n')),
    ]);
    expect([for (final f in file.foods) f.name], ['Egg', 'Soup', 'Tea']);
    expect(file.foodTables, ['a.csv', 'b.csv']);
  });
}
