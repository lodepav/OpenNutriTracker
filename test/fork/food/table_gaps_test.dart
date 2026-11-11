// Foods a photo's read found the wrong row for, or nothing: each now
// reaches the row it names. Counted table rows log their own piece, and the
// fork's dishes are not shadowed by the names that point elsewhere. Runs the
// real resolver over the bundled table as a photo's read.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/features/add_meal/data/data_sources/off_data_source.dart';
import 'package:opennutritracker/features/add_meal/data/repository/products_repository.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/usecase/resolve_parsed_meals_usecase.dart';
import 'package:opennutritracker/features/add_meal/domain/usecase/search_products_usecase.dart';
import 'package:opennutritracker/features/add_meal/util/meal_text_parser.dart';
import 'package:opennutritracker/fork/food/local_food_data_source.dart';

class _Search implements SearchProductsUseCase {
  final ProductsRepository repository;

  _Search(this.repository);

  @override
  Future<SearchProductsResult> searchOFFProductsByString(
    String searchString, {
    bool skipRemote = false,
  }) async => SearchProductsResult(meals: const [], remoteSourceEmpty: false);

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

/// The read, and the row it should log.
const _right = {
  'oat flakes, cooked': 'Oat flakes, boiled',
  // the state after the food, as a model writes it
  'eggs, scrambled': 'Egg, whole, cooked, scrambled',
  'chicken breast, roasted':
      'Chicken breast, baked, broiled, or roasted, skin not eaten, from raw',
  'bread, multigrain roll': 'Roll, multigrain',
  'ciabatta roll': 'Roll, white, hard',
  'bread roll, white': 'Roll, white, soft',
  'flatbread pizza crust': 'Wheat flatbread',
  'pastry filled with meat and vegetable': 'Empanada, beef, with vegetables',
  'meat turnover': 'Empanada, beef, with vegetables',
  'thin-crust pizza': 'Pizza, cheese, from restaurant or fast food, thin crust',
  'flatbread pizza': 'Pizza, cheese, from restaurant or fast food, thin crust',
  'falafel, fried': 'Falafel, home-prepared',
  'lamb sausage': 'Sausage, NFS',
  'spaetzle': 'Noodles, egg, enriched, cooked',
  'leafy greens, cooked': 'Greens, NS as to form, cooked',
  'mixed berries, fresh': 'Berries, NFS',
  'butter, cooked': 'Butter, NFS',
  'potatoes, cooked, baked': 'Potato, baked, NFS',
  'cabbage, sauerkraut': 'Sauerkraut',
  'pasta, lasagna sheets': 'Pasta, cooked',
  'rice, red, cooked': 'Rice, brown, cooked, no added fat',
  'chocolate cake': 'Cake or cupcake, chocolate with chocolate icing, bakery',
  'mixed salad':
      'Salad, green, without dressing (garden salad, tossed salad, side '
      'salad)',
  'oat flakes': 'Oat flakes',
  'milk chocolate': 'Candies, milk chocolate',
  'chocolate truffle': 'Candies, truffles, prepared-from-recipe',
  'kalamata olives': 'Olives blackened, in brine, drained',
  'pickled red onion': 'Silverskin onion, pickled, drained',
  'sour sweets': 'Candy, gummy',
  'gummy bears': 'Candy, gummy',
  'oat cookies': 'Cookie, oatmeal',
  'cookies': 'Cookie, NFS',
  'chicken salad':
      'Chicken or turkey garden salad, chicken and/or turkey, tomato and/or '
      'carrots, other vegetables, no dressing',
  'teriyaki salmon': 'Fish, salmon, Atlantic, wild, cooked, dry heat',
  'potato wedges': 'Potato, roasted, NFS',
  'bacon burger': 'Cheeseburger, NFS',
  'strawberry': 'Strawberries, raw',
  'blueberry': 'Blueberries, raw',
  'blackberry': 'Blackberries, raw',
  'salty licorice': 'Candy, licorice',
  'turkish delight': 'Candies, gumdrops, starch jelly pieces',
  'dried banana flakes': 'Banana, dried',
  'sweet chili sauce': 'Sweet and sour sauce',
  // a way of cooking the table has no row for is the food cooked, or
  // baked for roasted; only rows of the food itself
  'tomato, sautéed': 'Tomatoes, fresh, cooked',
  'sweet potato, roasted': 'Sweet potato, baked, fat added',
  'beets, roasted': 'Beets, NS as to form, cooked',
  'butter, sauteed': 'Butter, NFS',
  'acorn squash, roasted': 'Squash, winter, acorn, cooked, baked, with salt',
  'zucchini, grilled':
      'Squash, summer, zucchini, includes skin, cooked, boiled, drained, with '
      'salt',
  'sweet peppers, roasted':
      'Peppers, sweet, red, cooked, boiled, drained, with salt',
  // the fork's dishes, by the names they are typed as
  'cannele':
      'Canelé, French custard cake (canele, cannelé, cannele, canelé de '
      'Bordeaux, caneles)',
  'cannelé':
      'Canelé, French custard cake (canele, cannelé, cannele, canelé de '
      'Bordeaux, caneles)',
  'canele':
      'Canelé, French custard cake (canele, cannelé, cannele, canelé de '
      'Bordeaux, caneles)',
  'chicken kebab wrap':
      'Shawarma, chicken, wrap (chicken shawarma, chicken gyros, gyros, '
      'shawarma wrap)',
  'döner wrap':
      'Shawarma, chicken, wrap (chicken shawarma, chicken gyros, gyros, '
      'shawarma wrap)',
  'doner wrap':
      'Shawarma, chicken, wrap (chicken shawarma, chicken gyros, gyros, '
      'shawarma wrap)',
  'kebab in lavash':
      'Shawarma, chicken, wrap (chicken shawarma, chicken gyros, gyros, '
      'shawarma wrap)',
  'marzipan in dark chocolate':
      'Bittersweet/semisweet chocolate, filled with marzipan',
  'chocolate marzipan': 'Bittersweet/semisweet chocolate, filled with marzipan',
  'marzipan chocolate': 'Bittersweet/semisweet chocolate, filled with marzipan',
  'multigrain flakes':
      'Multigrain flakes, porridge flakes, dry (multigrain porridge flakes, '
      '4-grain flakes, four grain flakes, 5-grain flakes, five grain flakes, '
      'mixed grain flakes, daudzgraudu pārslas)',
};

/// Dishes found by a name that starts as theirs: none of the names above
/// may take them.
const _dishStarts = {
  'glazed curd snack': 'Glazed curd snack, chocolate-coated (',
  'biezpiena sieriņš': 'Glazed curd snack, chocolate-coated (',
  'сырок': 'Glazed curd snack, chocolate-coated (',
  'beef ragu': 'Beef ragu, in tomato sauce (',
  'chicken liver in cream sauce': 'Chicken liver in cream sauce (',
  'chicken kebab plate':
      'Chicken kebab plate, with fries, salad and garlic sauce (',
  'flapjack': 'Flapjack, oat bar (',
};

/// A count of a table row with no unit, and the piece it should log.
const _pieces = {
  'grilled sausages': ('Rostbratwurst sausage, grilled', '1 sausage', 100.0),
  'vienna sausages': ('Vienna sausage', '1 sausage', 50.0),
  'potato croquettes': ('Potato croquettes', '1 croquette', 25.0),
  'muesli bars': ('Muesli bar', '1 bar', 25.0),
  'marzipan chocolate': (
    'Bittersweet/semisweet chocolate, filled with marzipan',
    '1 piece',
    13.0,
  ),
};

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

