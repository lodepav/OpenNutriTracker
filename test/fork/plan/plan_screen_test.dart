import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/utils/navigation_options.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/fork/basket/basket.dart';
import 'package:opennutritracker/fork/copy/copy_entries.dart';
import 'package:opennutritracker/fork/plan/plan_screen.dart';
import 'package:opennutritracker/fork/plan/plan_store.dart';
import 'package:opennutritracker/fork/plan/plan_ui.dart';
import 'package:opennutritracker/generated/l10n.dart';

import '../../fixture/meal_entity_fixtures.dart';
import '../../helpers/ux_checks.dart';

final _today = DateTime(2026, 11, 2); // a Monday

PlannedFood _food(
  String id,
  DateTime day, {
  IntakeTypeEntity type = IntakeTypeEntity.lunch,
  Set<int> weekdays = const {},
  MealEntity? meal,
}) => PlannedFood(
  id: id,
  day: day,
  type: type,
  meal: meal ?? MealEntityFixtures.mealOne,
  unit: 'g',
  amountText: '150.0',
  kcal: 300,
  weekdays: weekdays,
);

class _Memory extends Fake implements PlanStore {
  List<PlannedFood> foods;

  _Memory(this.foods);

  @override
  Future<List<PlannedFood>> all() async => [...foods];

  @override
  Future<List<PlannedFood>> forDay(DateTime day) async => [
    for (final f in foods)
      if (f.repeats ? f.weekdays.contains(day.weekday) : f.day == day) f,
  ];

  @override
  Future<void> putBack(PlannedFood food) async {
    foods = [...foods, food];
    PlanStore.changes.value++;
  }

  @override
  Future<void> remove(String id) async {
    foods = [
      for (final f in foods)
        if (f.id != id) f,
    ];
    PlanStore.changes.value++;
  }

  @override
  Future<void> setRepeat(String id, Set<int> weekdays) async {
    foods = [
      for (final f in foods)
        f.id == id ? _food(f.id, f.day, type: f.type, weekdays: weekdays) : f,
    ];
    PlanStore.changes.value++;
  }
}

