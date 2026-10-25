import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
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
      find.textContaining('500 kcal left: 40 g protein, 50 g carbs, 5 g fat'),
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
