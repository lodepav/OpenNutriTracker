import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:opennutritracker/core/data/repository/config_repository.dart';
import 'package:opennutritracker/core/data/data_source/custom_meal_data_source.dart';
import 'package:opennutritracker/core/data/dbo/meal_dbo.dart';
import 'package:opennutritracker/core/data/repository/favourite_meal_repository.dart';
import 'package:opennutritracker/core/data/repository/intake_repository.dart';
import 'package:opennutritracker/core/data/repository/recipe_repository.dart';
import 'package:opennutritracker/core/domain/entity/app_theme_entity.dart';
import 'package:opennutritracker/core/domain/entity/config_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/domain/entity/recipe_entity.dart';
import 'package:opennutritracker/core/domain/entity/recipe_ingredient_entity.dart';
import 'package:opennutritracker/core/domain/usecase/compute_recipe_nutrition_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/save_recipe_usecase.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/features/edit_meal/presentation/bloc/edit_meal_bloc.dart';
import 'package:opennutritracker/features/edit_meal/presentation/edit_meal_screen.dart';
import 'package:opennutritracker/features/recipes/presentation/bloc/recipe_builder_bloc.dart';
import 'package:opennutritracker/features/recipes/presentation/screens/recipe_builder_screen.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:provider/provider.dart';

import '../helpers/photo_docs.dart';

// The recipe builder and the custom food editor keep a picked or removed
// photo until Save (G3 P1): Back leaves the stored photo as it was.

// Energy that matches the macros, or Save asks about it first
const _per100 = MealNutrimentsEntity(
  energyKcal100: 165,
  carbohydrates100: 20,
  fat100: 5,
  proteins100: 10,
  sugars100: null,
  saturatedFat100: null,
  fiber100: null,
);

const _recipePhoto = 'recipe_images/r.webp';
const _foodPhoto = 'meal_images/m1.webp';

final _food = MealEntity(
  code: 'm1',
  name: 'Cereal bar',
  url: null,
  mealQuantity: '40',
  mealUnit: 'g',
  servingQuantity: 40,
  servingUnit: 'g',
  servingSize: null,
  nutriments: _per100,
  source: MealSourceEntity.custom,
  localImagePath: _foodPhoto,
);

final _bowl = RecipeEntity(
  id: 'r',
  name: 'Oat Bowl',
  description: null,
  ingredients: [
    RecipeIngredientEntity(
      snapshotMeal: _food,
      amount: 400,
      unit: 'g',
      convertedAmountG: 400,
    ),
  ],
  totalWeightG: 400,
  aggregatedNutrimentsPer100: _per100,
  createdAt: DateTime(2026, 11, 1),
  updatedAt: DateTime(2026, 11, 2),
  servingsCount: 2,
  imagePath: _recipePhoto,
);

class _Recipes extends Fake implements RecipeRepository {
  final byId = <String, RecipeEntity>{};

  @override
  Future<void> saveRecipe(RecipeEntity recipe) async =>
      byId[recipe.id] = recipe;
}

class _Config extends Fake implements GetConfigUsecase {
  @override
  Future<ConfigEntity> getConfig() async =>
      const ConfigEntity(true, true, false, AppThemeEntity.system);
}

class _ConfigRepository extends Fake implements ConfigRepository {
  @override
  Future<String?> getCustomMealFormMode() async =>
      CustomMealFormMode.simple.name;
}

class _Library extends Fake implements CustomMealDataSource {
  final saved = <MealDBO>[];

  @override
  List<MealDBO> getAllCustomMeals() => [];

  @override
  Future<void> saveCustomMeal(MealDBO mealDBO, {MealDBO? previous}) async =>
      saved.add(mealDBO);
}

class _Favourites extends Fake implements FavouriteMealRepository {
  @override
  Future<void> moveFavourite(MealEntity previous, MealEntity updated) async {}
}

class _Intakes extends Fake implements IntakeRepository {}

