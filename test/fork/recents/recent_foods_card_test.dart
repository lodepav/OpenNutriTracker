import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:opennutritracker/core/domain/entity/config_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/fork/recents/recent_foods_card.dart';
import 'package:opennutritracker/generated/l10n.dart';

import '../../fixture/meal_entity_fixtures.dart';

class _Config extends Fake implements GetConfigUsecase {
  @override
  Future<ConfigEntity> getConfig() async => _Units();
}

class _Units extends Fake implements ConfigEntity {
  @override
  bool get usesImperialFoodUnits => false;
}

final _food = IntakeEntity(
  id: 'a',
  unit: 'g',
  amount: 150,
  type: IntakeTypeEntity.breakfast,
  meal: MealEntityFixtures.mealOne,
  dateTime: DateTime(2026, 10, 25, 8),
);

void main() {
  setUp(() => GetIt.instance.registerSingleton<GetConfigUsecase>(_Config()));
  tearDown(GetIt.instance.reset);

  Future<List<(IntakeEntity, IntakeTypeEntity)>> pump(
    WidgetTester tester,
    List<IntakeEntity> foods, {
    void Function()? onLoad,
  }) async {
    final logged = <(IntakeEntity, IntakeTypeEntity)>[];
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [S.delegate],
        supportedLocales: S.supportedLocales,
        home: Scaffold(
          body: RecentFoodsCard(
            load: () async {
              onLoad?.call();
              return (
                meal: IntakeTypeEntity.lunch,
                foods: foods,
                imperial: false,
              );
            },
            log: (_, food, meal) async => logged.add((food, meal)),
          ),
        ),
      ),
    );
    return logged;
  }

  testWidgets('collapsed until opened, and reads nothing before', (
    tester,
  ) async {
    var loads = 0;
    await pump(tester, [_food], onLoad: () => loads++);
    await tester.pumpAndSettle();
    expect(find.text('Recent foods'), findsOneWidget);
    expect(find.textContaining('150 g'), findsNothing);
    expect(loads, 0);
  });

  testWidgets('a tap logs the food at its amount, to the meal it names', (
    tester,
  ) async {
    final logged = await pump(tester, [_food]);
    await tester.tap(find.text('Recent foods'));
    await tester.pumpAndSettle();
    expect(find.textContaining('log it to Lunch'), findsOneWidget);
    expect(find.textContaining('150 g'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('home-recent-0')));
    await tester.pumpAndSettle();
    expect(logged, [(_food, IntakeTypeEntity.lunch)]);
  });

  testWidgets('each opening reads the foods anew', (tester) async {
    var loads = 0;
    await pump(tester, [_food], onLoad: () => loads++);
    await tester.tap(find.text('Recent foods'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Recent foods'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Recent foods'));
    await tester.pumpAndSettle();
    expect(loads, 2);
  });

  testWidgets('stays open when Home reloads, as it does after a log', (
    tester,
  ) async {
    final loading = ValueNotifier(false);
    addTearDown(loading.dispose);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [S.delegate],
        supportedLocales: S.supportedLocales,
        home: Scaffold(
          body: ValueListenableBuilder(
            valueListenable: loading,
            builder: (_, isLoading, _) => isLoading
                ? const SizedBox.shrink()
                : RecentFoodsCard(
                    load: () async => (
                      meal: IntakeTypeEntity.lunch,
                      foods: [_food],
                      imperial: false,
                    ),
                    log: (_, _, _) async {},
                  ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Recent foods'));
    await tester.pumpAndSettle();
    loading.value = true;
    await tester.pumpAndSettle();
    loading.value = false;
    await tester.pumpAndSettle();
    expect(find.textContaining('150 g'), findsOneWidget);
  });

  testWidgets('a Quick add shows its energy, no made-up amount', (
    tester,
  ) async {
    final quickAdd = IntakeEntity(
      id: 'q',
      unit: 'g',
      amount: 100,
      type: IntakeTypeEntity.snack,
      meal: MealEntity(
        code: 'q',
        name: 'Biscuit',
        url: null,
        mealQuantity: '100',
        mealUnit: 'gml',
        servingQuantity: null,
        servingUnit: 'gml',
        servingSize: '',
        nutriments: const MealNutrimentsEntity(
          energyKcal100: 300,
          carbohydrates100: null,
          fat100: null,
          proteins100: null,
          sugars100: null,
          saturatedFat100: null,
          fiber100: null,
        ),
        source: MealSourceEntity.custom,
      ),
      dateTime: DateTime(2026, 10, 25, 8),
    );
    await pump(tester, [quickAdd]);
    await tester.tap(find.text('Recent foods'));
    await tester.pumpAndSettle();
    expect(find.textContaining('300 kcal'), findsOneWidget);
    expect(find.textContaining('100 g'), findsNothing);
  });

  testWidgets('an amount logged by the serving is in its base unit', (
    tester,
  ) async {
    final served = IntakeEntity(
      id: 's',
      unit: 'serving',
      amount: 150,
      type: IntakeTypeEntity.lunch,
      meal: MealEntityFixtures.mealOne,
      dateTime: DateTime(2026, 10, 25, 12),
    );
    await pump(tester, [served]);
    await tester.tap(find.text('Recent foods'));
    await tester.pumpAndSettle();
    expect(find.textContaining('150 g'), findsOneWidget);
    expect(find.textContaining('serving'), findsNothing);
  });

  testWidgets('says so when nothing has been logged', (tester) async {
    await pump(tester, []);
    await tester.tap(find.text('Recent foods'));
    await tester.pumpAndSettle();
    expect(find.text('Foods you log will show here.'), findsOneWidget);
  });
}
