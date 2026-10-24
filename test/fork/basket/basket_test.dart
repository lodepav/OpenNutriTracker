import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/data/repository/config_repository.dart';
import 'package:opennutritracker/core/domain/entity/app_theme_entity.dart';
import 'package:opennutritracker/core/domain/entity/config_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/fork/basket/basket.dart';
import 'package:opennutritracker/fork/basket/basket_ui.dart';
import 'package:opennutritracker/fork/plan/plan_store.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';

import '../../fixture/meal_entity_fixtures.dart';

final _day = DateTime(2026, 10, 23);

BasketItem _item(double kcal) => BasketItem(
  meal: MealEntityFixtures.mealOne,
  unit: 'g',
  amountText: '150.0',
  kcal: kcal,
);

/// Days start at 04:00.
class _Config extends Fake implements ConfigRepository {
  @override
  Future<ConfigEntity> getConfig() async => const ConfigEntity(
    false,
    false,
    false,
    AppThemeEntity.system,
    dayStartOffsetHours: 4,
  );
}

class _Plans extends Fake implements PlanStore {
  final planned = <(String?, IntakeTypeEntity, DateTime)>[];

  @override
  Future<void> add(
    Iterable<({MealEntity meal, String unit, String amountText, double kcal})>
    foods,
    IntakeTypeEntity type,
    DateTime day,
  ) async {
    for (final f in foods) {
      planned.add((f.meal.name, type, day));
    }
  }
}