void main() {
  final getIt = GetIt.instance;
  late _Recipes recipes;
  late _Library library;
  late PhotoDocs docs;

  setUp(() async {
    recipes = _Recipes();
    library = _Library();
    final compute = ComputeRecipeNutritionUseCase();
    getIt
      ..registerFactory<RecipeBuilderBloc>(
        () => RecipeBuilderBloc(compute, SaveRecipeUseCase(recipes, compute)),
      )
      ..registerFactory<EditMealBloc>(
        () => EditMealBloc(
          _Config(),
          library,
          _ConfigRepository(),
          _Favourites(),
          _Intakes(),
        ),
      );
    docs = await PhotoDocs.create();
  });
  tearDown(() async {
    await getIt.reset();
    await docs.dispose();
  });

  Future<void> open(
    WidgetTester tester,
    String stored,
    Route<void> Function() route,
  ) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    await tester.runAsync(() => docs.write(stored, storedBytes));
    fakePicker(tester, docs.picked);
    await tester.pumpWidget(
      ChangeNotifierProvider<EnergyUnitProvider>(
        create: (_) => EnergyUnitProvider(),
        child: MaterialApp(
          localizationsDelegates: const [S.delegate],
          supportedLocales: S.supportedLocales,
          home: const Scaffold(),
        ),
      ),
    );
    tester.state<NavigatorState>(find.byType(Navigator)).push(route());
    await settleWithIo(tester);
  }

  Route<void> builder() => MaterialPageRoute<void>(
    settings: RouteSettings(arguments: RecipeBuilderArguments(existing: _bowl)),
    builder: (_) => const RecipeBuilderScreen(),
  );

  Route<void> editor() => MaterialPageRoute<void>(
    settings: RouteSettings(
      arguments: EditMealScreenArguments(
        DateTime(2026, 11, 21),
        _food,
        IntakeTypeEntity.lunch,
        false,
        editOnly: true,
      ),
    ),
    builder: (_) => const EditMealScreen(),
  );

  Finder recipeTile() =>
      find.bySemanticsIdentifier('recipe-builder-image-picker');
  Finder foodTile() => find.bySemanticsIdentifier('edit-meal-image-picker');

  group('recipe builder', () {
    testWidgets('Back after a remove leaves the stored photo', (tester) async {
      await open(tester, _recipePhoto, builder);
      await choose(tester, recipeTile(), 'Remove photo');
      await backAndDiscard(tester);

      expect(find.byType(RecipeBuilderScreen), findsNothing);
      expect(await tester.runAsync(() => docs.read(_recipePhoto)), storedBytes);
    });

    testWidgets('Back after a pick asks, then leaves the stored photo', (
      tester,
    ) async {
      await open(tester, _recipePhoto, builder);
      await choose(tester, recipeTile(), 'Choose from gallery');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.widgetWithText(FilledButton, 'Discard'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Discard'));
      await settleWithIo(tester);

      expect(find.byType(RecipeBuilderScreen), findsNothing);
      expect(await tester.runAsync(() => docs.read(_recipePhoto)), storedBytes);
      expect(await tester.runAsync(() => docs.list('recipe_images')), [
        'r.webp',
      ]);
    });

    testWidgets('Save after a pick writes the new photo at the stored path', (
      tester,
    ) async {
      await open(tester, _recipePhoto, builder);
      await choose(tester, recipeTile(), 'Choose from gallery');
      await tester.runAsync(() async {
        await tester.tap(find.bySemanticsIdentifier('recipe-builder-save'));
        await ioPause();
      });
      await settleWithIo(
        tester,
        done: () => find.byType(RecipeBuilderScreen).evaluate().isEmpty,
      );

      expect(find.byType(RecipeBuilderScreen), findsNothing);
      expect(recipes.byId['r']!.imagePath, _recipePhoto);
      expect(await tester.runAsync(() => docs.read(_recipePhoto)), pickedBytes);
      expect(await tester.runAsync(() => docs.list('recipe_images')), [
        'r.webp',
      ]);
    });

    testWidgets('a failed pick says it could not add the photo', (
      tester,
    ) async {
      await open(tester, _recipePhoto, builder);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/image_picker'),
        (_) async => throw PlatformException(code: 'camera_access_denied'),
      );
      await choose(tester, recipeTile(), 'Choose from gallery');
      expect(find.text('Could not add the photo'), findsOneWidget);
    });
  });

  group('custom food editor', () {
    testWidgets('Back after a remove leaves the stored photo', (tester) async {
      await open(tester, _foodPhoto, editor);
      await choose(tester, foodTile(), 'Remove photo');
      await backAndDiscard(tester);

      expect(find.byType(EditMealScreen), findsNothing);
      expect(await tester.runAsync(() => docs.read(_foodPhoto)), storedBytes);
    });

    testWidgets('Back after a pick leaves the stored photo', (tester) async {
      await open(tester, _foodPhoto, editor);
      await choose(tester, foodTile(), 'Choose from gallery');
      await backAndDiscard(tester);

      expect(find.byType(EditMealScreen), findsNothing);
      expect(await tester.runAsync(() => docs.read(_foodPhoto)), storedBytes);
      expect(await tester.runAsync(() => docs.list('meal_images')), [
        'm1.webp',
      ]);
    });

    testWidgets('Save after a pick writes the new photo at the stored path', (
      tester,
    ) async {
      await open(tester, _foodPhoto, editor);
      await choose(tester, foodTile(), 'Choose from gallery');
      await tester.runAsync(() async {
        await tester.tap(find.text('Save'));
        await ioPause();
      });
      await settleWithIo(
        tester,
        done: () => find.byType(EditMealScreen).evaluate().isEmpty,
      );

      expect(find.byType(EditMealScreen), findsNothing);
      expect(library.saved.single.localImagePath, _foodPhoto);
      expect(await tester.runAsync(() => docs.read(_foodPhoto)), pickedBytes);
      expect(await tester.runAsync(() => docs.list('meal_images')), [
        'm1.webp',
      ]);
    });

    testWidgets('Back pops at once until a field changes', (tester) async {
      await open(tester, _foodPhoto, editor);
      bool canPop() => tester
          .widget<PopScope>(
            find
                .descendant(
                  of: find.byType(EditMealScreen),
                  matching: find.byWidgetPredicate((w) => w is PopScope),
                )
                .first,
          )
          .canPop;
      expect(canPop(), isTrue);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Food name'),
        'Cereal bar 2',
      );
      await tester.pump();
      expect(canPop(), isFalse);
    });
  });
}
