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
      expect(wordsAgree('fanta', 'fan'), isFalse);
    });
  });

  group('fewerWords', () {
    test('cuts what follows "with", then the first words, to two', () {
      expect(fewerWords('Caesar salad with bacon'), ['Caesar salad']);
      expect(fewerWords('chicken rice pilaf'), ['rice pilaf']);
      expect(fewerWords('asian rice bowl with breaded chicken'), [
        'asian rice bowl',
        'rice bowl',
      ]);
      expect(fewerWords('cūkgaļa ar kartupeļiem'), isEmpty);
    });

    test('never leaves one word, too broad to stand for a dish', () {
      expect(fewerWords('potato balls'), isEmpty);
      expect(fewerWords('salad with burrata'), isEmpty);
      expect(fewerWords('rice with herbs'), isEmpty);
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
      // A person's search shows the rows with the most of its words, and
      // resolution never drops a word before the first comma.
      expect(
        (await source.fetchSearchWordResults(
          'bread, rye, toasted',
        )).map((f) => f.name),
        contains('Bread, rye'),
      );
      expect(
        await source.fetchSearchWordResults(
          'toasted bread, rye',
          forResolution: true,
        ),
        isEmpty,
      );
    });

    test('resolution finds the dish a longer name is named for', () async {
      final source = _source(
        _table([
          [20, 'fdc_survey', '20', 'Caesar salad, with romaine', true, 77.0],
          [21, 'fdc_sr_legacy', '21', 'Melon balls, frozen', true, 33.0],
          [22, 'fdc_survey', '22', 'Rice pilaf', true, 137.0],
          [
            23,
            'fdc_survey',
            '23',
            'Brown rice, with pilaf spices',
            true,
            120.0,
          ],
        ]),
      );
      Future<List<String?>> names(String query, {bool resolve = true}) async =>
          (await source.fetchSearchWordResults(
            query,
            forResolution: resolve,
          )).map((f) => f.name).toList();

      expect(await names('caesar salad with bacon'), [
        'Caesar salad, with romaine',
      ]);
      // A row named for the shorter name, not one that only holds it.
      expect(await names('chicken rice pilaf'), ['Rice pilaf']);
      // "Melon balls" holds "balls" but is no potato ball: nothing, so the
      // dish is broken down (D9).
      expect(await names('potato balls'), isEmpty);
      // A person's search does not cut the name, it shows the most words.
      expect(
        await names('caesar salad with bacon', resolve: false),
        contains('Caesar salad, with romaine'),
      );
    });

    test('a person\'s search with a word no row has shows the most words, '
        'the last one first', () async {
      final source = _source(
        _table([
          [30, 'fdc_sr_legacy', '30', 'Tomatoes, raw', true, 18.0],
          [31, 'fdc_sr_legacy', '31', 'Cherries, sweet, raw', true, 63.0],
          [32, 'fdc_survey', '32', 'Coffee, Turkish', true, 2.0],
          [33, 'fdc_sr_legacy', '33', 'Candies, KIT KAT Wafer Bar', true, 518],
          [34, 'fdc_sr_legacy', '34', 'Sauce, barbecue', true, 172.0],
          [35, 'fdc_sr_legacy', '35', 'Bacon, meatless', true, 309.0],
          [
            36,
            'fdc_sr_legacy',
            '36',
            'Pork, cured, bacon, unprepared',
            false,
            393,
          ],
        ]),
      );
      Future<List<String?>> names(String query, {bool resolve = false}) async =>
          (await source.fetchSearchWordResults(
            query,
            forResolution: resolve,
          )).map((f) => f.name).toList();

      expect(await names('cherry tomatoes'), ['Tomatoes, raw']);
      // One word that is not the food is no match.
      expect(await names('turkish delight'), isEmpty);
      // The resolver keeps every word, and breaks the dish down (D9).
      expect(await names('cherry tomatoes', resolve: true), isEmpty);
      // Run-together words and other spellings.
      expect(await names('kitkat'), ['Candies, KIT KAT Wafer Bar']);
      expect(await names('bbq sauce'), ['Sauce, barbecue']);
      // A variant the person did not name comes after the plain row.
      expect((await names('bacon')).first, 'Pork, cured, bacon, unprepared');
    });

    test('resolution keeps the unspecified row the cut of twenty left out '
        '(S73)', () async {
      final source = _source(
        _table([
          for (var i = 0; i < 25; i++)
            [
              100 + i,
              'fdc_survey',
              '${100 + i}',
              'Chicken, part $i',
              true,
              200,
            ],
          [
            200,
            'fdc_survey',
            '200',
            'Chicken, NS as to part and cooking method, NS as to skin eaten',
            true,
            230,
          ],
        ]),
      );
      Future<List<String?>> names({required bool resolve}) async =>
          (await source.fetchSearchWordResults(
            'chicken',
            forResolution: resolve,
          )).map((f) => f.name).toList();

      expect(await names(resolve: true), contains(startsWith('Chicken, NS')));
      expect(
        await names(resolve: false),
        isNot(contains(startsWith('Chicken, NS'))),
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

      test('the fork\'s dishes answer to their other spellings', () async {
        for (final (dish, queries) in [
          ('Solyanka', ['solyanka', 'solanka', 'soljanka', 'soļanka']),
          ('Cepelinai', ['cepelinai', 'cepelīni', 'zeppelins']),
          ('Salmon soup', ['salmon soup', 'lohikeitto', 'laša zupa']),
          ('Grey peas', ['grey peas with bacon', 'pelēkie zirņi ar speķi']),
          ('Potato balls', ['potato balls', 'roasted potato balls']),
          ('Plov', ['plov', 'chicken plov']),
          ('Khachapuri', [
            'khachapuri',
            'adjarian khachapuri',
            'adjaruli khachapuri',
          ]),
          ('Syrniki', ['syrniki', 'syrnyky']),
          ('Kharcho', ['kharcho', 'kharcho soup']),
          ('Kofta', ['kofta', 'beef kofta', 'kofte']),
          ('Odzhakhuri', ['odzhakhuri', 'ojakhuri']),
          ('Poke bowl', ['poke bowl', 'chicken poke bowl']),
          ('Beet salad', ['beet salad', 'grated beet salad', 'beetroot salad']),
          ('Chicken schnitzel', ['chicken schnitzel']),
          ('Salad, green', ['salad', 'garden salad']),
          ('Pork chop with cheese', [
            'pork chop with cheese',
            'karbonāde ar sieru',
            'pork cutlet with melted cheese',
          ]),
          ('Chicken teriyaki', ['chicken teriyaki', 'teriyaki chicken']),
          ('Shawarma, chicken', ['chicken shawarma', 'shawarma', 'gyros']),
          ('Shashlik, pork', ['shashlik', 'šašliks', 'pork skewers']),
          ('Butter chicken', [
            'butter chicken',
            'chicken tikka masala',
            'chicken makhani',
          ]),
          ('Thai green curry', ['green curry', 'thai curry']),
          ('Liver patties', ['liver patties', 'aknu pankūkas']),
          ('Kimchi pancake', ['kimchi pancake', 'kimchijeon']),
          ('Fish cutlets', ['fish cutlets', 'zivju kotletes']),
          ('Caesar wrap', ['chicken caesar wrap', 'caesar wrap']),
          ('Rassolnik', ['rassolnik', 'rasolnik']),
          ('Olivier salad', ['olivier salad', 'olivier', 'rasols']),
          ('Japchae', ['japchae', 'chapchae']),
          ('Chicken saganaki', ['chicken saganaki']),
          ('Okroshka', ['okroshka']),
          ('Biryani, lamb', ['lamb biryani']),
          ('Honey cake', ['honey cake', 'medovik']),
          ('Bulgogi, pork', ['pork bulgogi', 'jeyuk bokkeum']),
          ('Korean fried chicken', ['korean fried chicken', 'yangnyeom chicken']),
          ('Chili con carne', ['chili con carne', 'chilli con carne']),
          ('Lasagna, beef', ['beef lasagna', 'lasagna bolognese']),
        ]) {
          for (final query in queries) {
            final row = (await source.fetchSearchWordResults(
              query,
              forResolution: true,
            )).first;
            expect(row.name, startsWith(dish), reason: query);
            expect(row.source, 'fork_dishes', reason: query);
            expect(row.hasPortion, isTrue, reason: query);
          }
        }
      });

      test('dishes no table has find nothing, for D9 to estimate', () async {
        expect(await top('chakhokhbili'), isNull);
      });
    },
    skip: File(LocalFoodDataSource.assetPath).existsSync()
        ? false
        : 'run fork/tools/build_food_db.py first',
  );
}
