import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:opennutritracker/core/data/repository/recipe_repository.dart';
import 'package:opennutritracker/core/domain/entity/app_theme_entity.dart';
import 'package:opennutritracker/core/domain/entity/config_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/domain/usecase/compute_recipe_nutrition_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_intake_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/save_recipe_usecase.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/usecase/search_products_usecase.dart';
import 'package:opennutritracker/features/add_meal/presentation/bloc/food_bloc.dart';
import 'package:opennutritracker/features/add_meal/presentation/bloc/products_bloc.dart';
import 'package:opennutritracker/features/add_meal/presentation/bloc/recent_meal_bloc.dart';
import 'package:opennutritracker/features/recipes/presentation/bloc/recipe_builder_bloc.dart';
import 'package:opennutritracker/features/recipes/presentation/screens/recipe_builder_screen.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:provider/provider.dart';

// The empty-save error goes away once the user moves on to the ingredient
// picker, and the picker's rows say each food's energy per 100 g / 100 ml.

class _Unused
    implements RecipeRepository, SearchProductsUseCase, GetIntakeUsecase {
  final List<IntakeEntity> recent;

  _Unused([this.recent = const []]);

  @override
  Future<List<IntakeEntity>> getRecentIntake() async => recent;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Unexpected call: ${invocation.memberName}');
}

class _Config implements GetConfigUsecase {
  @override
  Future<ConfigEntity> getConfig() async =>
      const ConfigEntity(true, true, false, AppThemeEntity.system);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Unexpected call: ${invocation.memberName}');
}

IntakeEntity _recent(String name, double kcal100, String unit) => IntakeEntity(
  id: name,
  unit: unit,
  amount: 100,
  type: IntakeTypeEntity.lunch,
  meal: MealEntity(
    code: name,
    name: name,
    url: null,
    mealQuantity: null,
    mealUnit: unit,
    servingQuantity: null,
    servingUnit: unit,
    servingSize: null,
    nutriments: MealNutrimentsEntity(
      energyKcal100: kcal100,
      carbohydrates100: null,
      fat100: null,
      proteins100: null,
      sugars100: null,
      saturatedFat100: null,
      fiber100: null,
    ),
    source: MealSourceEntity.custom,
  ),
  dateTime: DateTime(2026, 11, 20),
);

void main() {
  final getIt = GetIt.instance;

  setUp(() async {
    await getIt.reset();
    final compute = ComputeRecipeNutritionUseCase();
    final unused = _Unused([
      _recent('Apple', 52, 'g'),
      _recent('Milk', 64, 'ml'),
    ]);
    final config = _Config();
    getIt
      ..registerFactory<RecipeBuilderBloc>(
        () => RecipeBuilderBloc(compute, SaveRecipeUseCase(unused, compute)),
      )
      ..registerFactory<ProductsBloc>(() => ProductsBloc(unused, config))
      ..registerFactory<FoodBloc>(() => FoodBloc(unused, config))
      ..registerFactory<RecentMealBloc>(() => RecentMealBloc(unused, config));
  });

  tearDown(() => getIt.reset());

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider<EnergyUnitProvider>(
        create: (_) => EnergyUnitProvider(),
        child: MaterialApp(
          localizationsDelegates: const [S.delegate],
          supportedLocales: S.supportedLocales,
          onGenerateRoute: (_) => MaterialPageRoute(
            settings: const RouteSettings(arguments: RecipeBuilderArguments()),
            builder: (_) => const RecipeBuilderScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openPicker(WidgetTester tester) async {
    await tester.tap(find.text('Add Ingredient').first);
    await tester.pumpAndSettle();
  }

  testWidgets('the empty-save error goes once the picker opens', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.textContaining('Save Recipe'));
    await tester.pump();
    expect(find.text('Recipe needs a name'), findsOneWidget);

    await openPicker(tester);
    expect(find.text('Recipe needs a name'), findsNothing);
  });

  testWidgets('the Recently rows say the energy per 100 g or 100 ml', (
    tester,
  ) async {
    await pump(tester);
    await openPicker(tester);
    await tester.tap(find.text('Recently'));
    await tester.pumpAndSettle();

    expect(find.text('52 kcal per 100 g'), findsOneWidget);
    expect(find.text('64 kcal per 100 ml'), findsOneWidget);
  });
}
