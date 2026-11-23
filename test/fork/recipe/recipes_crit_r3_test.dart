import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:opennutritracker/core/data/data_source/custom_meal_data_source.dart';
import 'package:opennutritracker/core/data/dbo/meal_dbo.dart';
import 'package:opennutritracker/core/data/repository/favourite_meal_repository.dart';
import 'package:opennutritracker/core/data/repository/recipe_repository.dart';
import 'package:opennutritracker/core/domain/entity/app_theme_entity.dart';
import 'package:opennutritracker/core/domain/entity/config_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/domain/entity/recipe_entity.dart';
import 'package:opennutritracker/core/domain/usecase/add_tracked_day_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/delete_intake_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/delete_recipe_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_all_recipes_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_intake_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/merge_custom_meals_usecase.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/usecase/search_products_usecase.dart';
import 'package:opennutritracker/features/add_meal/presentation/bloc/food_bloc.dart';
import 'package:opennutritracker/features/add_meal/presentation/bloc/products_bloc.dart';
import 'package:opennutritracker/features/add_meal/presentation/bloc/recent_meal_bloc.dart';
import 'package:opennutritracker/features/recipes/presentation/bloc/recipes_bloc.dart';
import 'package:opennutritracker/features/recipes/presentation/screens/recipes_page.dart';
import 'package:opennutritracker/features/settings/presentation/bloc/custom_meals_bloc.dart';
import 'package:opennutritracker/fork/screens/recipes/food_search_tab_view.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:provider/provider.dart';

// Round 3 critique of recipes: a recipe delete names it, is red and can be
// undone; an empty Custom foods says what one is under its own title; the
// ingredient picker lands on recents, and its tabs fit at 200%.

const _per100 = MealNutrimentsEntity(
  energyKcal100: 150,
  carbohydrates100: 20,
  fat100: 5,
  proteins100: 10,
  sugars100: null,
  saturatedFat100: null,
  fiber100: null,
);

RecipeEntity _recipe(String id, String name) => RecipeEntity(
  id: id,
  name: name,
  description: null,
  ingredients: const [],
  totalWeightG: 400,
  aggregatedNutrimentsPer100: _per100,
  createdAt: DateTime(2026, 11, 1),
  updatedAt: DateTime(2026, 11, int.parse(id)),
  servingsCount: 2,
);

class _Recipes extends Fake implements RecipeRepository {
  final Map<String, RecipeEntity> byId;
  _Recipes(List<RecipeEntity> recipes) : byId = {for (final r in recipes) r.id: r};

  @override
  List<RecipeEntity> getAllRecipes() => byId.values.toList();

  @override
  Future<void> saveRecipe(RecipeEntity recipe) async => byId[recipe.id] = recipe;

  @override
  Future<void> deleteRecipe(String id) async => byId.remove(id);
}

class _Delete extends Fake implements DeleteRecipeUseCase {
  final _Recipes repo;
  _Delete(this.repo);

  @override
  Future<void> delete(String id) => repo.deleteRecipe(id);
}

class _Config extends Fake implements GetConfigUsecase {
  @override
  Future<ConfigEntity> getConfig() async =>
      const ConfigEntity(true, true, false, AppThemeEntity.system);
}

class _NoCustomMeals extends Fake implements CustomMealDataSource {
  @override
  List<MealDBO> getAllCustomMeals() => [];
}

class _Intakes extends Fake implements GetIntakeUsecase {}

class _DeleteIntake extends Fake implements DeleteIntakeUsecase {}

class _Tracked extends Fake implements AddTrackedDayUsecase {}

class _Merge extends Fake implements MergeCustomMealsUseCase {}

class _Favourites extends Fake implements FavouriteMealRepository {}

class _CacheManager extends Fake implements CacheManager {}

class _Search
    implements SearchProductsUseCase, GetIntakeUsecase {
  final List<IntakeEntity> recent;
  _Search(this.recent);

  @override
  Future<List<IntakeEntity>> getRecentIntake() async => recent;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Unexpected call: ${invocation.memberName}');
}

IntakeEntity _eaten(String name) => IntakeEntity(
  id: name,
  unit: 'g',
  amount: 100,
  type: IntakeTypeEntity.lunch,
  meal: MealEntity(
    code: name,
    name: name,
    url: null,
    mealQuantity: null,
    mealUnit: 'g',
    servingQuantity: null,
    servingUnit: 'g',
    servingSize: null,
    nutriments: _per100,
    source: MealSourceEntity.custom,
  ),
  dateTime: DateTime(2026, 11, 20),
);

