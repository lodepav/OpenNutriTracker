// S213: a bare count is that many of the food's piece, at a European size.
// Runs typed text through Log with AI's bloc over the bundled table, with
// no key, so the parser reads it and the count takes the bloc's own path.
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/utils/ai_credential_storage.dart';
import 'package:opennutritracker/features/add_meal/data/data_sources/off_data_source.dart';
import 'package:opennutritracker/features/add_meal/data/repository/products_repository.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_portion_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/usecase/read_meal_photo_usecase.dart';
import 'package:opennutritracker/features/add_meal/domain/usecase/read_meal_text_usecase.dart';
import 'package:opennutritracker/features/add_meal/domain/usecase/resolve_parsed_meals_usecase.dart';
import 'package:opennutritracker/features/add_meal/domain/usecase/search_products_usecase.dart';
import 'package:opennutritracker/features/add_meal/presentation/bloc/bulk_add_bloc.dart';
import 'package:opennutritracker/features/meal_detail/util/meal_quantity_converter.dart';
import 'package:opennutritracker/fork/bulk/count_piece.dart';
import 'package:opennutritracker/fork/food/local_food_data_source.dart';

class _TableOnlySearch implements SearchProductsUseCase {
  final ProductsRepository repository;

  _TableOnlySearch(this.repository);

