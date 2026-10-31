// Phase 1b.4: the foods the user eats most resolve from the bundled table
// alone, without D9's estimate. Runs upstream's resolver and repository,
// with the fork's seams, over the table; Open Food Facts is left out, so a
// pass here does not lean on a branded product.
//
// Upstream's tie-break picks the shorter sibling, the same on its backend
// (resolver_relevance.dart, upstream #1231): `egg` landed on "Egg,
// creamed", `eggs` on a Foundation yolk row and `pizza` on "Pizza, no
// cheese, thin crust". The fork's tie-breaks (S73, S74), its list of the
// row a name means (S75) and variant rule (S70) fixed those, `pepperoni
// pizza` and the bare names below.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/features/add_meal/data/data_sources/off_data_source.dart';
import 'package:opennutritracker/features/add_meal/data/repository/products_repository.dart';
import 'package:opennutritracker/features/add_meal/util/meal_text_parser.dart';
import 'package:opennutritracker/features/add_meal/domain/usecase/resolve_parsed_meals_usecase.dart';
import 'package:opennutritracker/features/add_meal/domain/usecase/search_products_usecase.dart';
import 'package:opennutritracker/fork/food/local_food_data_source.dart';

class _TableOnlySearch implements SearchProductsUseCase {
  final ProductsRepository repository;

  _TableOnlySearch(this.repository);

