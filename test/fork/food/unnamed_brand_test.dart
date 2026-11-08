// A packet the name did not ask for trails the generic food (S196): a
// breakfast photo's "tomato", "sausages", "pickled gherkins" and "oatmeal
// porridge" logged Maestri's tinned tomatoes, Naked Glory's plant-based
// sausages, Dawtona's gherkins and a dry porridge mix, all from Open Food
// Facts. A photo of a plate shows food, not packets; a typed name may mean
// one. Runs the real resolver over the bundled table, with those products as
// Open Food Facts' hits.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/features/add_meal/data/data_sources/off_data_source.dart';
import 'package:opennutritracker/features/add_meal/data/repository/products_repository.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/usecase/resolve_parsed_meals_usecase.dart';
import 'package:opennutritracker/features/add_meal/domain/usecase/search_products_usecase.dart';
import 'package:opennutritracker/features/add_meal/util/meal_text_parser.dart';
import 'package:opennutritracker/fork/food/local_food_data_source.dart';
import 'package:opennutritracker/fork/food/unnamed_brand.dart';

MealEntity _product(String name, String? brand, double kcal) => MealEntity(
  code: '$brand $name',
  name: name,
  brands: brand,
  url: null,
  mealQuantity: null,
  mealUnit: 'g',
  servingQuantity: null,
  servingUnit: 'g',
  servingSize: null,
  nutriments: MealNutrimentsEntity(
    energyKcal100: kcal,
    carbohydrates100: 10,
    fat100: 2,
    proteins100: 3,
    sugars100: 3,
    saturatedFat100: 0.5,
    fiber100: 1,
  ),
  source: MealSourceEntity.off,
  detailed: true,
);

final _products = [
  _product('Tomatoes', 'Maestri', 20),
  _product('Sausages', 'Naked glory', 155),
  _product('Pickled Gherkins', 'Dawtona', 31),
  _product('Oatmeal porridge', 'Goodwill', 347),
  _product('apple juice', 'Innocent', 45),
  _product('Zorblax crisps', 'Zorb', 520),
];

class _Search implements SearchProductsUseCase {
  final ProductsRepository repository;

  _Search(this.repository);

  @override
  Future<SearchProductsResult> searchOFFProductsByString(
    String searchString, {
    bool skipRemote = false,
  }) async => SearchProductsResult(meals: _products, remoteSourceEmpty: false);

  @override
  Future<SearchProductsResult> searchFDCFoodByString(
    String searchString, {
    bool skipRemote = false,
    bool forResolution = false,
  }) async => SearchProductsResult(
    meals: await repository.getSupabaseFoodsByString(
      searchString,
      forResolution: forResolution,
    ),
    remoteSourceEmpty: false,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late ResolveParsedMealsUseCase resolver;

  setUpAll(() async {
    final table = LocalFoodTable.fromGzip(
      await File(LocalFoodDataSource.assetPath).readAsBytes(),
    );
    final foods = LocalFoodDataSource(
      loadTable: () async => table,
      readToggles: () async => null,
    );
    resolver = ResolveParsedMealsUseCase(
      _Search(ProductsRepository(OFFDataSource(), foods)),
    );
  });

  Future<MealEntity> resolve(
    String query, {
    double? count,
    bool fromPhoto = true,
  }) async => (await resolver.resolve([
    ParsedMealItem(query: query, quantity: count),
  ], fromPhoto: fromPhoto)).single.selected!;

  for (final (query, count) in [
    ('tomato', 1.0),
    ('sausages', 3.0),
    ('pickled gherkins', null),
    ('oatmeal porridge', null),
    ('apple juice', null),
  ]) {
    test(
      '"$query" on a photo is the food, not a packet it did not name',
      () async {
        final food = await resolve(query, count: count);
        expect(food.source, MealSourceEntity.fdc, reason: food.name);
      },
    );
  }

  test('oatmeal porridge is the cooked bowl, not the dry mix', () async {
    final food = await resolve('oatmeal porridge');
    expect(food.nutriments.energyKcal100, lessThan(150));
  });

  test('typed, a name may mean the packet, as it always did', () async {
    final food = await resolve('pickled gherkins', fromPhoto: false);
    expect(food.brands, 'Dawtona');
  });

  test('a brand the name gives keeps its product', () async {
    final food = await resolve('innocent apple juice');
    expect(food.brands, 'Innocent');
  });

  test('a product with nothing generic near it still wins', () async {
    final food = await resolve('zorblax crisps');
    expect(food.brands, 'Zorb');
  });

  test('only a branded Open Food Facts product trails', () {
    expect(unnamedBrandOf(_product('Tomatoes', null, 20), 'tomato'), 0);
    expect(
      unnamedBrandOf(
        _product('Penne', 'Barilla, Barilla G.e.R.', 357),
        'barilla penne',
      ),
      0,
    );
    expect(
      unnamedBrandOf(_product('Penne', 'Barilla', 357), 'penne'),
      unnamedBrandPenalty,
    );
  });
}