  @override
  Future<SearchProductsResult> searchOFFProductsByString(
    String searchString, {
    bool skipRemote = false,
  }) async => const SearchProductsResult(meals: [], remoteSourceEmpty: true);

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

class _EmptyStorage implements FlutterSecureStorage {
  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The food a line resolved to, and the grams its amount comes to.
typedef _Logged = ({String? name, double? grams});

void main() {
  late LocalFoodTable table;
  late ResolveParsedMealsUseCase resolver;

  setUpAll(() async {
    table = LocalFoodTable.fromGzip(
      await File(LocalFoodDataSource.assetPath).readAsBytes(),
    );
    final foods = LocalFoodDataSource(
      loadTable: () async => table,
      readToggles: () async => null,
    );
    resolver = ResolveParsedMealsUseCase(
      _TableOnlySearch(ProductsRepository(OFFDataSource(), foods)),
    );
  });

  Future<_Logged> log(String text) async {
    final bloc = BulkAddBloc(
      resolver,
      ReadMealTextUseCase(
        AiCredentialStorage(_EmptyStorage()),
        (_) => throw StateError('must not be built without a key'),
      ),
      ReadMealPhotoUseCase(
        AiCredentialStorage(_EmptyStorage()),
        (_) => throw StateError('must not be built without a key'),
      ),
    );
    bloc.add(ParseBulkTextEvent(text: text, usesImperialUnits: false));
    final state =
        await bloc.stream.firstWhere((s) => s is BulkAddLoadedState)
            as BulkAddLoadedState;
    await bloc.close();
    final row = state.rows.single;
    final meal = row.meal;
    if (meal == null) return (name: null, grams: null);
    final amount = double.parse(row.amountText.replaceAll(',', '.'));
    return (
      name: meal.name,
      grams: convertQuantityToBaseUnit(amount, row.effectiveUnit, meal),
    );
  }

  /// [text] logs the row named [name] at [grams], give or take [slack].
  void pin(String text, String name, double grams, {double slack = 0.5}) {
    test('"$text" is $grams g of "$name"', () async {
      final logged = await log(text);
      expect(logged.name, name);
      expect(logged.grams, closeTo(grams, slack));
    });
  }

  group('a European piece where the table had a US one', () {
    pin('2 naan', 'Bread, naan', 180);
    pin('1 pita', 'Bread, pita', 57);
    pin('1 cheeseburger', 'Cheeseburger, NFS', 115);
    pin('3 pancakes', 'Pancakes, NFS', 99);
    pin('2 crepes', 'Crepe, NFS', 100);
    pin('1 slice of apple pie', 'Pie, apple', 115);
    pin('1 slice of cake', 'Cake, cream', 110);
    pin('1 muffin', 'Muffin, NFS', 85);
    pin('1 cookie', 'Cookie, NFS', 18);
    pin('4 chocolate candies', 'Candies, milk chocolate', 28);
    pin('1 chocolate candy', 'Chocolate candy', 8);
    pin('2 sausages', 'Sausage, NFS', 150);
    pin('2 frankfurters', 'Frankfurter, pork', 100);
    pin('1 bagel', 'Bagel', 100);
    pin('2 slices of ham', 'Ham', 50);
    pin('1 baked potato', 'Potato, baked, NFS', 200);
    pin('1 chicken pot pie', 'Pot pie, chicken', 250);
    pin('1 apple strudel', 'Strudel, apple', 125);

    test('"1 steak" is a cooked steak of 150-200 g', () async {
      final logged = await log('1 steak');
      expect(logged.name, startsWith('Steak'));
      expect(logged.grams, inInclusiveRange(150, 200));
    });

    test('"1 apple pie" is a slice, not the whole 1,200 g pie', () async {
      final logged = await log('1 apple pie');
      expect(logged.name, 'Pie, apple');
      expect(logged.grams, closeTo(115, 0.5));
    });

    // S202's "piece" for a slice matched "1 cup, pieces" of bacon, 80 g.
    pin('1 slice of bacon', 'Bacon, NS as to type of meat, cooked', 8);
  });

  group('a German row given a piece', () {
    pin('2 wheat roll', 'Wheat roll', 110);
    pin('1 rye roll', 'Rye roll', 60);
    pin('1 pretzel', 'Pretzel, salted', 85);
    pin('1 bockwurst', 'Bockwurst', 90);
    pin('2 weisswurst', 'Bavarian white sausage', 140);
    pin('1 rhenish bratwurst', 'Rhenish bratwurst', 120);
    pin('3 fish fingers', 'Fish fingers (with Alaska pollock), fried', 84);
    pin('2 sprats', 'Sprat, in oil, canned, drained', 14);
    pin('1 hot dog', 'Hot Dog', 120);
    pin('1 brownie', 'Brownies', 50);
    pin('3 pralines', 'Pralines', 24);
    pin('1 mandarin', 'Mandarin, raw', 70);
    pin('1 nectarine', 'Nectarine, raw', 140);
    pin('2 leberkaese', 'Leberkaese sausage, fried', 200);
    pin('2 white bread dumplings', 'White bread dumplings', 180);
    pin('1 sacher torte', 'Sacher torte (cake batter)', 90);
    pin('1 marble cake', 'Marble cake (cake batter)', 70);
    pin('1 salmon steak', 'Salmon steaks, fried', 140);
    pin('1 jacket potato', 'Jacket potatoes, baked', 200);
    pin('1 goose egg', 'Goose egg, raw', 145);
    pin('2 kabanossi', 'Kabanossi/Peperoni, sausage, raw, small, firm', 60);
    pin('2 rye crispbread', 'Rye crispbread', 20);
    pin('1 bread soup', _breadSoup, 250);
    pin('1 maizes zupa', _breadSoup, 250);
    pin('1 karbonāde', 'Pork schnitzel breaded, fried', 150);
    pin('3 draniki', 'Potato pancake', 210);
    pin('2 golubtsi', 'Stuffed cabbage rolls with beef and rice', 206);
  });

  group('a bare count takes the piece', () {
    // "Avocado, raw" has "1 cup" and "1 slice" beside "1 fruit".
    pin('1 avocado', 'Avocado, raw', 150);
    pin('1 kiwi', 'Kiwi fruit, raw', 75);
    // A pepperoni is its slice, not "1 sausage (10-1/4" long ...)".
    pin('2 pepperoni', 'Pepperoni, NFS', 4);

    test('whatever the serving is', () {
      final meal = _meal([
        ('1 serving', 100),
        ('1 cup', 240),
        ('1 small pancake', 25),
        ('1 medium pancake', 33),
      ], name: 'Pancakes, plain');
      expect(pieceForCount(meal, 'pancakes'), 3);
    });

    test('but a slice does not replace a serving that is no measure', () {
      final meal = _meal(
        [('1 cup', 244), ('1 slice', 38)],
        name: 'Bread',
        namedServing: false,
      );
      expect(pieceForCount(meal, 'bread'), isNull);
    });

    test('while a whole one does', () {
      final meal = _meal(
        [('1 cup', 244), ('1 slice', 15), ('1 fruit', 150)],
        name: 'Avocado',
        namedServing: false,
      );
      expect(pieceForCount(meal, 'avocado'), 2);
    });

    test('and nothing when the food has no piece', () {
      final meal = _meal([
        ('1 serving', 30),
        ('1 cup', 240),
        ('1 tbsp', 15),
      ], name: 'Sauce, NFS');
      expect(pieceForCount(meal, 'sauce'), isNull);
    });
  });

  group('the table', () {
    List<MealPortionEntity> portionsOf(String name, String source) {
      final food = table.foods.firstWhere(
        (f) => f.name == name && f.source == source,
      );
      return table.portions[food.foodId]!;
    }

    test('an override takes the place of its own label', () {
      final cheese = portionsOf('Cheese, NFS', 'fdc_survey');
      expect(cheese.first.label, '1 slice');
      expect(cheese.where((p) => p.label == '1 slice'), hasLength(1));
    });

    test('a US ladder piece is rescaled, and its serving with it', () {
      final muffin = portionsOf('Muffin, NFS', 'fdc_survey');
      expect(muffin.firstWhere((p) => p.label == '1 medium').gramWeight, 85);
      expect(muffin.every((p) => p.gramWeight != 130), isTrue);
    });

    test('a whole pie is not named a pie', () {
      final pie = portionsOf('Pie, apple', 'fdc_survey');
      expect(pie.map((p) => p.label), contains('1 whole (8-9" dia)'));
      expect(
        pie.map((p) => p.label),
        isNot(contains('1 regular pie (8-9" dia)')),
      );
    });
  });

  group('the dishes still reach their rows', () {
    for (final (text, start) in [
      ('sour cream garlic sauce', 'Garlic sauce, sour cream'),
      ('ķiploku mērce', 'Garlic sauce, sour cream'),
      ('napoleon', 'Napoleon cake'),
      ('napoleon cake', 'Napoleon cake'),
      ('napoleona kūka', 'Napoleon cake'),
      ('pelmeni', 'Pelmeni'),
      ('vareniki', 'Vareniki'),
      ('cheburek', 'Chebureki'),
      ('sklandrausis', 'Sklandrausis'),
      ('debesmanna', 'Debesmanna'),
      ('rupjmaizes kārtojums', 'Rye bread dessert'),
      ('frikadeļu zupa', 'Meatball soup'),
      ('shchi', 'Sauerkraut soup with pork'),
    ]) {
      test('"$text" is "$start…"', () async {
        expect((await log(text)).name, startsWith(start));
      });
    }
  });
}

const _breadSoup =
    'Bread soup (brown bread), with raisins, apple and sour cream';

MealEntity _meal(
  List<(String, double)> portions, {
  required String name,
  bool namedServing = true,
}) => MealEntity(
  code: null,
  name: name,
  brands: null,
  thumbnailImageUrl: null,
  mainImageUrl: null,
  url: null,
  mealQuantity: null,
  mealUnit: null,
  servingQuantity: portions.first.$2,
  servingUnit: 'g',
  servingSize: namedServing ? portions.first.$1 : null,
  nutriments: MealNutrimentsEntity.empty(),
  source: MealSourceEntity.fdc,
  portions: [
    for (final (label, grams) in portions)
      MealPortionEntity(label: label, gramWeight: grams, localized: false),
  ],
);
