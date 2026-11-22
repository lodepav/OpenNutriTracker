import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:hive_ce/hive.dart';
import 'package:opennutritracker/core/data/data_source/custom_meal_data_source.dart';
import 'package:opennutritracker/core/data/dbo/meal_dbo.dart';
import 'package:opennutritracker/core/data/dbo/meal_nutriments_dbo.dart';
import 'package:opennutritracker/core/data/repository/favourite_meal_repository.dart';
import 'package:opennutritracker/core/data/repository/recipe_repository.dart';
import 'package:opennutritracker/core/domain/entity/app_theme_entity.dart';
import 'package:opennutritracker/core/domain/entity/config_entity.dart';
import 'package:opennutritracker/core/domain/entity/recipe_entity.dart';
import 'package:opennutritracker/core/domain/usecase/add_tracked_day_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/compute_recipe_nutrition_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/delete_intake_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/delete_recipe_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_all_recipes_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_intake_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_recipe_by_id_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/merge_custom_meals_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/save_recipe_usecase.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/features/recipes/presentation/bloc/recipe_builder_bloc.dart';
import 'package:opennutritracker/features/recipes/presentation/bloc/recipe_detail_bloc.dart';
import 'package:opennutritracker/features/recipes/presentation/bloc/recipes_bloc.dart';
import 'package:opennutritracker/features/recipes/presentation/screens/recipe_builder_screen.dart';
import 'package:opennutritracker/features/recipes/presentation/screens/recipe_detail_screen.dart';
import 'package:opennutritracker/features/recipes/presentation/screens/recipes_page.dart';
import 'package:opennutritracker/features/settings/presentation/bloc/custom_meals_bloc.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:provider/provider.dart';

import '../../helpers/fake_hive_db_provider.dart';
import '../../helpers/hive_test_setup.dart';
import '../../helpers/test_l10n.dart';

// Round 4 critique of recipes: recipe detail's Delete and the custom food
// bin confirm by name in red and offer Undo, as the list's bulk delete does;
// the builder's Discard is red too.

const _per100 = MealNutrimentsEntity(
  energyKcal100: 150,
  carbohydrates100: 20,
  fat100: 5,
  proteins100: 10,
  sugars100: null,
  saturatedFat100: null,
  fiber100: null,
);

final _bowl = RecipeEntity(
  id: 'r',
  name: 'Oat Bowl',
  description: null,
  ingredients: const [],
  totalWeightG: 400,
  aggregatedNutrimentsPer100: _per100,
  createdAt: DateTime(2026, 11, 1),
  updatedAt: DateTime(2026, 11, 2),
  servingsCount: 2,
);

MealDBO _food(String name) => MealDBO(
  code: null,
  name: name,
  brands: null,
  thumbnailImageUrl: null,
  mainImageUrl: null,
  url: null,
  mealQuantity: '40',
  mealUnit: 'g',
  servingQuantity: 40,
  servingUnit: 'g',
  servingSize: null,
  nutriments: MealNutrimentsDBO.fromProductNutrimentsEntity(_per100),
  source: MealSourceDBO.custom,
  localImagePath: 'photos/bar.jpg',
);

class _Recipes extends Fake implements RecipeRepository {
  final byId = <String, RecipeEntity>{};

  @override
  List<RecipeEntity> getAllRecipes() => byId.values.toList();

  @override
  Future<void> saveRecipe(RecipeEntity recipe) async => byId[recipe.id] = recipe;
}

class _GetRecipe extends Fake implements GetRecipeByIdUseCase {
  final _Recipes repo;
  _GetRecipe(this.repo);

  @override
  RecipeEntity? getById(String id) => repo.byId[id];
}

class _DeleteRecipe extends Fake implements DeleteRecipeUseCase {
  final _Recipes repo;
  _DeleteRecipe(this.repo);

  @override
  Future<void> delete(String id) async => repo.byId.remove(id);
}

class _Library extends Fake implements CustomMealDataSource {
  final meals = <MealDBO>[];
  final saved = <MealDBO>[];

  @override
  List<MealDBO> getAllCustomMeals() => List.of(meals);

  @override
  Future<void> deleteCustomMeal(String mealKey) async =>
      meals.removeWhere((m) => (m.code ?? m.name) == mealKey);

  @override
  Future<void> saveCustomMeal(MealDBO mealDBO, {MealDBO? previous}) async {
    saved.add(mealDBO);
    meals.add(mealDBO);
  }
}

class _Favourites extends Fake implements FavouriteMealRepository {
  @override
  Future<void> keepLatestCustomMealSnapshot(String libraryKey) async {}
}

class _Config extends Fake implements GetConfigUsecase {
  @override
  Future<ConfigEntity> getConfig() async =>
      const ConfigEntity(true, true, false, AppThemeEntity.system);
}

class _Intakes extends Fake implements GetIntakeUsecase {}

class _DeleteIntake extends Fake implements DeleteIntakeUsecase {}

class _Tracked extends Fake implements AddTrackedDayUsecase {}

class _Merge extends Fake implements MergeCustomMealsUseCase {}

class _CacheManager extends Fake implements CacheManager {}

Color? _fill(WidgetTester tester, Finder button) =>
    tester.widget<FilledButton>(button).style?.backgroundColor?.resolve({});

