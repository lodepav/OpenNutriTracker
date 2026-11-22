import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:opennutritracker/core/data/data_source/custom_meal_data_source.dart';
import 'package:opennutritracker/core/data/dbo/meal_dbo.dart';
import 'package:opennutritracker/core/data/dbo/meal_nutriments_dbo.dart';
import 'package:opennutritracker/core/data/repository/favourite_meal_repository.dart';
import 'package:opennutritracker/core/data/repository/recipe_repository.dart';
import 'package:opennutritracker/core/domain/entity/app_theme_entity.dart';
import 'package:opennutritracker/core/domain/entity/config_entity.dart';
import 'package:opennutritracker/core/domain/entity/recipe_entity.dart';
import 'package:opennutritracker/core/domain/usecase/add_tracked_day_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/delete_intake_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/delete_recipe_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_all_recipes_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_intake_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_recipe_by_id_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/merge_custom_meals_usecase.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/features/recipes/presentation/bloc/recipe_detail_bloc.dart';
import 'package:opennutritracker/features/recipes/presentation/bloc/recipes_bloc.dart';
import 'package:opennutritracker/features/recipes/presentation/screens/recipes_page.dart';
import 'package:opennutritracker/features/settings/presentation/bloc/custom_meals_bloc.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:opennutritracker/fork/custom_food/serving_mode.dart';
import 'package:opennutritracker/fork/recipe/recipe_builder.dart';
import 'package:opennutritracker/fork/recipe/recipe_list.dart';
import 'package:opennutritracker/fork/display/contrast.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:provider/provider.dart';


// Leftovers of G3 (recipes and profiles): custom foods typed per serving,
// a search on custom foods, no + menu repeating the footer, and the audit's
// P3s on the Recipes page.

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

