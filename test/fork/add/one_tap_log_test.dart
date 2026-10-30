import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/utils/navigation_options.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/features/add_meal/presentation/add_meal_type.dart';
import 'package:opennutritracker/features/add_meal/presentation/bloc/favourite_toggle_bloc.dart';
import 'package:opennutritracker/fork/add/one_tap_log.dart';
import 'package:opennutritracker/fork/screens/add_meal/meal_item_card.dart';
import 'package:opennutritracker/generated/l10n.dart';

import '../../fixture/intake_entity_fixtures.dart';
import '../../helpers/fake_favourites.dart';

MealEntity _food({double? serving, String unit = 'g'}) => MealEntity(
  code: 'oats',
  name: 'Oats',
  url: null,
  mealQuantity: null,
  mealUnit: unit,
  servingQuantity: serving,
  servingUnit: unit,
  servingSize: null,
  nutriments: MealNutrimentsEntity(
    energyKcal100: 380,
    carbohydrates100: 60,
    fat100: 7,
    proteins100: 13,
    sugars100: 1,
    saturatedFat100: 1,
    fiber100: 10,
  ),
  source: MealSourceEntity.custom,
);

void main() {
  group('the amount the plus logs', () {
    test('a recent at its latest entry, as logged', () {
      final last = intakeOf('oats', 45);
      expect(oneTapAmount(_food(serving: 40), last: last), (
        unit: 'g',
        amount: 45,
      ));
    });

    test('else the amount last logged of the food', () {
      expect(
        oneTapAmount(
          _food(serving: 40),
          remembered: (unit: 'serving', quantity: '1,5'),
        ),
        (unit: 'serving', amount: 60),
      );
    });

    test('a remembered serving the food cannot scale is passed over', () {
      expect(
        oneTapAmount(_food(), remembered: (unit: 'serving', quantity: '2')),
        (unit: 'g', amount: 100),
      );
    });

    test('else a serving, or 100 g when raw units are the default', () {
      expect(oneTapAmount(_food(serving: 40)), (unit: 'serving', amount: 40));
      expect(oneTapAmount(_food(serving: 40), rawUnits: true), (
        unit: 'g',
        amount: 100,
      ));
      expect(oneTapAmount(_food(unit: 'ml')), (unit: 'ml', amount: 100));
    });
  });

  group('the row', () {
    late List<String> calls;

    setUp(() async {
      calls = [];
      await GetIt.instance.reset();
      final favourites = FakeFavourites();
      GetIt.instance.registerFactory<FavouriteToggleBloc>(
        () => FavouriteToggleBloc(favourites.get, favourites.toggle),
      );
      logFromRow =
          (
            context, {
            required MealEntity meal,
            required IntakeTypeEntity type,
            required DateTime day,
            required bool imperial,
            IntakeEntity? last,
          }) async =>
              calls.add('log ${meal.name} ${type.name} ${last?.amount}');
    });

    tearDown(() async {
      logFromRow = defaultLogFromRow;
      await GetIt.instance.reset();
    });

    Future<void> pump(WidgetTester tester) => tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [S.delegate],
        onGenerateRoute: (settings) {
          calls.add('open ${settings.name}');
          return MaterialPageRoute(builder: (_) => const Scaffold());
        },
        home: Scaffold(
          body: MealItemCard(
            day: DateTime(2026, 10, 30),
            mealEntity: _food(),
            addMealType: AddMealType.lunchType,
            usesImperialUnits: false,
            forkLastLogged: intakeOf('oats', 45),
          ),
        ),
      ),
    );

    testWidgets('the plus logs at once and stays', (tester) async {
      await pump(tester);
      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pumpAndSettle();
      expect(calls, ['log Oats lunch 45.0']);
    });

    testWidgets('the row opens the food\'s page', (tester) async {
      await pump(tester);
      await tester.tap(find.textContaining('Oats', findRichText: true).first);
      await tester.pumpAndSettle();
      expect(calls, ['open ${NavigationOptions.mealDetailRoute}']);
    });
  });
}
