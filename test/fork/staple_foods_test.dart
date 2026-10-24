// Phase 1b.4: the foods the user eats most resolve from the bundled table
// alone, without D9's estimate. Runs upstream's resolver and repository
// unchanged over the table; Open Food Facts is left out, so a pass here does
// not lean on a branded product.
//
// Known misses, not pinned here: `egg` lands on "Egg, creamed", `eggs` on a
// Foundation yolk row, `pizza` on "Pizza, no cheese, thin crust" and
// `pepperoni pizza` on "...with meat other than pepperoni". The right rows
// are in the table; upstream's tie-break picks the shorter sibling, the same
// on its backend (resolver_relevance.dart, upstream #1231).
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

  // A gap, so a recipe (D12): phase 1c's starter "grey peas with bacon".
  test('grey peas are in no table', () async {
    expect((await resolve('grey peas')).candidates, isEmpty);
  });

  // Phase 1c: the ingredient names the breakdown prompt asks for
  // (BreakDownDishUseCase.systemPrompt) land on the plain raw row. Bare
  // names do not: `carrot` finds "Carrot, dehydrated", `bacon` "Bacon,
  // turkey, microwaved", the tie-break above.
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