void main() {
  final getIt = GetIt.instance;
  late _Recipes recipes;
  late _Library library;

  setUp(() {
    recipes = _Recipes()..byId['r'] = _bowl;
    library = _Library()
      ..meals.addAll([_food('Cereal bar'), _food('Granola')]);
    CustomFoodModes.perServing.value = const {};
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
  tearDown(() {
    CustomFoodModes.perServing.value = const {};
    return getIt.reset();
  });

  final navigator = GlobalKey<NavigatorState>();

  Future<void> pump(
    WidgetTester tester,
    Widget home, {
    ThemeData? theme,
  }) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider<EnergyUnitProvider>(
        create: (_) => EnergyUnitProvider(),
        child: MaterialApp(
          navigatorKey: navigator,
          theme: theme,
          localizationsDelegates: const [S.delegate],
          supportedLocales: S.supportedLocales,
          home: home,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }


  Future<void> openFoods(WidgetTester tester) async {
    await pump(tester, const RecipesPage());
    await tester.tap(find.text('Custom foods 2'));
    await tester.pumpAndSettle();
  }

  // G3-19: a food typed per serving is listed per serving.
  testWidgets('a food saved per serving says per serving', (tester) async {
    CustomFoodModes.perServing.value = {'Cereal bar'};
    await openFoods(tester);
    expect(find.textContaining('per serving'), findsOneWidget);
    expect(find.textContaining('per 100 g'), findsOneWidget);
  });

  // G3-25: the list filters by name, with a way back from no match.
  testWidgets('the custom foods search filters by name', (tester) async {
    await openFoods(tester);
    final search = find.widgetWithText(TextField, 'Search foods');
    await tester.enterText(search, 'gran');
    await tester.pumpAndSettle();
    expect(find.text('Granola'), findsOneWidget);
    expect(find.text('Cereal bar'), findsNothing);

    await tester.enterText(search, 'zzz');
    await tester.pumpAndSettle();
    expect(find.text('No foods match'), findsOneWidget);
    await tester.tap(find.text('Clear search'));
    await tester.pumpAndSettle();
    expect(find.text('Cereal bar'), findsOneWidget);
    expect(find.text('Granola'), findsOneWidget);
  });

  // G3-28: the footer holds the page's actions; no + menu repeats them.
  testWidgets('no + menu repeats the footer', (tester) async {
    await pump(tester, const RecipesPage());
    expect(find.byIcon(Icons.add), findsNothing);
    expect(find.text('Import recipe'), findsOneWidget);
    await tester.tap(find.text('Custom foods 2'));
    await tester.pumpAndSettle();
    expect(find.text('New custom food'), findsOneWidget);
  });

  // Audit P3s: the recipes search has a label; More and Delete keep 8 dp
  // apart; "per 100 g" is spoken in words.
  testWidgets('the recipes search is labelled', (tester) async {
    await pump(tester, const RecipesPage());
    expect(find.widgetWithText(TextField, 'Search recipes'), findsOneWidget);
  });

  testWidgets('a custom food row keeps its buttons apart and speaks grams', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await openFoods(tester);
    final bin = tester.getRect(find.byTooltip('Delete Cereal bar'));
    final moreButton = tester.getRect(
      find.ancestor(
        of: find.byIcon(Icons.more_vert_rounded).first,
        matching: find.byType(IconButton),
      ),
    );
    expect(bin.left - moreButton.right, greaterThanOrEqualTo(8));
    expect(find.bySemanticsLabel(RegExp('per 100 grams')), findsWidgets);
    handle.dispose();
  });

  testWidgets('the empty recipes icon reaches 3:1 on its tint', (
    tester,
  ) async {
    recipes.byId.clear();
    // a pale accent the user may pick
    await pump(
      tester,
      const RecipesPage(),
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.yellow,
        ).copyWith(primary: const Color(0xFFFFE066)),
      ),
    );
    final icon = tester.widget<Icon>(find.byIcon(Icons.menu_book_rounded));
    final context = tester.element(find.byIcon(Icons.menu_book_rounded));
    final accent = Theme.of(context).colorScheme.primary;
    final tint = Color.alphaBlend(
      accent.withValues(alpha: 0.12),
      AppPalette.light.canvas,
    );
    expect(contrastRatio(icon.color!, tint), greaterThanOrEqualTo(3));
  });

  // G3-16: at 200% the builder's totals take one line, not four columns
  // whose labels wrap; a macro dot stays with its letter
  testWidgets('the builder footer at 200% puts the totals on one line', (
    tester,
  ) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<EnergyUnitProvider>(
        create: (_) => EnergyUnitProvider(),
        child: MaterialApp(
          localizationsDelegates: const [S.delegate],
          supportedLocales: S.supportedLocales,
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Scaffold(
              bottomNavigationBar: BuilderSaveBar(
                per100: _per100,
                totalWeightG: 200,
                saving: false,
                onSave: () {},
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.text('protein g'), findsNothing);
    expect(find.textContaining('300 kcal'), findsOneWidget);
  });

  testWidgets('a macro dot is joined to its letter', (tester) async {
    late List<InlineSpan> spans;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            spans = macroSpans(context, (
              kcal: 1,
              carbs: 1,
              fat: 1,
              protein: 1,
            ), small: true);
            return const SizedBox();
          },
        ),
      ),
    );
    for (var i = 0; i < spans.length; i++) {
      if (spans[i] is WidgetSpan) {
        expect((spans[i + 1] as TextSpan).text, '⁠');
      }
    }
  });

  // G3-7: at 200% the Recipes footer stacks its two buttons
  testWidgets('the Recipes footer stacks its buttons at 200%', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pump(tester, const RecipesPage());
    final import = tester.getRect(find.text('Import recipe'));
    final create = tester.getRect(find.text('Create Recipe'));
    expect(create.top, greaterThan(import.bottom));
  });

  // the searches' edge is the theme's 3:1 one (S552), not a fill alone
  testWidgets('the recipe and food searches have a 3:1 edge', (tester) async {
    void edgeOf(String label) {
      final field = tester.widget<TextField>(
        find.widgetWithText(TextField, label),
      );
      final side =
          (field.decoration!.enabledBorder! as OutlineInputBorder).borderSide;
      expect(side.style, BorderStyle.solid, reason: label);
      expect(
        contrastRatio(side.color, AppPalette.light.canvas),
        greaterThanOrEqualTo(3),
        reason: label,
      );
    }

    await openFoods(tester);
    edgeOf('Search foods');
    await tester.tap(find.textContaining('Recipes').first);
    await tester.pumpAndSettle();
    edgeOf('Search recipes');
  });
}
