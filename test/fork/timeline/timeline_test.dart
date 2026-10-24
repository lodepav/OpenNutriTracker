import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/app_theme_entity.dart';
import 'package:opennutritracker/core/domain/entity/config_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/utils/calc/day_boundary_calc.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/fork/copy/copy_entries.dart';
import 'package:opennutritracker/fork/timeline/timeline.dart';

final _day = DateTime(2026, 10, 23);

IntakeEntity _eat(String food, DateTime at, {double grams = 100}) =>
    IntakeEntity(
      id: food,
      unit: 'g',
      amount: grams,
      type: IntakeTypeEntity.breakfast,
      meal: MealEntity(
        code: food,
        name: food,
        url: null,
        mealQuantity: null,
        mealUnit: 'g',
        servingQuantity: null,
        servingUnit: 'g',
        servingSize: null,
        nutriments: const MealNutrimentsEntity(
          energyKcal100: 100,
          carbohydrates100: null,
          fat100: null,
          proteins100: null,
          sugars100: null,
          saturatedFat100: null,
          fiber100: null,
        ),
        source: MealSourceEntity.custom,
      ),
      dateTime: at,
    );

void main() {
  test('by the hour, earliest first, the untimed first', () {
    final groups = timelineHours([
      _eat('Coffee', DateTime(2026, 10, 23, 7, 50)),
      _eat('Soup', DateTime(2026, 10, 23, 12, 5)),
      _eat('Toast', DateTime(2026, 10, 23, 7, 10)),
      _eat('Apple', _day),
    ]);
    expect(
      [
        for (final (hour, intakes) in groups)
          '${hour?.hour}: ${[for (final i in intakes) i.id].join(', ')}',
      ],
      ['null: Apple', '7: Toast, Coffee', '12: Soup'],
    );
  });

  test('a time before the day starts is on the next calendar date', () {
    expect(
      momentOn(_day, const TimeOfDay(hour: 2, minute: 30), 4 * 60),
      DateTime(2026, 10, 24, 2, 30),
    );
    expect(
      momentOn(_day, const TimeOfDay(hour: 9, minute: 0), 4 * 60),
      DateTime(2026, 10, 23, 9),
    );
    // 00:00 is the night of the 23rd, not a date-only entry of the 24th.
    final midnight = momentOn(_day, const TimeOfDay(hour: 0, minute: 0), 240);
    expect(DayBoundaryCalc.dayLabelOf(midnight, 240), DateTime(2026, 10, 23));
  });

  testWidgets('a running total; an entry moved; a food added at a time', (
    tester,
  ) async {
    var stored = [
      _eat('Toast', DateTime(2026, 10, 23, 7, 10), grams: 150),
      _eat('Apple', _day),
      _eat('Soup', DateTime(2026, 10, 23, 12, 5), grams: 300),
    ];
    final added = <(IntakeTypeEntity, DateTime)>[];
    var picked = const TimeOfDay(hour: 15, minute: 45);
    await tester.pumpWidget(
      MaterialApp(
        home: TimelineScreen(
          day: _day,
          entries: TimelineEntries(
            of: (_) async => stored,
            replace: (moved) async =>
                stored = [for (final i in stored) i.id == moved.id ? moved : i],
            config: () async =>
                const ConfigEntity(false, false, false, AppThemeEntity.system),
          ),
          pickTime: (_, _) async => picked,
          addAt: (_, meal, at) async => added.add((meal, at)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No time'), findsOneWidget);
    expect(find.text('07:00'), findsOneWidget);
    // Apple 100, then Toast 150, then Soup 300.
    expect(find.text('250 kcal'), findsOneWidget);
    expect(find.text('550 kcal'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('timeline-Apple')));
    await tester.pumpAndSettle();
    expect(stored[1].dateTime, DateTime(2026, 10, 23, 15, 45));
    expect(find.text('No time'), findsNothing);
    expect(find.text('15:00'), findsOneWidget);

    picked = const TimeOfDay(hour: 19, minute: 30);
    await tester.tap(find.byKey(const ValueKey('timeline-add')));
    await tester.pumpAndSettle();
    expect(added, [(IntakeTypeEntity.dinner, DateTime(2026, 10, 23, 19, 30))]);
  });
}
