import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/data/repository/recipe_repository.dart';
import 'package:opennutritracker/core/domain/entity/recipe_entity.dart';
import 'package:opennutritracker/core/domain/usecase/compute_recipe_nutrition_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/save_recipe_usecase.dart';
import 'package:opennutritracker/fork/dish/starter_recipes.dart';
import 'package:opennutritracker/fork/food/local_food_data_source.dart';

void main() {
  late LocalFoodTable table;

  setUpAll(() async {
    table = LocalFoodTable.fromGzip(
      await File(LocalFoodDataSource.assetPath).readAsBytes(),
    );
  });

  test('every food id is in the table under the food it was chosen as', () {
    final names = {for (final f in table.foods) f.foodId: f.name};
    // The comment beside each id in starter_recipes.dart, checked here so a
    // rebuilt table that renumbers rows fails loudly.
    const chosen = {
      172428: 'Peas, green, split, mature seeds, raw',
      10002256: 'Pork streaky bacon, raw cured, smoked',
      10000521: 'Onion, raw',
      10000390: 'Common salt/table salt',
      169761: 'Wheat flour, white, all-purpose, unenriched',
      2710707: 'Water, tap',
      2707152: 'Egg, whole, raw',
      2514745: 'Pork, ground, raw',
      2705853: 'Beef, ground, raw',
      169230: 'Garlic, raw',
      10000338: 'Whole milk, fresh, 3.5 % fat, pasteurised',
      10000548: 'Rye wholemeal flour',
      10000841: 'Pork lard',
      169655: 'Sugars, granulated',
      10000325: 'Potatoe, peeled, raw',
      173430: 'Butter, without salt',
      10000298: 'Carrot, raw',
      10001076: 'Sour cream, min. 20 % fat',
      10002238: 'Rye bread',
      173961: 'Cranberry sauce, canned, sweetened',
      10000698: 'Whipping cream, min. 30 % fat',
    };
    final used = {
      for (final r in starterRecipes)
        for (final i in r.ingredients) i.foodId,
    };
    expect(used, chosen.keys.toSet());
    for (final MapEntry(:key, :value) in chosen.entries) {
      expect(names[key], value, reason: 'food $key');
    }
  });

  group('StarterRecipeSeeder', () {
    late _Repository repository;
    late bool seeded;

    StarterRecipeSeeder seeder({LocalFoodTable? from}) => StarterRecipeSeeder(
      isSeeded: () async => seeded,
      markSeeded: () async => seeded = true,
      table: () async => from ?? table,
      save: SaveRecipeUseCase(repository, ComputeRecipeNutritionUseCase()),
    );

    setUp(() {
      repository = _Repository();
      seeded = false;
    });

    test('saves the four recipes once, with computed nutrition', () async {
      await seeder().run();

      expect(repository.saved.map((r) => r.name), [
        'Grey peas with bacon',
        'Pelmeni',
        'Sklandu rauši',
        'Layered rye bread dessert',
      ]);
      expect(seeded, isTrue);

      // kcal per serving, from the table: a sanity range per dish.
      double perServing(RecipeEntity r) =>
          r.aggregatedNutrimentsPer100.energyKcal100! *
          r.totalWeightG /
          100 /
          r.servingsCount!;
      final [peas, pelmeni, rausi, dessert] = repository.saved;
      expect(peas.totalWeightG, 302);
      expect(perServing(peas), inInclusiveRange(400, 500));
      expect(perServing(pelmeni), inInclusiveRange(500, 650));
      expect(perServing(rausi), inInclusiveRange(200, 300));
      expect(perServing(dessert), inInclusiveRange(550, 750));
      for (final r in repository.saved) {
        expect(r.description, contains('Latvian Institute'));
      }

      await seeder().run();
      expect(repository.saved, hasLength(4));
    });

    test('skips a recipe whose food is gone, and never throws', () async {
      final thin = LocalFoodTable(
        table.foods.where((f) => f.foodId != 10002238).toList(),
        const {},
      );

      await seeder(from: thin).run();
      expect(
        repository.saved.map((r) => r.name),
        isNot(contains('Layered rye bread dessert')),
      );
      expect(repository.saved, hasLength(3));

      repository.fail = true;
      seeded = false;
      await seeder().run();
      expect(seeded, isFalse);
    });
  });
}

class _Repository implements RecipeRepository {
  final saved = <RecipeEntity>[];
  bool fail = false;

  @override
  Future<void> saveRecipe(RecipeEntity recipe) async {
    if (fail) throw StateError('disk full');
    saved.add(recipe);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}
