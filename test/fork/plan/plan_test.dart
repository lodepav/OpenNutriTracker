import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/fork/plan/plan_store.dart';
import 'package:opennutritracker/fork/plan/plan_ui.dart';

import '../../fixture/meal_entity_fixtures.dart';

final _sunday = DateTime(2026, 10, 25);

void main() {
  late Directory dir;
  late PlanStore store;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('plan');
    Hive.init(dir.path);
    store = PlanStore(() => Hive.openBox<dynamic>('plan'));
  });

  tearDown(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  Future<void> planTwo() => store.add(
    [
      (
        meal: MealEntityFixtures.mealOne,
        unit: 'g',
        amountText: '150.0',
        kcal: 300,
      ),
      (
        meal: MealEntityFixtures.mealTwo,
        unit: 'ml',
        amountText: '250.0',
        kcal: 120,
      ),
    ],
    IntakeTypeEntity.lunch,
    _sunday.add(const Duration(hours: 13)),
  );

  test('a plan is kept by day, food and amount', () async {
    await planTwo();

    final sunday = await store.forDay(_sunday);
    expect(sunday.map((f) => f.meal.name), [
      MealEntityFixtures.mealOne.name,
      MealEntityFixtures.mealTwo.name,
    ]);
    expect(sunday.first.day, _sunday);
    expect(
      sunday.first.meal.nutriments.energyKcal100,
      MealEntityFixtures.mealOne.nutriments.energyKcal100,
    );
    expect(await store.forDay(DateTime(2026, 10, 26)), isEmpty);

    await store.remove(sunday.first.id);
    await store.merge(sunday);
    expect(await store.forDay(_sunday), hasLength(2));
  });

  test('a plan reads back once the box is reopened', () async {
    // Hive hands nested maps back as Map<dynamic, dynamic> after a reopen;
    // before it, the very objects written.
    await planTwo();
    await Hive.close();

    final sunday = await store.forDay(_sunday);
    expect(sunday, hasLength(2));
    expect(
      sunday.first.meal.nutriments.energyKcal100,
      MealEntityFixtures.mealOne.nutriments.energyKcal100,
    );
  });

  test(
    'a repeating food shows on its weekdays until logged or dropped',
    () async {
      await planTwo();
      final oats = (await store.forDay(_sunday)).first;
      // Sundays and Tuesdays, from this Sunday on.
      await store.setRepeat(oats.id, {DateTime.sunday, DateTime.tuesday});

      List<String?> names(List<PlannedFood> l) => [
        for (final f in l) f.meal.name,
      ];
      final one = MealEntityFixtures.mealOne.name;
      expect(names(await store.forDay(_sunday)), [
        one,
        MealEntityFixtures.mealTwo.name,
      ]);
      expect(await store.forDay(DateTime(2026, 10, 18)), isEmpty);
      expect(await store.forDay(DateTime(2026, 10, 26)), isEmpty);
      final tuesday = await store.forDay(DateTime(2026, 10, 27));
      expect(names(tuesday), [one]);
      expect(tuesday.single.day, DateTime(2026, 10, 27));
      expect(tuesday.single.repeatOf, oats.id);
      expect(tuesday.single.weekdays, {DateTime.sunday, DateTime.tuesday});

      // Logging or dropping one day leaves the other days planned.
      await store.remove(tuesday.single.id);
      expect(await store.forDay(DateTime(2026, 10, 27)), isEmpty);
      expect(names(await store.forDay(DateTime(2026, 11, 1))), [one]);
      expect(names(await store.forDay(DateTime(2026, 11, 3))), [one]);

      // And it reads back so after a reopen, as a backup would.
      await Hive.close();
      expect(await store.forDay(DateTime(2026, 10, 27)), isEmpty);
      expect(names(await store.forDay(DateTime(2026, 11, 3))), [one]);
      final copy = PlannedFood.fromJson(
        jsonDecode(jsonEncode((await store.all()).first.toJson())) as Map,
      );
      expect(copy.weekdays, {DateTime.sunday, DateTime.tuesday});
      expect(copy.doneDays, {DateTime(2026, 10, 27)});

      // A backup from before that log keeps it logged.
      final json = copy.toJson()..['doneDays'] = <String>[];
      await store.merge([PlannedFood.fromJson(json)]);
      expect(await store.forDay(DateTime(2026, 10, 27)), isEmpty);

      // Stopping keeps it on the day it was stopped from, and only there.
      await store.setRepeat('${oats.id}@2026-11-03', {});
      expect(names(await store.forDay(DateTime(2026, 11, 3))), [one]);
      expect(await store.forDay(DateTime(2026, 11, 1)), isEmpty);
      expect(names(await store.forDay(_sunday)), [
        MealEntityFixtures.mealTwo.name,
      ]);
    },
  );

  test('a plan saved before repeats reads as one day', () {
    final json = _planned('a', MealEntityFixtures.mealOne, 300).toJson();
    expect(json.containsKey('weekdays'), isFalse);
    final food = PlannedFood.fromJson(jsonDecode(jsonEncode(json)) as Map);
    expect(food.repeats, isFalse);
    expect(food.doneDays, isEmpty);
  });

  test('the plan\'s macros, from each food\'s energy', () {
    MealEntity meal(double? energy) => MealEntity(
      code: 'oats',
      name: 'Oats',
      url: null,
      mealQuantity: null,
      mealUnit: 'g',
      servingQuantity: null,
      servingUnit: 'g',
      servingSize: null,
      nutriments: MealNutrimentsEntity(
        energyKcal100: energy,
        carbohydrates100: 60,
        fat100: 8,
        proteins100: 12,
        sugars100: null,
        saturatedFat100: null,
        fiber100: null,
      ),
      source: MealSourceEntity.custom,
    );
    final m = plannedMacros([
      _planned('a', meal(400), 600), // 150 g
      _planned('b', meal(null), 100), // no energy figure: none
    ]);
    expect(m.protein, closeTo(18, 1e-9));
    expect(m.carbs, closeTo(90, 1e-9));
    expect(m.fat, closeTo(12, 1e-9));
  });

  testWidgets('a tick logs one, a cross drops one, "Log all" the rest', (
    tester,
  ) async {
    final memory = _MemoryPlan([
      _planned('a', MealEntityFixtures.mealOne, 300),
      _planned('b', MealEntityFixtures.mealTwo, 120),
      _planned('c', MealEntityFixtures.mealThree, 80),
    ]);
    final logged = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlannedFoodsCard(
            day: _sunday,
            store: memory,
            log: (_, food) async {
              logged.add(food.id);
              return true;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Planned · 500 kcal'), findsOneWidget);
    expect(find.textContaining('Lunch · 150 g · 300 kcal'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('plan-drop-b')));
    await tester.pumpAndSettle();
    expect(logged, isEmpty);
    expect(find.text('Planned · 380 kcal'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('plan-log-c')));
    await tester.pumpAndSettle();
    expect(logged, ['c']);

    await tester.tap(find.byKey(const ValueKey('plan-log-all')));
    await tester.pumpAndSettle();
    expect(logged, ['c', 'a']);
    expect(memory.foods, isEmpty);
    expect(find.textContaining('Planned'), findsNothing);
  });

  testWidgets('"Repeat" picks the days; a repeating food says so', (
    tester,
  ) async {
    final memory = _MemoryPlan([
      _planned('a', MealEntityFixtures.mealOne, 300),
    ]);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlannedFoodsCard(
            day: _sunday,
            store: memory,
            log: (_, _) async => true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('plan-repeat-a')));
    await tester.pumpAndSettle();
    // Its own day comes chosen; no "Stop" for a food that doesn't repeat.
    expect(
      tester
          .widget<FilterChip>(find.byKey(const ValueKey('repeat-day-7')))
          .selected,
      isTrue,
    );
    expect(find.byKey(const ValueKey('repeat-stop')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('repeat-every-day')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('repeat-save')));
    await tester.pumpAndSettle();
    expect(memory.repeats['a'], {1, 2, 3, 4, 5, 6, 7});
    expect(find.textContaining('Repeats every day'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('plan-repeat-a')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('repeat-stop')));
    await tester.pumpAndSettle();
    expect(memory.repeats['a'], isEmpty);
    expect(find.textContaining('Repeats'), findsNothing);
    // Still planned today, as a one-day food.
    expect(find.byKey(const ValueKey('plan-log-a')), findsOneWidget);
  });

  test('repeat days read as words', () async {
    await initializeDateFormatting('en');
    expect(repeatTextFor('en', {1, 2, 3, 4, 5, 6, 7}), 'Repeats every day');
    expect(repeatTextFor('en', {1, 2, 3, 4, 5}), 'Repeats on weekdays');
    expect(repeatTextFor('en', {3, 1}), 'Repeats Mon, Wed');
  });

  testWidgets('a food a profile switch dropped stays planned', (tester) async {
    final memory = _MemoryPlan([
      _planned('a', MealEntityFixtures.mealOne, 300),
      _planned('b', MealEntityFixtures.mealTwo, 120),
    ]);
    final logged = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlannedFoodsCard(
            day: _sunday,
            store: memory,
            log: (_, food) async {
              logged.add(food.id);
              return false;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('plan-log-all')));
    await tester.pumpAndSettle();

    expect(logged, hasLength(1));
    expect(memory.foods.map((f) => f.id), ['a', 'b']);
  });
}

PlannedFood _planned(String id, MealEntity meal, double kcal) => PlannedFood(
  id: id,
  day: _sunday,
  type: IntakeTypeEntity.lunch,
  meal: meal,
  unit: 'g',
  amountText: '150.0',
  kcal: kcal,
);

class _MemoryPlan extends Fake implements PlanStore {
  final List<PlannedFood> foods;

  _MemoryPlan(this.foods);

  @override
  Future<List<PlannedFood>> forDay(DateTime day) async => [...foods];

  final repeats = <String, Set<int>>{};

  @override
  Future<void> remove(String id) async {
    foods.removeWhere((f) => f.id == id);
    PlanStore.changes.value++;
  }

  @override
  Future<void> setRepeat(String id, Set<int> weekdays) async {
    repeats[id] = weekdays;
    final at = foods.indexWhere((f) => f.id == id);
    final f = foods[at];
    foods[at] = PlannedFood(
      id: f.id,
      day: f.day,
      type: f.type,
      meal: f.meal,
      unit: f.unit,
      amountText: f.amountText,
      kcal: f.kcal,
      weekdays: weekdays,
    );
    PlanStore.changes.value++;
  }
}
