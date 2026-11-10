// The wrong rows a photo's reads found (CREDITS_PLAN, step 8): "pork,
// cooked, stir-fried" logged bacon, "dark leafy greens" a beef-and-rice
// dish. Runs the real resolver over the bundled table as a photo's read,
// with the Open Food Facts products the evals met where they found one.
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
import 'package:opennutritracker/fork/food/served_with.dart';
import 'package:opennutritracker/fork/food/unasked_variant.dart';

MealEntity _product(String name, double kcal, {String brand = 'Brand'}) =>
    MealEntity(
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
        fat100: 5,
        proteins100: 5,
        sugars100: 1,
        saturatedFat100: 1,
        fiber100: 1,
      ),
      source: MealSourceEntity.off,
    );

/// The products Open Food Facts answers each query with.
final _products = <String, List<MealEntity>>{
  'Zucchini fries': [_product('Zucchini Fries', 0)],
  'fruit soup base': [_product('Soup base, dry', 357)],
  'fruit soup base, cream-based': [_product('Soup Base', 188)],
  'wheat berries, cooked': [_product('Coffee Whey Protein', 322)],
  'sweet bell pepper, raw': [_product('Roasted Red Bell Pepper Strips', 30)],
  'roasted mushrooms': [_product('Mushroom pâté with roasted mushrooms', 180)],
};

class _Search implements SearchProductsUseCase {
  final ProductsRepository repository;

  _Search(this.repository);

  @override
  Future<SearchProductsResult> searchOFFProductsByString(
    String searchString, {
    bool skipRemote = false,
  }) async => SearchProductsResult(
    meals: _products[searchString] ?? const [],
    remoteSourceEmpty: false,
  );

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

  Future<MealEntity?> photo(String query) async => (await resolver.resolve([
    ParsedMealItem(query: query, quantity: 150, unit: 'g'),
  ], fromPhoto: true)).single.selected;

  // Each wrong row, then the row it lands on now. Null: no row is right,
  // and the read breaks the food down (D9).
  final expected = <String, (String, String?)>{
    'vegetable fritters': ('Fritter, corn', null),
    'Zucchini fries': ('Zucchini Fries', null),
    'fried vegetables, battered': (
      'Fast foods, potato, french fried in vegetable oil',
      null,
    ),
    'vegetables, battered and fried': (
      'Vegetables, mixed, canned, solids and liquids',
      null,
    ),
    'carrots, battered and fried': (
      'Carrots, raw',
      'Carrots, in frying batter (with beer) deep-fried',
    ),
    'chicken sausage, grilled': (
      'Sausage, Polish, beef with chicken, hot',
      'Turkey or chicken sausage',
    ),
    'chicken apple sausage': (
      'Sausage, Polish, beef with chicken, hot',
      'Turkey or chicken sausage',
    ),
    'pork, cooked, stir-fried': (
      'Pork, cured, bacon, pre-sliced, cooked, pan-fried',
      'Pork, NFS',
    ),
    'pork, cured': (
      'Pork, cured, salt pork, raw',
      'Ham, sliced, regular (approximately 11% fat)',
    ),
    'fruit soup base': ('Soup base, dry', null),
    'herbs, fresh, mixed': (
      'Fresh wholemeal egg pasta, with anchovy-herb pesto',
      'Parsley, raw',
    ),
    'eggs, scrambled with whole milk and butter': (
      'Egg white, omelet, scrambled, or fried, with cheese',
      'Egg, whole, cooked, scrambled',
    ),
    'wheat berries, cooked': (
      'Coffee Whey Protein',
      'Wheat whole grain, boiled',
    ),
    'sweet bell pepper, raw': (
      'Roasted Red Bell Pepper Strips',
      'Peppers, sweet, red, raw',
    ),
    'tomato sauce, pizza': (
      'Pizza margherita (with tomato sauce, mozzarella)',
      'Sauce, pizza, canned, ready-to-serve',
    ),
    'roasted mushrooms': ('Mushroom pâté with roasted mushrooms', null),
    'oil': ('Oil, oat', 'Vegetable oil, NFS'),
    'coleslaw salad': ('Salad dressing, coleslaw', 'Coleslaw'),
  };
  for (final MapEntry(key: query, value: (wrong, right)) in expected.entries) {
    test('"$query" is not "$wrong"', () async {
      expect((await photo(query))?.name, right);
    });
  }

  test('"fried vegetables" are fried vegetables, not fried potatoes', () async {
    final food = await photo('fried vegetables');
    expect(food!.name, isNot(contains('potato')));
    expect(food.name, contains('vegetables'));
  });

