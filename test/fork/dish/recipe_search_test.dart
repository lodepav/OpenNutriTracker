import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/data/data_source/custom_meal_data_source.dart';
import 'package:opennutritracker/core/data/data_source/recipe_data_source.dart';
import 'package:opennutritracker/core/data/data_source/remote_search_cache_data_source.dart';
import 'package:opennutritracker/core/data/dbo/meal_dbo.dart';
import 'package:opennutritracker/core/data/dbo/meal_nutriments_dbo.dart';
import 'package:opennutritracker/core/data/dbo/recipe_dbo.dart';
import 'package:opennutritracker/core/domain/entity/app_theme_entity.dart';
import 'package:opennutritracker/core/domain/entity/config_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_intake_usecase.dart';
import 'package:opennutritracker/features/add_meal/data/repository/products_repository.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/usecase/resolve_parsed_meals_usecase.dart';
import 'package:opennutritracker/features/add_meal/domain/usecase/search_products_usecase.dart';
import 'package:opennutritracker/features/add_meal/util/meal_text_parser.dart';
import 'package:opennutritracker/fork/dish/recipe_search.dart';

void main() {
  group('nameHasQueryWords', () {
    test('every query word, in any order, up to an ending', () {
      expect(
        nameHasQueryWords('Adjarian khachapuri', 'khachapuri, adjarian'),
        isTrue,
      );
      expect(nameHasQueryWords('Pelmenis', 'pelmeni'), isTrue);
      expect(
        nameHasQueryWords('Grey peas with bacon', 'peas with bacon'),
        isTrue,
      );
    });

    test('a word the name lacks, or a blank query, does not match', () {
      expect(nameHasQueryWords('Grey peas with bacon', 'green peas'), isFalse);
      expect(nameHasQueryWords('Pelmenis', 'pelmeni, fried'), isFalse);
      expect(nameHasQueryWords('Pelmenis', '  '), isFalse);
      expect(nameHasQueryWords(null, 'pelmeni'), isFalse);
    });
  });

  group('recipe search by word (S5)', () {
    late _Recipes recipes;
    late SearchProductsUseCase search;

    setUp(() {
      recipes = _Recipes();
      search = SearchProductsUseCase(
        _NoRemote(),
        _NoIntake(),
        _NoCustomMeals(),
        _NoCache(),
        recipes,
        _Config(),
      );
    });

    Future<List<String?>> names(String query) async =>
        (await search.searchFDCFoodByString(query)).meals
            .where((m) => m.source == MealSourceEntity.recipe)
            .map((m) => m.name)
            .toList();

    test('finds a saved dish by the words a model names it with', () async {
      recipes.add('Adjarian khachapuri');
      recipes.add('Pelmenis');

      expect(await names('khachapuri, adjarian'), ['Adjarian khachapuri']);
      expect(await names('pelmeni'), ['Pelmenis']);
      // Upstream's whole-string match still works for half a word.
      expect(await names('khach'), ['Adjarian khachapuri']);
      expect(await names('borscht'), isEmpty);
    });

    test('the resolver puts the saved dish first', () async {
      recipes.add('Adjarian khachapuri');

      final [resolved] = await ResolveParsedMealsUseCase(
        search,
      ).resolve(const [ParsedMealItem(query: 'khachapuri, adjarian')]);

      expect(resolved.selected?.name, 'Adjarian khachapuri');
      expect(resolved.selected?.source, MealSourceEntity.recipe);
    });
  });
}

class _Recipes implements RecipeDataSource {
  final _all = <RecipeDBO>[];

  void add(String name) => _all.add(
    RecipeDBO(
      id: 'r-${_all.length}',
      name: name,
      description: null,
      ingredients: [],
      totalWeightG: 300,
      aggregatedNutrimentsPer100: MealNutrimentsDBO(
        energyKcal100: 250,
        carbohydrates100: 30,
        fat100: 10,
        proteins100: 10,
        sugars100: null,
        saturatedFat100: null,
        fiber100: null,
      ),
      createdAt: DateTime.utc(2026, 10, 22),
      updatedAt: DateTime.utc(2026, 10, 22),
      servingsCount: 1,
      tags: null,
      imagePath: null,
    ),
  );

  @override
  List<RecipeDBO> getAllRecipes() => _all;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _NoRemote implements ProductsRepository {
  @override
  Future<List<MealEntity>> getOFFProductsByString(String searchString) async =>
      const [];

  @override
  Future<List<MealEntity>> getSupabaseFoodsByString(
    String searchString, {
    bool forResolution = false,
  }) async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _NoIntake implements GetIntakeUsecase {
  @override
  Future<List<IntakeEntity>> getRecentIntake() async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _NoCustomMeals implements CustomMealDataSource {
  @override
  List<MealDBO> getAllCustomMeals() => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _NoCache implements RemoteSearchCacheDataSource {
  @override
  List<MealDBO> getAll() => const [];

  @override
  List<MealDBO> getAllByMostRecentlyTouched() => const [];

  @override
  Future<void> cacheFromSearch(Iterable<MealDBO> incoming) async {}

  @override
  Future<void> cacheAll(Iterable<MealDBO> incoming) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _Config implements GetConfigUsecase {
  @override
  Future<ConfigEntity> getConfig() async =>
      ConfigEntity(true, true, false, AppThemeEntity.system);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}