void main() {
  setUp(
    () => locator.registerSingleton<GetConfigUsecase>(
      GetConfigUsecase(_Config()),
    ),
  );
  tearDown(() => locator.unregister<GetConfigUsecase>());

  test('the basket holds one meal of one day', () {
    final basket = FoodBasket()
      ..add(_item(100), IntakeTypeEntity.lunch, _day)
      ..add(_item(250), IntakeTypeEntity.lunch, _day);

    expect(basket.totalKcal, 350);
    expect(basket.itemsFor(IntakeTypeEntity.lunch, _day), hasLength(2));
    expect(basket.itemsFor(IntakeTypeEntity.dinner, _day), isEmpty);

    basket.add(_item(80), IntakeTypeEntity.dinner, _day);
    expect(basket.items, hasLength(1));
    expect(basket.itemsFor(IntakeTypeEntity.lunch, _day), isEmpty);
  });

  testWidgets('the bar reviews the basket and logs it all in order', (
    tester,
  ) async {
    final basket = FoodBasket()
      ..add(_item(100), IntakeTypeEntity.lunch, _day)
      ..add(_item(250), IntakeTypeEntity.lunch, _day)
      ..add(_item(40), IntakeTypeEntity.lunch, _day);
    final logged = <double>[];
    await tester.pumpWidget(
      MaterialApp(
        initialRoute: 'main',
        routes: {'main': (_) => const Scaffold(body: Text('home'))},
        onGenerateRoute: (_) => null,
      ),
    );
    final nav = tester.state<NavigatorState>(find.byType(Navigator));
    nav.push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          body: const Text('search'),
          bottomNavigationBar: BasketBar(
            type: IntakeTypeEntity.lunch,
            day: _day,
            basket: basket,
            log: (_, item, type, day) async {
              logged.add(item.kcal);
              return true;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('3 in the basket · 390 kcal'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('basket-bar')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('basket-remove-2')));
    await tester.pumpAndSettle();
    expect(find.text('Total 350 kcal'), findsOneWidget);

    await tester.tap(find.text('Log all 2'));
    await tester.pumpAndSettle();

    expect(logged, [100, 250]);
    expect(basket.items, isEmpty);
    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('a write a profile switch dropped stops "Log all" and keeps '
      'the rest in the basket', (tester) async {
    final basket = FoodBasket()
      ..add(_item(100), IntakeTypeEntity.lunch, _day)
      ..add(_item(250), IntakeTypeEntity.lunch, _day)
      ..add(_item(40), IntakeTypeEntity.lunch, _day);
    final logged = <double>[];
    await tester.pumpWidget(
      MaterialApp(
        initialRoute: 'main',
        routes: {'main': (_) => const Scaffold(body: Text('home'))},
        onGenerateRoute: (_) => null,
      ),
    );
    final nav = tester.state<NavigatorState>(find.byType(Navigator));
    nav.push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          body: const Text('search'),
          bottomNavigationBar: BasketBar(
            type: IntakeTypeEntity.lunch,
            day: _day,
            basket: basket,
            log: (_, item, _, _) async {
              logged.add(item.kcal);
              return logged.length < 2;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('basket-bar')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Log all 3'));
    await tester.pumpAndSettle();

    expect(logged, [100, 250]);
    expect(basket.items.map((i) => i.kcal), [250, 40]);
    expect(find.text('Logged 1 foods.'), findsOneWidget);
  });

  testWidgets('a sheet closed partway through "Log all" leaves only what '
      'was not logged in the basket', (tester) async {
    final basket = FoodBasket()
      ..add(_item(100), IntakeTypeEntity.lunch, _day)
      ..add(_item(250), IntakeTypeEntity.lunch, _day)
      ..add(_item(40), IntakeTypeEntity.lunch, _day);
    final logged = <double>[];
    final firstWritten = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: BasketBar(
            type: IntakeTypeEntity.lunch,
            day: _day,
            basket: basket,
            log: (context, item, _, _) async {
              logged.add(item.kcal);
              if (logged.length > 1) return true;
              // The user swipes the sheet away while the first one logs.
              Navigator.of(context).pop();
              await firstWritten.future;
              return true;
            },
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('basket-bar')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Log all 3'));
    await tester.pumpAndSettle();
    firstWritten.complete();
    await tester.pumpAndSettle();

    expect(logged, [100]);
    expect(basket.items.map((i) => i.kcal), [250, 40]);
  });

  testWidgets('"Plan, don\'t log" puts the basket on the plan', (tester) async {
    final basket = FoodBasket()..add(_item(100), IntakeTypeEntity.dinner, _day);
    final plans = _Plans();
    var logged = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: BasketBar(
            type: IntakeTypeEntity.dinner,
            day: _day,
            basket: basket,
            plans: plans,
            log: (_, _, _, _) async {
              logged++;
              return true;
            },
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('basket-bar')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('basket-plan')));
    await tester.pumpAndSettle();

    expect(logged, 0);
    expect(plans.planned, [
      (MealEntityFixtures.mealOne.name, IntakeTypeEntity.dinner, _day),
    ]);
    expect(basket.items, isEmpty);
  });

  testWidgets('a plan made after midnight, before the day starts, is the '
      "previous day's", (tester) async {
    final moment = DateTime(2026, 10, 24, 1, 30);
    final basket = FoodBasket()
      ..add(_item(100), IntakeTypeEntity.snack, moment);
    final plans = _Plans();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: BasketBar(
            type: IntakeTypeEntity.snack,
            day: moment,
            basket: basket,
            plans: plans,
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('basket-bar')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('basket-plan')));
    await tester.pumpAndSettle();

    expect(plans.planned.single.$3, DateTime(2026, 10, 23));
  });

  testWidgets('"Add to basket" takes a valid amount and goes back', (
    tester,
  ) async {
    final basket = FoodBasket();
    BasketItem? current;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => Scaffold(
                  body: AddToBasketButton(
                    meal: MealEntityFixtures.mealOne,
                    type: IntakeTypeEntity.snack,
                    day: _day,
                    basket: basket,
                    current: () => current,
                  ),
                ),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('add-to-basket')));
    await tester.pumpAndSettle();
    expect(basket.items, isEmpty);

    current = _item(120);
    await tester.tap(find.byKey(const ValueKey('add-to-basket')));
    await tester.pumpAndSettle();
    expect(basket.itemsFor(IntakeTypeEntity.snack, _day), hasLength(1));
    expect(find.text('open'), findsOneWidget);
  });
}
