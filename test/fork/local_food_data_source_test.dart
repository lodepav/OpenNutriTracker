import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/fork/food/local_food_data_source.dart';

Map<String, dynamic> _table(
  List<List<Object?>> foods, [
  Map<String, Object> portions = const {},
]) => {
  'columns': [
    'food_id',
    'source',
    'source_code',
    'name',
    'has_portion',
    'energy_kcal_100',
  ],
  'foods': foods,
  'portions': portions,
};

LocalFoodDataSource _source(
  Map<String, dynamic> json, {
  Map<String, bool>? toggles,
}) => LocalFoodDataSource(
  loadTable: () async => LocalFoodTable.fromJson(json),
  readToggles: () async => toggles,
);

void main() {
  group('wordsAgree', () {
    test('matches a word and its inflections', () {
      expect(wordsAgree('egg', 'eggs'), isTrue);
      expect(wordsAgree('potatoes', 'potato'), isTrue);
      expect(wordsAgree('cheesy', 'cheese'), isTrue);
      expect(wordsAgree('berry', 'berries'), isTrue);
    });

    test('does not match different words that share a start', () {
      expect(wordsAgree('pea', 'peanut'), isFalse);
      expect(wordsAgree('rye', 'ryegrass'), isFalse);
      expect(wordsAgree('ham', 'hamburger'), isFalse);
      expect(wordsAgree('grey', 'green'), isFalse);
    });
  });

  group('search', () {
    final json = _table(
      [
        [1, 'fdc_sr_legacy', '1', 'Bread, rye', true, 259.0],
        [2, 'bls', 'B121000', 'Wholemeal rye bread', false, 200.0],
        [3, 'fdc_sr_legacy', '3', 'Bread, wheat', true, 270.0],
        [4, 'bls', 'G1', 'Peanut butter', false, 600.0],
      ],
      {
        '1': [
          ['1 slice', 32.0],
          ['1 oz', 28.35],
        ],
      },
    );

    test('needs every query word, inflected or not', () async {
      final names = (await _source(
        json,
      ).fetchSearchWordResults('rye breads')).map((f) => f.name);
      expect(names, unorderedEquals(['Bread, rye', 'Wholemeal rye bread']));
    });

    test('a disabled source is left out', () async {
      final found = await _source(
        json,
        toggles: {'bls': false},
      ).fetchSearchWordResults('rye bread');
      expect(found.map((f) => f.source), ['fdc_sr_legacy']);
    });

    test('resolution drops a qualifier no row has, from the end', () async {
      final source = _source(json);
      expect(
        (await source.fetchSearchWordResults(
          'bread, rye, toasted',
          forResolution: true,
        )).map((f) => f.name),
        contains('Bread, rye'),
      );
      // A person's search stays exact, and a word before the first comma is
      // never dropped.
      expect(
        await source.fetchSearchWordResults('bread, rye, toasted'),
        isEmpty,
      );
      expect(
        await source.fetchSearchWordResults(
          'toasted bread, rye',
          forResolution: true,
        ),
        isEmpty,
      );
    });

    test('"pea" does not find peanut butter', () async {
      expect(await _source(json).fetchSearchWordResults('pea'), isEmpty);
    });

    test('resolution leaves the dry grain out for the cooked one', () async {
      final source = _source({
        'columns': [
          'food_id',
          'source',
          'name',
          'energy_kcal_100',
          'carbohydrates_100',
        ],
        'foods': [
          [10, 'fdc_sr_legacy', 'Buckwheat', 343.0, 71.5],
          [11, 'fdc_sr_legacy', 'Buckwheat, boiled', 115.0, 23.0],
          [12, 'bls', 'Buckwheat pancake', 260.0, 40.0],
          [13, 'bls', 'Buckwheat, fried in butter', 420.0, 20.0],
        ],
        'portions': const <String, Object>{},
      });
      Future<List<String?>> names(String query, {bool resolve = true}) async =>
          (await source.fetchSearchWordResults(
            query,
            forResolution: resolve,
          )).map((f) => f.name).toList();

      expect(
        await names('buckwheat'),
        unorderedEquals([
          'Buckwheat, boiled',
          'Buckwheat pancake',
          // Dense for fat, not dry.
          'Buckwheat, fried in butter',
        ]),
      );
      // Saying dry keeps it, though no row says so, and a person's search
      // sees every row.
      expect(await names('buckwheat, dry'), contains('Buckwheat'));
      expect(await names('buckwheat', resolve: false), hasLength(4));
    });

    test('portions come back for the foods that have them', () async {
      final portions = await _source(json).fetchPortions([1, 2]);
      expect(portions!.keys, [1]);
      expect(portions[1]!.first.label, '1 slice');
      expect(portions[1]!.first.gramWeight, 32.0);
    });
  });

  group(
    'the bundled table',
    () {
      final file = File(LocalFoodDataSource.assetPath);
      late LocalFoodDataSource source;

      setUpAll(() async {
        final table = LocalFoodTable.fromGzip(await file.readAsBytes());
        source = LocalFoodDataSource(
          loadTable: () async => table,
          readToggles: () async => null,
        );
      });

      Future<String?> top(String query) async =>
          (await source.fetchSearchWordResults(
            query,
            forResolution: true,
          )).firstOrNull?.name;

      test('holds the USDA and BLS tables', () async {
        final foods = (await source.table).foods;
        expect(foods.length, greaterThan(20000));
        expect(
          foods.map((f) => f.source).toSet(),
          containsAll(['fdc_sr_legacy', 'fdc_foundation', 'fdc_survey', 'bls']),
        );
      });

      test('finds the staples the plan names (PLAN.md phase 1b)', () async {
        for (final query in [
          'rye bread',
          'kefir',
          'quark',
          'buckwheat',
          'sauerkraut',
          'herring',
          'sour cream',
          'egg',
          'cheese pizza',
        ]) {
          expect(await top(query), isNotNull, reason: query);
        }
      });

      test('an egg resolves to a record with egg-sized portions', () async {
        final egg = (await source.fetchSearchWordResults(
          'egg',
          forResolution: true,
        )).first;
        final portions = (await source.fetchPortions([
          egg.foodId!,
        ]))![egg.foodId];
        expect(portions, isNotNull);
        expect(portions!.map((p) => p.label).join(' '), contains('egg'));
      });

      test('dishes no table has find nothing, for D9 to estimate', () async {
        expect(await top('khachapuri'), isNull);
      });
    },
    skip: File(LocalFoodDataSource.assetPath).existsSync()
        ? false
        : 'run fork/tools/build_food_db.py first',
  );
}