  @override
  Future<SearchProductsResult> searchOFFProductsByString(
    String searchString, {
    bool skipRemote = false,
  }) async => SearchProductsResult(meals: const [], remoteSourceEmpty: true);

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
      _TableOnlySearch(ProductsRepository(OFFDataSource(), foods)),
    );
  });

  Future<ResolvedMealItem> resolve(String query) async =>
      (await resolver.resolve([ParsedMealItem(query: query)])).single;

  for (final (query, expected) in [
    ('rye bread', 'Bread, rye'),
    ('kefir', 'Kefir'),
    ('buckwheat', 'Buckwheat, boiled'),
    // biezpiens: the model's usual English for it.
    ('quark', 'Quark, < 10 % fat in dry matter'),
    ('cottage cheese', 'Cheese, cottage, NFS'),
  ]) {
    test('$query resolves to "$expected"', () async {
      final item = await resolve(query);
      expect(item.candidates[item.selectedIndex].name, expected);
      expect(item.confidence, greaterThanOrEqualTo(kResolutionConfidenceFloor));
    });
  }

  // No open table has them; the fork's own dish row does (S72), beside
  // phase 1c's starter recipe "grey peas with bacon" (D12).
  test('grey peas resolve to the fork\'s dish', () async {
    final item = await resolve('grey peas');
    expect(item.candidates.map((c) => c.backendSource).toSet(), {
      'fork_dishes',
    });
  });

  // FNDDS's crème brûlée, at 113 kcal per 100 g, is left out of the table
  // (WRONG_ROWS, build_food_db.py): it shared BLS's name.
  test('creme brulee resolves to a custard of cream and yolks', () async {
    final item = await resolve('creme brulee');
    final row = item.candidates[item.selectedIndex];
    expect(row.name, 'Creme brulee');
    expect(row.nutriments.energyKcal100, greaterThan(300));
  });

  // A bare family name lands on the everyday row, not the shortest sibling:
  // the user's log typed these, and "chicken" logged "Chicken, back",
  // "tomato" "Tomato, green, pickled", "salad" "Salmon salad". A fork dish
  // wins a tie with the table's odd forms (S74): "lasagna" logged "Lasagna,
  // Vegetable, frozen, baked"; a form the query names keeps its row.
  for (final (query, expected) in [
    ('chicken', 'Chicken, NS as to part'),
    ('bacon', 'Bacon, NS as to type of meat, cooked'),
    ('tomato', 'Tomatoes, '),
    ('salad', 'Salad, green, without dressing'),
    ('pepperoni pizza', 'Pizza, with pepperoni'),
    ('coffee', 'Coffee, NS as to type'),
    ('kvass, bread-based', 'Kvass, bread drink'),
    ('lasagna', 'Lasagna, beef, homemade'),
    ('egg', 'Egg, whole, raw, fresh'),
    ('eggs', 'Eggs, Grade A, Large, egg whole'),
    ('pizza', 'Pizza, cheese, from restaurant or fast food, NS as to'),
    ('cheese pizza', 'Pizza, cheese, from restaurant or fast food, NS as to'),
    ('fries', 'Potato, french fries, NFS'),
    ('tomato sauce', 'Tomato products, canned, sauce'),
    ('tomato paste', 'Tomato products, canned, paste'),
    ('potato', 'Potatoes, boiled, cooked without skin'),
    ('potatoes', 'Potatoes, boiled, cooked without skin'),
    ('porridge', 'Oatmeal, regular or quick, made with water'),
    ('bread soup', 'Bread soup (brown bread), with raisins'),
    ('butter, unsalted', 'Butter, without salt'),
    ('unsalted butter', 'Butter, without salt'),
    ('cola', 'Soft drink, cola'),
    ('coke', 'Soft drink, cola'),
    ('diet coke', 'Soft drink, cola, diet'),
    ('greek yogurt', 'Yogurt, Greek, NS as to type of milk, plain'),
    ('granola', 'Cereal, granola'),
    ('basmati rice', 'Rice, white, long-grain, regular, enriched, cooked'),
    ('jasmine rice', 'Rice, white, long-grain, regular, enriched, cooked'),
    ('cooked basmati rice', 'Rice, white, long-grain'),
    ('chicken broth', 'Soup, chicken broth, ready-to-serve'),
    ('beef broth', 'Soup, beef broth or bouillon canned, ready-to-serve'),
    (
      'coconut milk',
      'Nuts, coconut milk, canned (liquid expressed from grated meat and water)',
    ),
    ('vegetable stock', 'Soup, vegetable broth, ready to serve'),
    ('sour cream', 'Cream, sour, cultured'),
    ('vegetable lasagna', 'Lasagna, Vegetable'),
    ('hamburger bun, plain', 'Roll, white, hamburger bun'),
    ('salad dressing, caesar', 'Salad dressing, caesar dressing, regular'),
    ('beef patty, cooked, pan-broiled', 'Beef, ground, 70%'),
    ('bacon, cooked, pan-fried', 'Pork, cured, bacon'),
    ('tortilla, wheat flour', 'Wheat flour tortilla'),
    ('potatoes, boiled, cooked without skin', 'Potatoes, boiled, cooked'),
    ('mayonnaise', 'Mayonnaise, regular'),
    ('bread, hamburger bun', 'Roll, white, hamburger bun'),
    ('spaghetti, cooked', 'Pasta, cooked'),
    ('rice, white, cooked, fried', 'Rice, fried, NFS'),
    ('potatoes, roasted', 'Potato, roasted, NFS'),
    ('gravy, onion', 'Gravy, beef, canned, ready-to-serve'),
    ('salad dressing, vinaigrette', 'Salad dressing, home recipe, vinegar'),
    ('carrots, cooked', 'Carrots, NS as to form, cooked'),
    ('salmon, baked', 'Fish, salmon, baked or broiled'),
    ('rice, white, cooked', 'Rice, white, cooked, NS as to fat'),
    ('rice', 'Rice, white, long-grain, regular, enriched, cooked'),
    ('lentils, red, cooked', 'Lentils, mature seeds, cooked'),
    ('noodles, chinese, cooked', 'Noodles, cooked'),
    ('tomato sauce, cooked', 'Tomato products, canned, sauce'),
    ('white sauce, prepared with milk', 'Bechamel sauce'),
    ('mint, fresh', 'Spearmint, fresh'),
    ('chicken, fried', 'Chicken, broilers or fryers, meat and skin'),
    ('dumplings, vegetable, cooked', 'Wonton, dumpling or pot sticker'),
    ('gyoza', 'Wonton, dumpling or pot sticker, fried'),
    ('tzatziki sauce', 'Tzatziki dip'),
    ('flan', 'Flan'),
    ('spaghetti, cooked, enriched', 'Pasta, cooked'),
  ]) {
    test('bare "$query" resolves to "$expected..."', () async {
      final item = await resolve(query);
      expect(item.candidates[item.selectedIndex].name, startsWith(expected));
      expect(item.confidence, greaterThanOrEqualTo(kResolutionConfidenceFloor));
    });
  }

  // Phase 1c: the ingredient names the breakdown prompt asks for
  // (BreakDownDishUseCase.systemPrompt) land on the plain raw row.
  for (final (query, expected) in [
    ('egg, whole, raw', 'Egg, whole, raw'),
    ('carrot, raw', 'Carrots, raw'),
    (
      'wheat flour, white, all-purpose',
      'Wheat flour, white, all-purpose, unenriched',
    ),
    ('sour cream, regular', 'Sour cream, regular'),
    ('beef, ground, raw', 'Beef, ground, raw'),
    ('split peas, raw', 'Peas, green, split, mature seeds, raw'),
    ('cheese, mozzarella, whole milk', 'Cheese, mozzarella, whole milk'),
    ('pork bacon', 'Pork, cured, bacon, unprepared'),
  ]) {
    test('ingredient "$query" resolves to "$expected"', () async {
      final item = await resolve(query);
      expect(item.candidates[item.selectedIndex].name, expected);
      expect(item.confidence, greaterThanOrEqualTo(kResolutionConfidenceFloor));
    });
  }
}
