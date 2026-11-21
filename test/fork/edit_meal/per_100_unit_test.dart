import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:opennutritracker/core/data/data_source/custom_meal_data_source.dart';
import 'package:opennutritracker/core/data/dbo/meal_dbo.dart';
import 'package:opennutritracker/core/data/repository/config_repository.dart';
import 'package:opennutritracker/core/data/repository/favourite_meal_repository.dart';
import 'package:opennutritracker/core/data/repository/intake_repository.dart';
import 'package:opennutritracker/core/domain/entity/app_theme_entity.dart';
import 'package:opennutritracker/core/domain/entity/config_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/features/edit_meal/presentation/bloc/edit_meal_bloc.dart';
import 'package:opennutritracker/features/edit_meal/presentation/edit_meal_screen.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:provider/provider.dart';

import '../../helpers/test_l10n.dart';

// S407: an imperial user's Edit meal says the facts are per 100 g, as they
// are stored, and leaves an unset serving empty rather than "0.00".
void main() {
  final getIt = GetIt.instance;
  late _Library library;

  setUp(() {
    library = _Library();
    getIt.registerFactory<EditMealBloc>(
      () => EditMealBloc(
        _Config(),
        library,
        _ConfigRepository(),
        _Favourites(),
        _Intakes(),
      ),
    );
  });
  tearDown(() => getIt.reset());

  const nutriments = MealNutrimentsEntity(
    energyKcal100: 97,
    carbohydrates100: 20,
    fat100: 1,
    proteins100: 2,
    sugars100: null,
    saturatedFat100: null,
    fiber100: null,
  );
  final banana = MealEntity(
    code: 'uuid-banana',
    name: 'Banana',
    url: null,
    mealQuantity: null,
    mealUnit: 'g',
    servingQuantity: null,
    servingUnit: 'g',
    servingSize: '',
    nutriments: nutriments,
    source: MealSourceEntity.custom,
  );

  Future<void> pump(WidgetTester tester) async {
    library.meals.add(MealDBO.fromMealEntity(banana));
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider<EnergyUnitProvider>(
        create: (_) => EnergyUnitProvider(),
        child: MaterialApp(
          localizationsDelegates: const [S.delegate],
          supportedLocales: S.supportedLocales,
          onGenerateInitialRoutes: (_) => [
            MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Text('custom meals')),
            ),
            MaterialPageRoute<void>(
              settings: RouteSettings(
                arguments: EditMealScreenArguments(
                  DateTime(2026, 11, 21),
                  banana,
                  IntakeTypeEntity.lunch,
                  true, // imperial
                  editOnly: true,
                ),
              ),
              builder: (_) => const EditMealScreen(),
            ),
          ],
          onGenerateRoute: (_) => null,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the facts read per 100 g and the serving starts empty', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text('Per 100 g'), findsWidgets);
    expect(find.textContaining('100 oz'), findsNothing);
    expect(find.text('0.00'), findsNothing);
  });

  testWidgets('saving untouched keeps the nutrition and the unset serving', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.widgetWithText(FilledButton, l10nEn.buttonSaveLabel));
    await tester.pumpAndSettle();

    final saved = MealEntity.fromMealDBO(library.saves.single);
    expect(saved.nutriments.energyKcal100, 97);
    expect(saved.nutriments.carbohydrates100, 20);
    expect(saved.nutriments.fat100, 1);
    expect(saved.nutriments.proteins100, 2);
    expect(saved.servingQuantity, isNull);
    expect(saved.mealQuantity, isNull);
  });
}

class _Library implements CustomMealDataSource {
  final saves = <MealDBO>[];
  final meals = <MealDBO>[];

  @override
  List<MealDBO> getAllCustomMeals() => meals;

  @override
  Future<void> saveCustomMeal(MealDBO mealDBO, {MealDBO? previous}) async {
    saves.add(mealDBO);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Unexpected call: ${invocation.memberName}');
}

class _Intakes implements IntakeRepository {
  @override
  Future<int> moveCustomMealInEveryProfile({
    required String fromMealKey,
    required MealDBO toMeal,
  }) async => 0;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Unexpected call: ${invocation.memberName}');
}

class _Config implements GetConfigUsecase {
  @override
  Future<ConfigEntity> getConfig() async =>
      const ConfigEntity(
        true,
        true,
        true,
        AppThemeEntity.system,
        usesImperialUnits: true,
      );

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Unexpected call: ${invocation.memberName}');
}

class _ConfigRepository implements ConfigRepository {
  @override
  Future<String?> getCustomMealFormMode() async =>
      CustomMealFormMode.advanced.name;

  @override
  Future<void> setCustomMealFormMode(String mode) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Unexpected call: ${invocation.memberName}');
}

class _Favourites implements FavouriteMealRepository {
  @override
  Future<void> moveFavourite(MealEntity previous, MealEntity updated) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Unexpected call: ${invocation.memberName}');
}
