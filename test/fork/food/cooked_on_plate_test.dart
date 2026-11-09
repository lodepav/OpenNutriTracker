// Food on a plate is cooked (S186): a photo of cooked penne logged Barilla's
// dry "Penne Pasta" from Open Food Facts, 1000 kcal for 280 g. Runs the real
// resolver over the bundled table, with that product as Open Food Facts' hit.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/features/add_meal/data/data_sources/off_data_source.dart';
import 'package:opennutritracker/features/add_meal/data/repository/products_repository.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/usecase/resolve_parsed_meals_usecase.dart';
import 'package:opennutritracker/features/add_meal/domain/usecase/search_products_usecase.dart';
import 'package:opennutritracker/features/add_meal/util/meal_text_parser.dart';
import 'package:opennutritracker/fork/food/cooked_on_plate.dart';
import 'package:opennutritracker/fork/food/local_food_data_source.dart';

MealEntity _product(String name, String brand, double kcal, double carbs) =>
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
        carbohydrates100: carbs,
        fat100: 2,
        proteins100: 12,
        sugars100: 3,
        saturatedFat100: 0.5,
        fiber100: 3,
      ),
      source: MealSourceEntity.off,
    );

final _barilla = _product('Penne Pasta', 'Barilla', 357, 71);

class _Search implements SearchProductsUseCase {
  final ProductsRepository repository;
  final List<MealEntity> products;

  _Search(this.repository, this.products);

  @override
  Future<SearchProductsResult> searchOFFProductsByString(
    String searchString, {
    bool skipRemote = false,
  }) async => SearchProductsResult(meals: products, remoteSourceEmpty: false);

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
      _Search(ProductsRepository(OFFDataSource(), foods), [_barilla]),
    );
  });

  Future<MealEntity> resolve(String query) async =>
      (await resolver.resolve([ParsedMealItem(query: query)])).single.selected!;

  for (final query in [
    'penne',
    'penne pasta',
    'penne, cooked',
    'penne pasta, cooked',
    'pasta, cooked',
    'pasta',
  ]) {
    test('"$query" on a plate is cooked pasta, not the dry product', () async {
      final food = await resolve(query);
      expect(food.brands, isNot('Barilla'));
      expect(food.nutriments.energyKcal100, lessThan(250));
    });
  }

  for (final query in ['penne, dry', 'penne pasta, uncooked']) {
    test('"$query" keeps the dry product within reach', () async {
      final item = (await resolver.resolve([
        ParsedMealItem(query: query),
      ])).single;
      expect(item.candidates.first.nutriments.energyKcal100, greaterThan(250));
    });
  }

  test('a product named by its brand stays first', () {
    final cooked = _product('Pasta, cooked', 'Table', 158, 31);
    expect(dryRowsLast([_barilla, cooked], 'barilla pasta').first, _barilla);
  });

  test('a word the brand shares with the food does not name it', () {
    final cooked = _product('Lentils, cooked', 'Table', 116, 20);
    final dry = _product('Red Lentils', "Bob's Red Mill", 340, 60);
    expect(dryRowsLast([dry, cooked], 'red lentils').first, cooked);
    expect(dryRowsLast([dry, cooked], "bob's red mill lentils").first, dry);

    final zara = _product('Penne', 'Pasta Zara', 355, 72);
    final pasta = _product('Pasta, cooked', 'Table', 158, 31);
    expect(dryRowsLast([zara, pasta], 'penne pasta').first, pasta);
  });

  test('a listing that adds the brand\'s owner still names it', () {
    final cooked = _product('Pasta, cooked', 'Table', 158, 31);
    final listed = _product('Penne', 'Barilla, Barilla G.e.R.', 357, 71);
    expect(dryRowsLast([listed, cooked], 'barilla pasta').first, listed);
  });

  test('dry rows trail the cooked ones and stay candidates', () {
    final cooked = _product('Pasta, cooked', 'Table', 158, 31);
    expect(dryRowsLast([_barilla, cooked], 'penne pasta'), [cooked, _barilla]);
  });

  test('a food only named after the staple is left alone', () {
    final cakes = _product('Rice cakes', 'Snacks', 390, 80);
    final other = _product('Rice cake, plain', 'Other', 120, 25);
    expect(dryRowsLast([cakes, other], 'rice cakes').first, cakes);
    final flour = _product('Rice flour', 'Mill', 366, 80);
    expect(dryRowsLast([flour, other], 'rice flour').first, flour);
  });

  test('a dense food that is not starch stays', () {
    final fatty = _product('Fried rice', 'Takeaway', 300, 40);
    final cooked = _product('Rice, cooked', 'Table', 130, 28);
    expect(dryRowsLast([fatty, cooked], 'rice').first, fatty);
  });

  test('the same rule holds for rice and lentils', () {
    final dryRice = _product('Basmati Rice', 'Tilda', 350, 78);
    final rice = _product('Rice, cooked', 'Table', 130, 28);
    expect(dryRowsLast([dryRice, rice], 'basmati rice').first, rice);
    final dryLentils = _product('Red Lentils', 'Bio', 340, 55);
    final lentils = _product('Lentils, cooked', 'Table', 116, 20);
    expect(dryRowsLast([dryLentils, lentils], 'lentils').first, lentils);
  });

  group('a ready food is not its powder', () {
    final powder = _product('Latte Macchiato', 'Jacobs', 420, 60);
    final latte = _product('Coffee, Latte', 'Table', 43, 4);
    final flakes = _product('Mashed potato flakes', 'Maggi', 350, 75);
    final mash = _product('Potatoes, mashed', 'Table', 106, 16);
    final cup = _product('Tomato soup mix', 'Knorr', 90, 12);
    final soup = _product('Soup, tomato', 'Table', 40, 7);

    test('the made-up drink, mash and soup come first', () {
      expect(dryRowsLast([powder, latte], 'latte').first, latte);
      expect(dryRowsLast([flakes, mash], 'mashed potatoes').first, mash);
      expect(dryRowsLast([cup, soup], 'tomato soup').first, soup);
      expect(dryRowsLast([powder, latte], 'latte'), [latte, powder]);
    });

    test('a name that asks for the powder or names the brand keeps it', () {
      expect(dryRowsLast([powder, latte], 'latte powder').first, powder);
      expect(
        dryRowsLast([flakes, mash], 'instant mashed potatoes').first,
        flakes,
      );
      expect(dryRowsLast([powder, latte], 'jacobs latte').first, powder);
    });

    test('a food only named before the drink is left alone', () {
      final beans = _product('Coffee beans', 'Roaster', 350, 30);
      expect(dryRowsLast([beans, latte], 'coffee beans').first, beans);
    });
  });
}