  test('"pizza crust, cheese, tomato sauce" is not a stuffed crust', () async {
    final food = await photo('pizza crust, cheese, tomato sauce');
    expect(food!.name, startsWith('Pizza'));
    expect(food.name, isNot(contains('stuffed')));
  });

  for (final query in [
    'carrots, fried in batter',
    'chicken breast, coated in breadcrumbs',
  ]) {
    test('"$query" keeps its coating, or has no row', () async {
      final name = (await photo(query))?.name;
      if (name == null) return;
      expect(
        name,
        matches(RegExp(r'batter|bread|crumb|coat', caseSensitive: false)),
      );
    });
  }

  // The rows the replay of the evals' names found worse, then better.
  final acceptable = <String, Object>{
    'gravy, brown, from meat drippings': anyOf(isNull, isNot(contains('dry'))),
    'pork chop, pan-fried': allOf(contains('chop'), contains('pan-fried')),
    'bread, whole grain with seeds, roll': allOf(
      startsWith('Bread'),
      isNot(contains('gluten')),
    ),
    'herbs, fresh, garnish': 'Parsley, raw',
    'mashed potatoes, made with milk and butter':
        'Potatoes, mashed, home-prepared, whole milk and butter added',
    'potatoes, mashed, made with milk and butter':
        'Potatoes, mashed, home-prepared, whole milk and butter added',
    'pasta, baked with tomato sauce': allOf(
      contains('asta'),
      isNot(contains('pumpkin')),
    ),
    'fruit soup base, cream-based': isNull,
    'beef, stir-fried': 'Beef, NFS',
    'beef, cooked, stir-fried': 'Beef, NFS',
    'pork sausage, cooked': startsWith('Pork sausage'),
    'chicken breast, breaded and fried': contains('breaded'),
    'gravy, meat-based': 'Gravy, NFS',
    'egg, scrambled, with milk and butter': 'Egg, whole, cooked, scrambled',
    'chicken sausage, cooked': 'Turkey or chicken sausage',
  };
  for (final MapEntry(key: query, value: row) in acceptable.entries) {
    test('"$query" lands on an acceptable row', () async {
      expect((await photo(query))?.name, row);
    });
  }

  test('"dark leafy greens" are greens, not a beef-and-rice dish', () async {
    expect((await photo('dark leafy greens'))!.name, startsWith('Greens'));
  });

  group('the rules', () {
    test('a row of another meat than the one named is a variant', () {
      expect(
        unaskedVariant('Sausage, Polish, beef with chicken, hot', 'chicken'),
        unaskedVariantPenalty,
      );
      expect(unaskedVariant('Turkey or chicken sausage', 'chicken'), 0);
      expect(unaskedVariant('Sausage, pork and beef', 'pork and beef'), 0);
      expect(unaskedVariant('Sausage, NFS', 'chicken sausage'), 0);
    });

    test('a stuffed crust and egg whites are variants unless asked', () {
      expect(
        unaskedVariant('Pizza, cheese, stuffed crust', 'cheese pizza'),
        unaskedVariantPenalty,
      );
      expect(
        unaskedVariant('Pizza, cheese, stuffed crust', 'stuffed crust pizza'),
        0,
      );
      expect(
        unaskedVariant('Egg white omelet, scrambled, or fried', 'eggs'),
        unaskedVariantPenalty,
      );
      expect(unaskedVariant('Egg white omelet', 'egg white omelet'), 0);
    });

    test('a product at 0 kcal stays for a food that has none', () {
      final cola = _product('Cola zero', 0);
      expect(withoutUnrelatedProducts([cola], 'cola zero'), [cola]);
      expect(withoutUnrelatedProducts([_product('Cola', 0)], 'cola'), isEmpty);
      expect(
        withoutUnrelatedProducts([_product('Ice cream', 0)], 'ice cream'),
        isEmpty,
      );
    });

    test('a product of another kind stays when the name asks for it', () {
      final soup = _product('Mushroom soup', 50);
      expect(withoutUnrelatedProducts([soup], 'mushroom soup'), [soup]);
      expect(withoutUnrelatedProducts([soup], 'mushrooms'), isEmpty);
    });

    test('the food only in what a row was cooked in is not it', () {
      expect(
        servedWithOnly(
          'Fast foods, potato, french fried in vegetable oil',
          'fried vegetables',
        ),
        isTrue,
      );
      expect(
        servedWithOnly(
          'Pizza margherita (with tomato sauce)',
          'margherita pizza',
        ),
        isFalse,
      );
    });
  });
}
