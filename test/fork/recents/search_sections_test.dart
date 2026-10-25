import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:opennutritracker/core/domain/entity/app_theme_entity.dart';
import 'package:opennutritracker/core/domain/entity/config_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/features/add_meal/presentation/add_meal_type.dart';
import 'package:opennutritracker/features/add_meal/presentation/bloc/favourite_meal_bloc.dart';
import 'package:opennutritracker/features/add_meal/presentation/bloc/favourite_toggle_bloc.dart';
import 'package:opennutritracker/fork/recents/search_sections.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:provider/provider.dart';

import '../../helpers/fake_favourites.dart';

class _Config implements GetConfigUsecase {
  @override
  Future<ConfigEntity> getConfig() async =>
      const ConfigEntity(true, true, false, AppThemeEntity.system);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Unexpected call: ${invocation.memberName}');
}

MealEntity _meal(String name, {double kcal = 123}) => MealEntity(
  code: name,
  name: name,
  url: null,
  mealQuantity: null,
  mealUnit: 'g',
  servingQuantity: null,
  servingUnit: null,
  servingSize: null,
  nutriments: MealNutrimentsEntity(
    energyKcal100: kcal,
    carbohydrates100: 26,
    fat100: 1,
    proteins100: 3,
    sugars100: null,
    saturatedFat100: null,
    fiber100: null,
  ),
  source: MealSourceEntity.custom,
);

IntakeEntity _entry(MealEntity meal, double grams) => IntakeEntity(
  id: meal.name!,
  unit: 'g',
  amount: grams,
  type: IntakeTypeEntity.dinner,
  meal: meal,
  dateTime: DateTime(2026, 10, 24, 19),
);

void main() {
  final getIt = GetIt.instance;
  late FakeFavourites favourites;
  FavouriteMealBloc? bloc;

  // Made in the test's zone, as its loads only run there.
  FavouriteMealBloc favouritesBloc() =>
      bloc ??= FavouriteMealBloc(favourites.get, _Config());

  setUp(() {
    favourites = FakeFavourites();
    getIt.registerFactory<FavouriteToggleBloc>(
      () => FavouriteToggleBloc(favourites.get, favourites.toggle),
    );
  });

  tearDown(() async {
    await getIt.reset();
    await bloc?.close();
    bloc = null;
    await favourites.dispose();
  });

  Widget app(List<MealEntity> history, {double scale = 1}) =>
      ChangeNotifierProvider<EnergyUnitProvider>(
        create: (_) => EnergyUnitProvider(usesKilojoules: false),
        child: MaterialApp(
          localizationsDelegates: const [
            S.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          supportedLocales: S.supportedLocales,
          home: Scaffold(
            body: MediaQuery(
              data: MediaQueryData(
                size: const Size(360, 720),
                textScaler: TextScaler.linear(scale),
              ),
              child: SearchSections(
                day: DateTime(2026, 10, 25),
                addMealType: AddMealType.dinnerType,
                usesImperialUnits: false,
                history: history,
                entries: [for (final m in history) _entry(m, 640)],
                favourites: favouritesBloc(),
              ),
            ),
          ),
        ),
      );

  testWidgets('a history row shows the amount last logged, its energy and '
      'its macros', (tester) async {
    await tester.pumpWidget(app([_meal('Brown rice')]));
    await tester.pumpAndSettle();

    expect(find.text('From your history'), findsOneWidget);
    expect(find.text('640 g'), findsOneWidget);
    expect(find.text('787 kcal'), findsOneWidget);
    expect(find.text('C 166 · F 6 · P 19', findRichText: true), findsOneWidget);
  });

  testWidgets('the favourites follow the history, which shows ten until '
      'asked for all', (tester) async {
    favourites.add(_meal('Oatmeal', kcal: 150));
    final history = [for (var i = 0; i < 12; i++) _meal('Food $i')];
    await tester.pumpWidget(app(history));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('Show all 12'), 200);
    await tester.scrollUntilVisible(find.text('Favourites'), 200);
    expect(find.textContaining('Food 10', findRichText: true), findsNothing);
    // A favourite shows per 100 g: there is no amount of it to go by.
    await tester.scrollUntilVisible(find.text('150 kcal'), 200);
    expect(find.text('per 100 g'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('search-history-all')),
      -200,
    );
    await tester.tap(find.byKey(const ValueKey('search-history-all')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.textContaining('Food 11', findRichText: true),
      200,
    );
    expect(find.text('Show all 12'), findsNothing);
  });

  testWidgets('a favourite filtered on the Favourites chip comes back whole', (
    tester,
  ) async {
    favourites
      ..add(_meal('Oatmeal'))
      ..add(_meal('Bread'));
    favouritesBloc().add(const LoadFavouriteMealEvent(searchString: 'oat'));
    await tester.pumpWidget(app([_meal('Brown rice')]));
    await tester.pumpAndSettle();

    expect(find.textContaining('Bread', findRichText: true), findsOneWidget);
  });

  testWidgets('fits at a large text size', (tester) async {
    favourites.add(_meal('A favourite with a long name to wrap'));
    await tester.pumpWidget(
      app([_meal('Wholegrain bread with seeds, sliced')], scale: 2),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