void main() {
  setUpAll(() => initializeDateFormatting());

  Future<List<(IntakeTypeEntity, DateTime, PlanMode)>> pump(
    WidgetTester tester,
    PlanStore store,
  ) async {
    final picks = <(IntakeTypeEntity, DateTime, PlanMode)>[];
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [S.delegate],
        supportedLocales: S.supportedLocales,
        home: MealPlanScreen(
          today: _today,
          store: store,
          pickFoods: (_, meal, day, mode) async => picks.add((meal, day, mode)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return picks;
  }

  testWidgets('the screen check', (tester) async {
    await checkScreen(
      tester,
      MealPlanScreen(
        today: _today,
        store: _Memory([
          _food('a', _today),
          _food('r', _today, weekdays: {DateTime.monday}),
        ]),
      ),
    );
  });

  testWidgets('says when a day is empty, and shows the day picked', (
    tester,
  ) async {
    await pump(tester, _Memory([_food('a', DateTime(2026, 11, 3))]));
    expect(find.text('Nothing planned for this day.'), findsOneWidget);
    expect(find.textContaining('Planned ·'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('plan-day-1')));
    await tester.pumpAndSettle();
    expect(find.text('Nothing planned for this day.'), findsNothing);
    expect(find.textContaining('Planned ·'), findsOneWidget);
  });

  testWidgets('Plan foods asks the meal and searches for the day picked', (
    tester,
  ) async {
    final picks = await pump(tester, _Memory([]));
    await tester.tap(find.byKey(const ValueKey('plan-day-2')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('plan-add-foods')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('plan-meal-dinner')));
    await tester.pumpAndSettle();
    expect(picks, [
      (IntakeTypeEntity.dinner, DateTime(2026, 11, 4), PlanMode.once),
    ]);
  });

  testWidgets('search from the plan is planning, until it closes', (
    tester,
  ) async {
    final basket = FoodBasket.instance;
    addTearDown(basket.clear);
    PlanMode? during;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [S.delegate],
        supportedLocales: S.supportedLocales,
        routes: {
          NavigationOptions.addMealRoute: (_) {
            during = basket.planning;
            basket.add(
              BasketItem(
                meal: MealEntityFixtures.mealOne,
                unit: 'g',
                amountText: '100',
                kcal: 100,
              ),
              IntakeTypeEntity.lunch,
              _today,
            );
            return const Scaffold(body: BackButton());
          },
        },
        home: MealPlanScreen(today: _today, store: _Memory([])),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('plan-add-recurring')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('plan-meal-lunch')));
    await tester.pumpAndSettle();
    expect(during, PlanMode.recurring);
    expect(basket.planning, PlanMode.recurring);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(basket.planning, isNull);
    expect(basket.items, isEmpty);
  });

  testWidgets('Add recurring meal searches to repeat', (tester) async {
    final picks = await pump(tester, _Memory([]));
    await tester.tap(find.byKey(const ValueKey('plan-add-recurring')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('plan-meal-breakfast')));
    await tester.pumpAndSettle();
    expect(picks, [(IntakeTypeEntity.breakfast, _today, PlanMode.recurring)]);
  });

  testWidgets('a recurring food can be changed and stopped for good', (
    tester,
  ) async {
    final store = _Memory([
      _food('r', _today, weekdays: {DateTime.monday}),
    ]);
    await pump(tester, store);
    final row = find.byKey(const ValueKey('plan-recurring-r'));
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();

    await tester.tap(row);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('repeat-day-3')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('repeat-save')));
    await tester.pumpAndSettle();
    expect(store.foods.single.weekdays, {1, 3});

    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(find.text('Remove'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('repeat-stop')));
    await tester.pumpAndSettle();
    expect(store.foods, isEmpty);
    expect(row, findsNothing);
    expect(find.textContaining('Removed'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(store.foods.single.weekdays, {1, 3});
    expect(row, findsOneWidget);
  });

  test('the next meal is the time\'s, the one after, else the first left', () {
    final foods = [
      _food('b', _today, type: IntakeTypeEntity.breakfast),
      _food('d', _today, type: IntakeTypeEntity.dinner),
      _food('e', _today, type: IntakeTypeEntity.dinner),
    ];
    DateTime at(int hour) => DateTime(2026, 11, 2, hour);
    expect(upNextFoods(foods, at(8)).single.id, 'b');
    // Lunch time, none planned: on to dinner.
    expect(upNextFoods(foods, at(12)).map((f) => f.id), ['d', 'e']);
    // The afternoon snack, none planned: dinner is still to come.
    expect(upNextFoods(foods, at(16)).map((f) => f.id), ['d', 'e']);
    // Snack time, nothing after: breakfast went past uneaten.
    expect(upNextFoods(foods, at(23)).single.id, 'b');
    expect(upNextFoods(foods, at(1)).single.id, 'b');
    expect(upNextFoods(const [], at(8)), isEmpty);
  });

  group('a log or a drop says so, with Undo', () {
    Future<(List<Placed>, List<PlannedFood>)> card(
      WidgetTester tester,
      _Memory store,
    ) async {
      final undone = <Placed>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: PlannedFoodsCard(
                day: _today,
                store: store,
                log: (_, food) async => IntakeEntity(
                  id: 'i-${food.id}',
                  unit: food.unit,
                  amount: 150,
                  type: food.type,
                  meal: food.meal,
                  dateTime: food.day,
                ),
                undoLog: (placed, _) async {
                  undone.add(placed);
                  return true;
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return (undone, store.foods);
    }

    testWidgets('Log all, and Undo takes it out and plans it again', (
      tester,
    ) async {
      final store = _Memory([_food('a', _today), _food('b', _today)]);
      final (undone, _) = await card(tester, store);
      await tester.tap(find.byKey(const ValueKey('plan-log-all')));
      await tester.pumpAndSettle();
      expect(store.foods, isEmpty);
      expect(find.textContaining('Logged 2 foods to Lunch'), findsOneWidget);

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(undone.single.written.map((i) => i.id), ['i-a', 'i-b']);
      expect(store.foods.map((f) => f.id), ['a', 'b']);
    });

    testWidgets('each button names its food', (tester) async {
      final oats = MealEntity(
        code: 'oats',
        name: 'Oats',
        url: null,
        mealQuantity: null,
        mealUnit: 'g',
        servingQuantity: null,
        servingUnit: 'g',
        servingSize: null,
        nutriments: MealNutrimentsEntity.empty(),
        source: MealSourceEntity.custom,
      );
      await card(
        tester,
        _Memory([
          _food('a', _today, meal: oats),
          _food('r', _today, weekdays: {_today.weekday}, meal: oats),
        ]),
      );
      for (final tip in [
        'Log Oats',
        'Drop Oats',
        'Repeat Oats',
        'Drop Oats on this day',
        'Change how Oats repeats',
      ]) {
        expect(find.byTooltip(tip), findsWidgets, reason: tip);
      }
    });

    testWidgets('a drop, and Undo plans it again', (tester) async {
      final store = _Memory([_food('a', _today)]);
      final (undone, _) = await card(tester, store);
      await tester.tap(find.byKey(const ValueKey('plan-drop-a')));
      await tester.pumpAndSettle();
      expect(store.foods, isEmpty);
      expect(find.textContaining('Dropped'), findsOneWidget);

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(store.foods.map((f) => f.id), ['a']);
      expect(undone, isEmpty);
    });
  });

  testWidgets('Up next logs that meal only, and only where asked for', (
    tester,
  ) async {
    final store = _Memory([
      for (final type in IntakeTypeEntity.values)
        _food(type.name, _today, type: type),
    ]);
    final logged = <String>[];
    Widget card(bool upNext) => MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: PlannedFoodsCard(
            day: _today,
            store: store,
            showUpNext: upNext,
            log: (_, food) async {
              logged.add(food.id);
              return IntakeEntity(
                id: food.id,
                unit: food.unit,
                amount: 150,
                type: food.type,
                meal: food.meal,
                dateTime: food.day,
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpWidget(card(false));
    await tester.pumpAndSettle();
    final log = find.byKey(const ValueKey('plan-up-next-log'));
    expect(log, findsNothing);

    await tester.pumpWidget(card(true));
    await tester.pumpAndSettle();
    expect(find.textContaining('Up next: '), findsOneWidget);
    await tester.tap(log);
    await tester.pumpAndSettle();
    expect(logged, hasLength(1));
    // It leaves the plan as a tick does.
    expect(store.foods, hasLength(3));
  });
}
