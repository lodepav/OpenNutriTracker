import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/data/repository/config_repository.dart';
import 'package:opennutritracker/core/domain/entity/app_theme_entity.dart';
import 'package:opennutritracker/core/domain/entity/config_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/fork/basket/basket.dart';
import 'package:opennutritracker/fork/basket/basket_ui.dart';
import 'package:opennutritracker/fork/plan/plan_store.dart';
import 'package:opennutritracker/generated/l10n.dart';

import '../../fixture/meal_entity_fixtures.dart';

// Empty and removing a food can be undone; "Plan, don't log" says the day.

final _day = DateTime(2026, 11, 24, 13);

BasketItem _item(MealEntity meal, double kcal) =>
    BasketItem(meal: meal, unit: 'g', amountText: '100', kcal: kcal);

class _Config extends Fake implements ConfigRepository {
  @override
  Future<ConfigEntity> getConfig() async =>
      const ConfigEntity(false, false, false, AppThemeEntity.system);
}

class _Plans extends Fake implements PlanStore {
  @override
  Future<void> add(
    Iterable<({MealEntity meal, String unit, String amountText, double kcal})>
    foods,
    IntakeTypeEntity type,
    DateTime day, {
    Set<int> weekdays = const {},
  }) async {}
}

void main() {
  setUp(
    () => locator.registerSingleton<GetConfigUsecase>(
      GetConfigUsecase(_Config()),
    ),
  );
  tearDown(() => locator.unregister<GetConfigUsecase>());

  final apple = MealEntityFixtures.mealOne;
  final toast = MealEntityFixtures.mealTwo;

  Future<FoodBasket> open(WidgetTester tester, List<BasketItem> items) async {
    final basket = FoodBasket();
    for (final i in items) {
      basket.add(i, IntakeTypeEntity.lunch, _day);
    }
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [S.delegate],
        home: Scaffold(
          body: const Text('search'),
          bottomNavigationBar: BasketBar(
            type: IntakeTypeEntity.lunch,
            day: _day,
            basket: basket,
            plans: _Plans(),
            log: (_, _, _, _) async => null,
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('basket-bar')));
    await tester.pumpAndSettle();
    return basket;
  }

  testWidgets('Empty the basket can be undone', (tester) async {
    final basket = await open(tester, [_item(apple, 100), _item(toast, 200)]);
    await tester.tap(find.text('Empty the basket'));
    await tester.pumpAndSettle();
    expect(basket.items, isEmpty);

    await tester.tap(find.text('Undo').hitTestable());
    await tester.pumpAndSettle();
    expect(basket.itemsFor(IntakeTypeEntity.lunch, _day).map((i) => i.kcal), [
      100,
      200,
    ]);
  });

  testWidgets('removing a food with others left is undone in the sheet', (
    tester,
  ) async {
    final basket = await open(tester, [_item(apple, 100), _item(toast, 200)]);
    await tester.tap(find.byKey(const ValueKey('basket-remove-0')));
    await tester.pumpAndSettle();
    expect(basket.items.map((i) => i.kcal), [200]);

    await tester.tap(find.text('Undo').hitTestable());
    await tester.pumpAndSettle();
    expect(basket.items.map((i) => i.kcal), [100, 200]);
    expect(find.text('Undo'), findsNothing);
  });

  testWidgets('removing the last food closes the sheet with an Undo', (
    tester,
  ) async {
    final basket = await open(tester, [_item(apple, 100)]);
    await tester.tap(find.byKey(const ValueKey('basket-remove-0')));
    await tester.pumpAndSettle();
    expect(basket.items, isEmpty);

    await tester.tap(find.text('Undo').hitTestable());
    await tester.pumpAndSettle();
    expect(basket.items.map((i) => i.kcal), [100]);
    expect(find.textContaining('1 in the basket'), findsOneWidget);
  });

  testWidgets('"Plan, don\'t log" names the day it plans for', (tester) async {
    await open(tester, [_item(apple, 100)]);
    await tester.tap(find.byKey(const ValueKey('basket-plan')));
    await tester.pumpAndSettle();
    expect(find.text('Planned 1 food for Tue, Nov 24.'), findsOneWidget);
  });
}
