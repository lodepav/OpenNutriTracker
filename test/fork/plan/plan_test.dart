import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
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
            log: (_, food) async => logged.add(food.id),
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

  @override
  Future<void> remove(String id) async {
    foods.removeWhere((f) => f.id == id);
    PlanStore.changes.value++;
  }
}
