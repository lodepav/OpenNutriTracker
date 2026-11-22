import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:opennutritracker/core/data/repository/recipe_repository.dart';
import 'package:opennutritracker/core/domain/entity/app_theme_entity.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
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

  // G3-7: the missing name is said on the name field, not in a snackbar
  testWidgets('a save without a name marks the name field', (tester) async {
    await pump(tester);
    await tester.tap(find.textContaining('Save Recipe'));
    await tester.pumpAndSettle();
    final name = tester.widget<TextField>(
      find.widgetWithText(TextField, 'Recipe name'),
    );
    expect(name.decoration?.errorText, 'Recipe needs a name');
    // the theme's 3:1 field edge (S552), not the 1.1:1 hairline
    final edge =
        (name.decoration!.enabledBorder! as OutlineInputBorder).borderSide;
    expect(edge.color, AppPalette.light.textMuted);
    expect(find.byType(SnackBar), findsNothing);

    await tester.enterText(find.widgetWithText(TextField, 'Recipe name'), 'S');
    await tester.pumpAndSettle();
    expect(find.text('Recipe needs a name'), findsNothing);
  });

  // G3-12: a new recipe's total weight is empty, not 0
  testWidgets('a new recipe shows no total weight', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const ValueKey('recipe-builder-optional')));
    await tester.pumpAndSettle();
    final weight = find.widgetWithText(TextField, 'Total weight (g)');
    expect(weight, findsOneWidget);
    expect(tester.widget<TextField>(weight).controller!.text, isEmpty);
  });

  // G3-21: the picker opens on Recently, and Products waits for a search
  // rather than listing the same recents
  testWidgets('the picker opens on Recently with the food pictures', (
    tester,
  ) async {
    await pump(tester);
    await openPicker(tester);
    expect(find.text('52 kcal per 100 g'), findsOneWidget);
    expect(find.text('🍎'), findsOneWidget, reason: "the builder's picture");

    await tester.tap(find.text('Products'));
    await tester.pumpAndSettle();
    expect(find.text('Your recent foods'), findsNothing);
  });

  testWidgets('with nothing recent the picker opens on Products', (
    tester,
  ) async {
    getIt.unregister<RecentMealBloc>();
    final none = _Unused();
    getIt.registerFactory<RecentMealBloc>(
      () => RecentMealBloc(none, _Config()),
    );
    await pump(tester);
    await openPicker(tester);
    final tabs = tester.widget<TabBar>(find.byType(TabBar));
    expect(tabs.controller!.index, 0);
  });

  // the name field is at the top of the list: a save from further down
  // brings it back into view to show its error
  testWidgets('a save without a name scrolls back to the name', (
    tester,
  ) async {
    await pump(tester);
    tester.view.physicalSize = const Size(400, 700);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('recipe-builder-optional')));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).first, const Offset(0, -2000));
    await tester.pumpAndSettle();
    expect(find.text('Recipe name').hitTestable(), findsNothing);
    final list = tester.state<ScrollableState>(
      find
          .descendant(
            of: find.byType(ListView).first,
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(list.position.pixels, greaterThan(100));

    await tester.tap(find.textContaining('Save Recipe'));
    await tester.pumpAndSettle();
    expect(list.position.pixels, 0);
    expect(find.text('Recipe needs a name').hitTestable(), findsOneWidget);
  });
}
