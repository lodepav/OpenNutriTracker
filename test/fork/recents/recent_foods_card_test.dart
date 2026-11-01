import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:opennutritracker/core/domain/entity/config_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
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
              return (meal: IntakeTypeEntity.lunch, foods: foods);
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

  testWidgets('says so when nothing has been logged', (tester) async {
    await pump(tester, []);
    await tester.tap(find.text('Recent foods'));
    await tester.pumpAndSettle();
    expect(find.text('Foods you log will show here.'), findsOneWidget);
  });
}
