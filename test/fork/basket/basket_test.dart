import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:opennutritracker/core/data/repository/config_repository.dart';
import 'package:opennutritracker/core/domain/entity/app_theme_entity.dart';
import 'package:opennutritracker/core/domain/entity/config_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/fork/add/logged_bar.dart';
import 'package:opennutritracker/fork/basket/basket.dart';
import 'package:opennutritracker/fork/copy/copy_entries.dart' show Placed;
import 'package:opennutritracker/fork/basket/basket_ui.dart';
import 'package:opennutritracker/fork/plan/plan_store.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';

import '../../fixture/meal_entity_fixtures.dart';

final _day = DateTime(2026, 10, 23);
final _undoLogged = undoLogged;

BasketItem _item(double kcal) => BasketItem(
  meal: MealEntityFixtures.mealOne,
  unit: 'g',
  amountText: '150.0',
  kcal: kcal,
);

IntakeEntity _written(BasketItem item) => IntakeEntity(
  id: 'id-${item.kcal}',
  unit: item.unit,
  amount: 150,
  type: IntakeTypeEntity.lunch,
  meal: item.meal,
  dateTime: _day,
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
  Set<int>? repeatsOn;

  @override
  Future<void> add(
    Iterable<({MealEntity meal, String unit, String amountText, double kcal})>
    foods,
    IntakeTypeEntity type,
    DateTime day, {
    Set<int> weekdays = const {},
  }) async {
    repeatsOn = weekdays;
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

  test('an amount reads as it was picked', () {
    expect(pickedLabel('1', 'serving'), '1 serving');
    expect(pickedLabel('2.0', 'serving#1'), '2 servings');
    expect(pickedLabel('7.5', 'oz'), '7.5 oz');
  });

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
      ..add(
        BasketItem(
          meal: MealEntityFixtures.mealOne,
          unit: 'serving',
          amountText: '210.0',
          kcal: 100,
          picked: pickedLabel('1.5', 'serving'),
        ),
        IntakeTypeEntity.lunch,
        _day,
      )
      ..add(_item(250), IntakeTypeEntity.lunch, _day)
      ..add(_item(40), IntakeTypeEntity.lunch, _day);
    final logged = <double>[];
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [S.delegate],
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
              return _written(item);
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('3 in the basket · 390 kcal'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('basket-bar')));
    await tester.pumpAndSettle();
    // Servings as picked, not the 210 g they come to.
    expect(find.text('1.5 servings · 100 kcal'), findsOneWidget);
    expect(find.text('150 g · 250 kcal'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('basket-remove-2')));
    await tester.pumpAndSettle();
    expect(find.text('Total 350 kcal'), findsOneWidget);

    await tester.tap(find.text('Log all 2 to Lunch'));
    await tester.pumpAndSettle();

    expect(logged, [100, 250]);
    expect(basket.items, isEmpty);
    expect(find.text('home'), findsOneWidget);

    // Undo takes back every entry the log wrote, off the basket's day.
    Placed? undone;
    undoLogged = (placed, {required startedOn}) async {
      undone = placed;
      return true;
    };
    addTearDown(() => undoLogged = _undoLogged);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(undone!.day, _day);
    expect(undone!.written.map((i) => i.id), ['id-100.0', 'id-250.0']);
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
        localizationsDelegates: const [S.delegate],
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
              return logged.length < 2 ? _written(item) : null;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('basket-bar')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Log all 3 to Lunch'));
    await tester.pumpAndSettle();

    expect(logged, [100, 250]);
    expect(basket.items.map((i) => i.kcal), [250, 40]);
    expect(
      find.text('Logged 1 food to Lunch. Not all added: the profile changed.'),
      findsOneWidget,
    );
  });

  Future<void> logAllFailing(
    WidgetTester tester,
    FoodBasket basket,
    Future<IntakeEntity?> Function(BasketItem) log,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [S.delegate],
        initialRoute: 'main',
        routes: {'main': (_) => const Scaffold(body: Text('home'))},
        onGenerateRoute: (_) => null,
      ),
    );
    tester
        .state<NavigatorState>(find.byType(Navigator))
        .push(
          MaterialPageRoute<void>(
            builder: (_) => Scaffold(
              body: const Text('search'),
              bottomNavigationBar: BasketBar(
                type: IntakeTypeEntity.lunch,
                day: _day,
                basket: basket,
                log: (_, item, _, _) => log(item),
              ),
            ),
          ),
        );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('basket-bar')));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('to Lunch').last);
    await tester.pumpAndSettle();
  }

  testWidgets('a failed write partway offers Undo for what was written and '
      'keeps the rest', (tester) async {
    final basket = FoodBasket()
      ..add(_item(100), IntakeTypeEntity.lunch, _day)
      ..add(_item(250), IntakeTypeEntity.lunch, _day);
    await logAllFailing(tester, basket, (item) async {
      if (item.kcal == 250) throw StateError('disk full');
      return _written(item);
    });
    expect(basket.items.map((i) => i.kcal), [250]);
    expect(
      find.text(
        "Logged 1 food to Lunch. The rest couldn't be saved and stay in the "
        'basket.',
      ),
      findsOneWidget,
    );
    expect(find.text('Undo'), findsOneWidget);
  });

  testWidgets('a first write failing keeps the sheet open to try again', (
    tester,
  ) async {
    final basket = FoodBasket()..add(_item(100), IntakeTypeEntity.lunch, _day);
    await logAllFailing(
      tester,
      basket,
      (item) async => throw StateError('disk full'),
    );
    expect(basket.items, hasLength(1));
    expect(find.textContaining("couldn't be saved"), findsOneWidget);
    expect(find.text('Undo'), findsNothing);
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Log all 1 to Lunch'),
    );
    expect(button.onPressed, isNotNull);
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
        localizationsDelegates: const [S.delegate],
        home: Scaffold(
          bottomNavigationBar: BasketBar(
            type: IntakeTypeEntity.lunch,
            day: _day,
            basket: basket,
            log: (context, item, _, _) async {
              logged.add(item.kcal);
              if (logged.length > 1) return _written(item);
              // The user swipes the sheet away while the first one logs.
              Navigator.of(context).pop();
              await firstWritten.future;
              return _written(item);
            },
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('basket-bar')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Log all 3 to Lunch'));
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
        localizationsDelegates: const [S.delegate],
        home: Scaffold(
          bottomNavigationBar: BasketBar(
            type: IntakeTypeEntity.dinner,
            day: _day,
            basket: basket,
            plans: plans,
            log: (_, item, _, _) async {
              logged++;
              return _written(item);
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

  group('from the meal plan', () {
    Future<void> open(
      WidgetTester tester,
      FoodBasket basket,
      _Plans plans,
    ) async {
      // The plan screen, search over it, the sheet over that.
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [S.delegate],
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => Scaffold(
                    bottomNavigationBar: BasketBar(
                      type: IntakeTypeEntity.dinner,
                      day: _day,
                      basket: basket,
                      plans: plans,
                    ),
                  ),
                ),
              ),
              child: const Text('plan screen'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('plan screen'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('basket-bar')));
      await tester.pumpAndSettle();
    }

    FoodBasket filled(PlanMode mode) => FoodBasket()
      ..planning = mode
      ..add(_item(100), IntakeTypeEntity.dinner, _day);

    testWidgets('offers no logging, and plans back to the plan screen', (
      tester,
    ) async {
      final plans = _Plans();
      await open(tester, filled(PlanMode.once), plans);
      expect(find.textContaining('Log all'), findsNothing);
      expect(find.textContaining('1 to plan'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('basket-plan')));
      await tester.pumpAndSettle();
      expect(plans.planned, hasLength(1));
      expect(plans.repeatsOn, isEmpty);
      expect(find.text('plan screen'), findsOneWidget);
    });

    testWidgets('a recurring meal only asks which days', (tester) async {
      final plans = _Plans();
      await open(tester, filled(PlanMode.recurring), plans);
      expect(find.byKey(const ValueKey('basket-plan')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('basket-repeat')));
      await tester.pumpAndSettle();
      // The day picked starts ticked.
      await tester.tap(find.byKey(const ValueKey('repeat-every-day')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('repeat-save')));
      await tester.pumpAndSettle();
      expect(plans.repeatsOn, {1, 2, 3, 4, 5, 6, 7});
      expect(plans.planned, hasLength(1));
      expect(find.text('plan screen'), findsOneWidget);
    });

    testWidgets('Cancel on the days plans nothing', (tester) async {
      final plans = _Plans();
      await open(tester, filled(PlanMode.recurring), plans);
      await tester.tap(find.byKey(const ValueKey('basket-repeat')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(plans.planned, isEmpty);
    });
  });

  testWidgets('a plan made after midnight, before the day starts, is the '
      "previous day's", (tester) async {
    final moment = DateTime(2026, 10, 24, 1, 30);
    final basket = FoodBasket()
      ..add(_item(100), IntakeTypeEntity.snack, moment);
    final plans = _Plans();
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [S.delegate],
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
        localizationsDelegates: const [S.delegate],
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
