import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/features/add_meal/presentation/add_meal_type.dart';
import 'package:opennutritracker/features/add_meal/presentation/bloc/favourite_toggle_bloc.dart';
import 'package:opennutritracker/fork/copy/copy_ui.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/fork/display/diary_timeline.dart';
import 'package:opennutritracker/fork/screens/add_meal/meal_item_card.dart';

import '../helpers/fake_favourites.dart';
import '../helpers/ux_checks.dart';

MealEntity _food() => MealEntity(
  code: 'oats',
  name: 'Rolled oats, whole grain, organic',
  brands: 'A brand with a long name',
  url: null,
  mealQuantity: null,
  mealUnit: 'g',
  servingQuantity: 40,
  servingUnit: 'g',
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
  group('the checks catch', () {
    testWidgets('a line past its limit', (tester) async {
      await pumpOnPhone(
        tester,
        Text('word ' * 200, maxLines: 1, overflow: TextOverflow.ellipsis),
      );
      expect(cutText(tester), hasLength(1));
    });

    testWidgets('a line too wide for its box', (tester) async {
      await pumpOnPhone(
        tester,
        const SizedBox(
          width: 20,
          child: Text('12:30 PM', softWrap: false, maxLines: 1),
        ),
      );
      expect(cutText(tester), hasLength(1));
    });

    testWidgets('and let text that wraps pass', (tester) async {
      await pumpOnPhone(tester, Text('word ' * 50));
      expect(cutText(tester), isEmpty);
    });
  });

  group('at 200% text', () {
    setUp(() async {
      await GetIt.instance.reset();
      final favourites = FakeFavourites();
      GetIt.instance.registerFactory<FavouriteToggleBloc>(
        () => FavouriteToggleBloc(favourites.get, favourites.toggle),
      );
    });

    tearDown(() => GetIt.instance.reset());

    testWidgets('a food row', (tester) async {
      await pumpOnPhone(
        tester,
        MealItemCard(
          day: DateTime(2026, 10, 30),
          mealEntity: _food(),
          addMealType: AddMealType.lunchType,
          usesImperialUnits: false,
        ),
      );
      expect(cutText(tester), isEmpty);
      await expectAccessible(tester);
    });

    testWidgets('a gap on the timeline', (tester) async {
      await pumpOnPhone(
        tester,
        TimelineGap(
          from: DateTime(2026, 10, 30, 9),
          to: DateTime(2026, 10, 30, 12),
        ),
      );
      expect(cutText(tester), isEmpty);
    });

    testWidgets('the copy sheet', (tester) async {
      await pumpOnPhone(
        tester,
        WhereToSheet(
          today: DateTime(2026, 10, 30),
          now: DateTime(2026, 10, 30, 12),
          from: DateTime(2026, 10, 30),
          meals: const {IntakeTypeEntity.lunch, IntakeTypeEntity.dinner},
          count: 2,
        ),
      );
      expect(cutText(tester), isEmpty);
      await expectAccessible(tester);
    });
  });
}