void main() {
  final getIt = GetIt.instance;
  tearDown(() => getIt.reset());

  group('the Recipes page', () {
    late _Recipes repo;

    setUp(() {
      repo = _Recipes([
        _recipe('1', 'Greek Yogurt Parfait'),
        _recipe('2', 'Oat Bowl'),
      ]);
      getIt
        ..registerSingleton<RecipeRepository>(repo)
        // Lazy: a bloc made outside the test's zone never runs its events
        ..registerLazySingleton<RecipesBloc>(
          () => RecipesBloc(GetAllRecipesUseCase(repo)),
        )
        ..registerLazySingleton<CustomMealsBloc>(
          () => CustomMealsBloc(
            _NoCustomMeals(),
            _Intakes(),
            _DeleteIntake(),
            _Tracked(),
            _Merge(),
            _Favourites(),
          ),
        )
        ..registerSingleton<GetConfigUsecase>(_Config())
        ..registerSingleton<DeleteRecipeUseCase>(_Delete(repo))
        ..registerSingleton<CacheManager>(_CacheManager());
    });

    Future<void> pump(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.625;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ChangeNotifierProvider<EnergyUnitProvider>(
          create: (_) => EnergyUnitProvider(),
          child: MaterialApp(
            localizationsDelegates: const [S.delegate],
            supportedLocales: S.supportedLocales,
            home: const RecipesPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> selectAndDelete(WidgetTester tester, List<String> names) async {
      await tester.longPress(find.text(names.first));
      await tester.pumpAndSettle();
      for (final name in names.skip(1)) {
        await tester.tap(find.text(name));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byTooltip('Delete'));
      await tester.pumpAndSettle();
    }

    testWidgets('one recipe\'s confirm names it, Delete is red, Undo brings '
        'it back', (tester) async {
      await pump(tester);
      await selectAndDelete(tester, ['Greek Yogurt Parfait']);

      expect(find.text('Delete Greek Yogurt Parfait?'), findsOneWidget);
      final delete = find.widgetWithText(FilledButton, 'Delete');
      expect(
        tester.widget<FilledButton>(delete).style!.backgroundColor!.resolve({}),
        Theme.of(tester.element(delete)).colorScheme.error,
      );
      final before = repo.byId['1']!;
      await tester.tap(delete);
      await tester.pumpAndSettle();
      expect(repo.byId.containsKey('1'), isFalse);
      expect(find.text('Greek Yogurt Parfait deleted'), findsOneWidget);

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      // Written back as it was, not re-saved as an edit
      expect(repo.byId['1'], same(before));
      expect(find.text('Greek Yogurt Parfait'), findsOneWidget);
    });

    testWidgets('several recipes are counted, and Undo brings all back', (
      tester,
    ) async {
      await pump(tester);
      await selectAndDelete(tester, ['Greek Yogurt Parfait', 'Oat Bowl']);

      expect(find.text('Delete 2 recipes?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(repo.byId, isEmpty);
      expect(find.text('2 recipes deleted'), findsOneWidget);

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(repo.byId.keys, containsAll(['1', '2']));
    });

    testWidgets('an empty Custom foods says what one is, under its own title', (
      tester,
    ) async {
      await pump(tester);
      expect(find.widgetWithText(AppBar, 'Recipes'), findsOneWidget);

      await tester.tap(find.text('Custom foods'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(AppBar, 'Custom foods'), findsOneWidget);
      expect(find.text('No custom foods yet.'), findsOneWidget);
      expect(
        find.text(
          'Your own foods with their nutrition. Add one with New custom '
          'food.',
        ),
        findsOneWidget,
      );
    });
  });

  group('the ingredient picker', () {
    setUp(() {
      final search = _Search([_eaten('Broccoli'), _eaten('Brown rice')]);
      final config = _Config();
      getIt
        ..registerFactory<ProductsBloc>(() => ProductsBloc(search, config))
        ..registerFactory<FoodBloc>(() => FoodBloc(search, config))
        ..registerFactory<RecentMealBloc>(() => RecentMealBloc(search, config));
    });

    Future<void> pump(WidgetTester tester, {double scale = 1}) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.625;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ChangeNotifierProvider<EnergyUnitProvider>(
          create: (_) => EnergyUnitProvider(),
          child: MaterialApp(
            localizationsDelegates: const [S.delegate],
            supportedLocales: S.supportedLocales,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: Scaffold(
              body: FoodSearchTabView(onMealSelected: (_) {}),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('opens with the recent foods under an empty search', (
      tester,
    ) async {
      await pump(tester);
      expect(find.textContaining('Broccoli', findRichText: true), findsOneWidget);
      expect(find.text('Please enter a search word'), findsNothing);
    });

    testWidgets('at 200% the tab labels are not cut off', (tester) async {
      await pump(tester, scale: 2);
      for (final label in ['Products', 'Food', 'Recently']) {
        final paragraph = tester.renderObject<RenderParagraph>(
          find.descendant(of: find.byType(Tab), matching: find.text(label)),
        );
        expect(paragraph.debugHasOverflowShader, isFalse, reason: label);
        expect(paragraph.size.width, paragraph.getMaxIntrinsicWidth(double.infinity),
            reason: label);
      }
    });

    testWidgets('the search button keeps the cards\' edge gutter', (
      tester,
    ) async {
      await pump(tester, scale: 2);
      final screen = tester.view.physicalSize.width / tester.view.devicePixelRatio;
      final button = tester.getRect(find.byTooltip('Search'));
      expect(screen - button.right, greaterThanOrEqualTo(16));
    });
  });
}