  group('a photo read logs the row it names', () {
    for (final MapEntry(key: query, value: name) in _right.entries) {
      test('"$query"', () async {
        expect((await photo(query))?.name, name);
      });
    }
  });

  group('a dish is not shadowed', () {
    for (final MapEntry(key: query, value: start) in _dishStarts.entries) {
      test('"$query"', () async {
        expect((await photo(query))?.name, startsWith(start));
      });
    }
  });

  group(
    'flakes named bare are weighed dry; groats and porridge are cooked',
    () {
      const dry = {
        'oat flakes',
        'buckwheat groats, dry',
        'buckwheat groats, raw',
      };
      const cooked = {
        'buckwheat groats',
        'oat flakes, cooked',
        'oatmeal',
        'oat porridge',
      };
      for (final query in dry) {
        test('"$query" is dry', () async {
          final meal = await photo(query);
          expect(
            meal?.nutriments.energyKcal100,
            greaterThan(300),
            reason: meal?.name,
          );
        });
      }
      for (final query in cooked) {
        test('"$query" is cooked', () async {
          final meal = await photo(query);
          expect(
            meal?.nutriments.energyKcal100,
            lessThan(150),
            reason: meal?.name,
          );
        });
      }
      test('"buckwheat groats" is the cooked groats row', () async {
        final meal = await photo('buckwheat groats');
        expect(meal?.name, 'Buckwheat groats');
        expect(meal?.nutriments.energyKcal100, 118);
      });
    },
  );

  test('a roasted food is no dish of it', () async {
    expect((await photo('beetroot, roasted'))?.name, isNot(contains('salad')));
  });

  group('a count logs the row\'s piece', () {
    for (final MapEntry(key: query, value: piece) in _pieces.entries) {
      test('"3 $query"', () async {
        final meal = (await resolver.resolve([
          ParsedMealItem(query: query, quantity: 3),
        ])).single.selected;
        expect(meal?.name, piece.$1);
        expect(meal?.servingSize, startsWith(piece.$2));
        expect(meal?.servingQuantity, piece.$3);
      });
    }
  });
}