Color _error(WidgetTester tester, Finder at) =>
    Theme.of(tester.element(at)).colorScheme.error;

void main() {
  final getIt = GetIt.instance;
  late _Recipes recipes;
  late _Library library;

  setUp(() {
    recipes = _Recipes()..byId['r'] = _bowl;
    library = _Library()..meals.add(_food('Cereal bar'));
    getIt
      ..registerSingleton<RecipeRepository>(recipes)
      ..registerLazySingleton<RecipesBloc>(
        () => RecipesBloc(GetAllRecipesUseCase(recipes)),
      )
      ..registerFactory<RecipeDetailBloc>(
        () => RecipeDetailBloc(_GetRecipe(recipes), _DeleteRecipe(recipes)),
      )
      ..registerSingleton<CustomMealDataSource>(library)
      ..registerLazySingleton<CustomMealsBloc>(
        () => CustomMealsBloc(
          library,
          _Intakes(),
          _DeleteIntake(),
          _Tracked(),
          _Merge(),
          _Favourites(),
        ),
      )
      ..registerSingleton<GetConfigUsecase>(_Config())
      ..registerSingleton<DeleteRecipeUseCase>(_DeleteRecipe(recipes))
      ..registerSingleton<CacheManager>(_CacheManager());
  });
  tearDown(() => getIt.reset());

  final navigator = GlobalKey<NavigatorState>();

  Future<void> pump(WidgetTester tester, Widget home) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider<EnergyUnitProvider>(
        create: (_) => EnergyUnitProvider(),
        child: MaterialApp(
          navigatorKey: navigator,
          localizationsDelegates: const [S.delegate],
          supportedLocales: S.supportedLocales,
          home: home,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('recipe detail\'s Delete names the recipe in red, and Undo '
      'brings it back', (tester) async {
    await pump(tester, const Scaffold());
    navigator.currentState!.push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(
          arguments: RecipeDetailArguments(recipeId: 'r'),
        ),
        builder: (_) => const RecipeDetailScreen(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.more_vert_rounded));
    await tester.pumpAndSettle();
    // The test font's square glyphs overflow "Log another amount"'s row
    tester.takeException();
    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle();

    expect(find.text('Delete Oat Bowl?'), findsOneWidget);
    final delete = find.widgetWithText(FilledButton, 'Delete');
    expect(_fill(tester, delete), _error(tester, delete));
    await tester.tap(delete);
    await tester.pumpAndSettle();
    expect(recipes.byId, isEmpty);
    expect(find.byType(RecipeDetailScreen), findsNothing);
    expect(find.text('Oat Bowl deleted'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(recipes.byId['r'], same(_bowl));
  });

  testWidgets('the custom food bin names the food in red, and Undo writes '
      'the stored row back', (tester) async {
    await pump(tester, const RecipesPage());
    await tester.tap(find.text('Custom foods 1'));
    await tester.pumpAndSettle();
    final stored = library.meals.single;

    await tester.tap(find.byTooltip('Delete Cereal bar'));
    await tester.pumpAndSettle();
    expect(find.text('Delete Cereal bar?'), findsOneWidget);
    final delete = find.widgetWithText(FilledButton, 'Delete');
    expect(_fill(tester, delete), _error(tester, delete));
    await tester.tap(delete);
    await tester.pumpAndSettle();
    expect(library.meals, isEmpty);
    expect(find.text('Cereal bar deleted'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(library.saved.single, same(stored));
    // The list follows the restore
    expect(find.text('Cereal bar'), findsOneWidget);
  });

  testWidgets('the builder\'s Discard is red', (tester) async {
    final compute = ComputeRecipeNutritionUseCase();
    getIt.registerFactory<RecipeBuilderBloc>(
      () => RecipeBuilderBloc(compute, SaveRecipeUseCase(recipes, compute)),
    );
    await pump(tester, const Scaffold());
    navigator.currentState!.push(
      MaterialPageRoute<void>(
        settings: RouteSettings(
          arguments: RecipeBuilderArguments(existing: _bowl),
        ),
        builder: (_) => const RecipeBuilderScreen(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Oat Bowl 2');
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    final discard = find.widgetWithText(
      FilledButton,
      l10nEn.discardChangesConfirmLabel,
    );
    expect(_fill(tester, discard), _error(tester, discard));
  });

  group('a deleted custom food row', () {
    setUpAll(() {
      Hive.init('.');
      registerHiveAdaptersOnce();
    });
    tearDownAll(Hive.deleteFromDisk);

    test('can be saved back into the library as it was', () async {
      final box = await Hive.openBox<MealDBO>(
        'crit_r4_custom_${DateTime.now().microsecondsSinceEpoch}',
      );
      final source = CustomMealDataSource(
        FakeHiveDBProvider(customMealBox: box),
      );
      await box.add(_food('Cereal bar'));
      final stored = source.getAllCustomMeals().single;

      await source.deleteCustomMeal('Cereal bar');
      expect(source.getAllCustomMeals(), isEmpty);
      await source.saveCustomMeal(stored);

      final back = source.getAllCustomMeals().single;
      expect(back.localImagePath, 'photos/bar.jpg');
      expect(back.servingQuantity, 40);
      // No re-stamp: the row keeps the version it was written under
      expect(back.dataVersion, isNull);
    });
  });
}
