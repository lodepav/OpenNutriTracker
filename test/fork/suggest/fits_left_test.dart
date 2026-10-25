import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:opennutritracker/core/domain/entity/app_theme_entity.dart';
import 'package:opennutritracker/core/domain/entity/config_entity.dart';
import 'package:opennutritracker/core/domain/entity/tracked_day_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_kcal_goal_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_macro_goal_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_tracked_day_usecase.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_store.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/features/add_meal/presentation/add_meal_type.dart';
import 'package:opennutritracker/features/add_meal/presentation/bloc/favourite_toggle_bloc.dart';
import 'package:opennutritracker/features/add_meal/presentation/widgets/meal_item_card.dart';
import 'package:opennutritracker/fork/suggest/fits_left.dart';
import 'package:opennutritracker/generated/l10n.dart';

import '../../helpers/fake_favourites.dart';

/// 100 g of a food with these totals.
IntakeEntity _food(String name, double kcal, double p, double c, double f) =>
    IntakeEntity(
      id: name,
      unit: 'g',
      amount: 100,
      type: IntakeTypeEntity.lunch,
      dateTime: DateTime(2026, 10, 24, 13),
      meal: MealEntity(
        code: name,
        name: name,
        url: null,
        mealQuantity: null,
        mealUnit: 'g',
        servingQuantity: null,
        servingUnit: 'g',
        servingSize: null,
        nutriments: MealNutrimentsEntity(
          energyKcal100: kcal,
          carbohydrates100: c,
          fat100: f,
          proteins100: p,
          sugars100: null,
          saturatedFat100: null,
          fiber100: null,
        ),
        source: MealSourceEntity.custom,
      ),
    );

final _chicken = _food('Chicken', 200, 40, 0, 3);
final _oil = _food('Oil', 400, 0, 0, 45);
final _cake = _food('Cake', 700, 8, 80, 35);
final _rice = _food('Rice', 300, 6, 65, 1);

const DayLeft _left = (kcal: 500, protein: 40, carbs: 50, fat: 5);

class _TrackedDay extends Fake implements GetTrackedDayUsecase {
  final TrackedDayEntity? day;

  _TrackedDay([this.day]);

  @override
  Future<TrackedDayEntity?> getTrackedDay(DateTime day) async => this.day;
}

class _KcalGoal extends Fake implements GetKcalGoalUsecase {
  @override
  Future<double> getKcalGoal({
    dynamic userEntity,
    double? totalKcalActivitiesParam,
    double? kcalUserAdjustment,
  }) async => 2000;
}

class _MacroGoal extends Fake implements GetMacroGoalUsecase {
  @override
  Future<double> getCarbsGoal(double totalCalorieGoal) async => 250;

  @override
  Future<double> getFatsGoal(double totalCalorieGoal) async => 70;

  @override
  Future<double> getProteinsGoal(double totalCalorieGoal) async =>
      totalCalorieGoal / 20;
}

class _Config extends Fake implements GetConfigUsecase {
  @override
  Future<ConfigEntity> getConfig() async =>
      const ConfigEntity(true, true, false, AppThemeEntity.system);
}

void main() {
  test('what fits, the best fit for the macros left first', () {
    final names = [
      for (final f in fitsLeft([_oil, _cake, _rice, _chicken], _left))
        f.meal.name,
    ];
    // Cake is over the energy left; oil fills fat already spent.
    expect(names, ['Chicken', 'Rice', 'Oil']);
  });

  test('a rounding over still fits; nothing once the energy is spent', () {
    expect(fitsLeft([_rice], (kcal: 280, protein: 0, carbs: 0, fat: 0)), [
      _rice,
    ]);
    expect(fitsLeft([_rice], (kcal: 270, protein: 0, carbs: 0, fat: 0)), []);
    expect(
      fitsLeft([_chicken], (kcal: -10, protein: 40, carbs: 0, fat: 0)),
      isEmpty,
    );
  });

  test('a day with logs: its own goals less what is logged', () async {
    final getIt = GetIt.instance;
    await getIt.reset();
    getIt.registerSingleton<GetTrackedDayUsecase>(
      _TrackedDay(
        TrackedDayEntity(
          day: DateTime(2026, 10, 25),
          calorieGoal: 2000,
          caloriesTracked: 1500,
          proteinGoal: 120,
          proteinTracked: 100,
          carbsGoal: 200,
          carbsTracked: 150,
          fatGoal: 60,
          fatTracked: 70,
        ),
      ),
    );
    // The profile's goals differ from the day's (protein 100 at 2000).
    getIt
      ..registerSingleton<GetKcalGoalUsecase>(_KcalGoal())
      ..registerSingleton<GetMacroGoalUsecase>(_MacroGoal());
    final left = await dayLeft(DateTime(2026, 10, 25));
    expect(left, (kcal: 500.0, protein: 20.0, carbs: 50.0, fat: -10.0));
  });

  test('a day with nothing logged: the goal at its weekday', () async {
    final getIt = GetIt.instance;
    await getIt.reset();
    getIt
      ..registerSingleton<GetTrackedDayUsecase>(_TrackedDay())
      ..registerSingleton<GetKcalGoalUsecase>(_KcalGoal())
      ..registerSingleton<GetMacroGoalUsecase>(_MacroGoal())
      ..registerSingleton<GetConfigUsecase>(_Config());
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    // +300 on tomorrow's weekday only, as a weekend's higher target.
    AdaptiveStore.settings.value = AdaptiveSettings(
      weekdayOffsets: [
        for (var d = 1; d <= 7; d++) d == tomorrow.weekday ? 300 : 0,
      ],
    );
    addTearDown(() => AdaptiveStore.settings.value = const AdaptiveSettings());

    final left = await dayLeft(tomorrow);
    expect(left.kcal, 2300);
    expect(left.protein, 115); // the macros from that day's energy
    expect(left.carbs, 250);
  });

  testWidgets('the chip swaps the recents for what fits', (tester) async {
    await GetIt.instance.reset();
    final favourites = FakeFavourites();
    GetIt.instance.registerFactory<FavouriteToggleBloc>(
      () => FavouriteToggleBloc(favourites.get, favourites.toggle),
    );
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [S.delegate],
        home: Scaffold(
          body: FitsLeftSwitch(
            day: DateTime(2026, 10, 25),
            addMealType: AddMealType.lunchType,
            recents: const Text('All recents'),
            load: (_) async =>
                (left: _left, recents: [_cake, _chicken], imperial: false),
          ),
        ),
      ),
    );
    expect(find.text('All recents'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('add-meal-fits-left')));
    await tester.pumpAndSettle();
    expect(find.text('All recents'), findsNothing);
    expect(
      find.textContaining('500 kcal left: 50 g carbs, 5 g fat, 40 g protein'),
      findsOneWidget,
    );
    expect(find.text('100 g: 200 kcal, 40 g protein'), findsOneWidget);
    // Cake is over the energy left.
    expect(find.byType(MealItemCard), findsOneWidget);
    expect(find.byKey(const ValueKey('fits-Cake')), findsNothing);

    // Off again for the next test: the choice outlives the widget.
    await tester.tap(find.byKey(const ValueKey('add-meal-fits-left')));
    await tester.pumpAndSettle();
    expect(find.text('All recents'), findsOneWidget);
  });
}
