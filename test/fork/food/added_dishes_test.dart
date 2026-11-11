// Everyday foods the open tables lack, added as the fork's own dishes
// (fork/data/dishes.json): each is found under the names people type, starts
// at its own serving, and has the energy its basis gives.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/fork/food/local_food_data_source.dart';

/// A dish's code, the names it is typed as, its serving, and the kcal per
/// 100 g its basis gives (labels and recipe sites, in dishes.json).
const _dishes = [
  (
    code: 'multigrain-flakes',
    typed: [
      'multigrain flakes',
      'multigrain porridge flakes',
      '4 grain flakes',
      'five grain flakes',
    ],
    serving: ('1 portion', 50.0),
    kcal: (310.0, 370.0),
  ),
  (
    code: 'glazed-curd-snack',
    typed: [
      'biezpiena sieriņš',
      'biezpiena sierins',
      'curd snack',
      'glazed curd bar',
      'sirok',
      'сырок',
    ],
    serving: ('1 bar', 40.0),
    kcal: (350.0, 430.0),
  ),
  (
    code: 'beef-ragu',
    typed: ['tomato beef ragu', 'beef ragu'],
    serving: ('1 plate', 250.0),
    kcal: (100.0, 170.0),
  ),
  (
    code: 'chicken-liver-cream',
    typed: ['chicken liver in cream sauce', 'chicken livers in cream'],
    serving: ('1 plate', 200.0),
    kcal: (140.0, 220.0),
  ),
  (
    code: 'chicken-kebab-plate',
    typed: ['chicken kebab plate', 'doner plate', 'döner plate'],
    serving: ('1 plate', 480.0),
    kcal: (160.0, 240.0),
  ),
  (
    code: 'flapjack',
    typed: ['flapjack', 'flapjacks', 'oat flapjack'],
    serving: ('1 piece', 60.0),
    kcal: (400.0, 500.0),
  ),
  (
    code: 'canele',
    // "cannele" agrees with "canned" (`wordsAgree`) and every canned row
    // with a portion and a shorter name ranks above it.
    typed: ['canelé', 'canele', 'canelés'],
    serving: ('1 canelé', 60.0),
    kcal: (250.0, 330.0),
  ),
  // Baltic and regional dishes
  (
    code: 'pelmeni',
    typed: ['pelmeni', 'pelmeņi', 'пельмени', 'meat dumplings'],
    serving: ('1 plate', 250.0),
    kcal: (180.0, 250.0),
  ),
  (
    code: 'vareniki-curd',
    typed: [
      'vareniki',
      'vareņiki ar biezpienu',
      'varenyky',
      'curd dumplings',
      'вареники с творогом',
    ],
    serving: ('1 plate', 250.0),
    kcal: (160.0, 230.0),
  ),
  (
    code: 'chebureki',
    typed: ['chebureki', 'čebureki', 'cheburek', 'чебуреки'],
    serving: ('1 cheburek', 130.0),
    kcal: (260.0, 330.0),
  ),
  (
    code: 'bacon-buns',
    typed: [
      'pīrāgi',
      'piragi',
      'speķa pīrāgi',
      'speķa pīrādziņi',
      'piradzini',
      'bacon buns',
    ],
    serving: ('1 bun', 40.0),
    kcal: (300.0, 370.0),
  ),
  (
    code: 'sorrel-soup',
    typed: ['sorrel soup', 'skābeņu zupa', 'skabenu zupa', 'shchavel soup'],
    serving: ('1 bowl', 350.0),
    kcal: (40.0, 70.0),
  ),
  (
    code: 'buckwheat-mushrooms',
    typed: [
      'buckwheat with mushrooms',
      'griķi ar sēnēm',
      'grechka s gribami',
      'гречка с грибами',
    ],
    serving: ('1 plate', 250.0),
    kcal: (100.0, 150.0),
  ),
  (
    code: 'smoked-chicken-leg',
    typed: [
      'smoked chicken leg',
      'smoked chicken',
      'kūpināts vistas stilbs',
      'kupinata vista',
    ],
    serving: ('1 leg', 200.0),
    kcal: (180.0, 240.0),
  ),
  (
    code: 'herring-fur-coat',
    typed: [
      'herring under a fur coat',
      'siļķe kažokā',
      'silke kazoka',
      'shuba',
      'селёдка под шубой',
    ],
    serving: ('1 portion', 150.0),
    kcal: (150.0, 210.0),
  ),
  (
    code: 'rye-bread-dessert',
    typed: [
      'rupjmaizes kārtojums',
      'rupjmaizes kartojums',
      'rye bread dessert',
    ],
    serving: ('1 glass', 150.0),
    kcal: (270.0, 350.0),
  ),
  (
    code: 'debesmanna',
    typed: ['debesmanna', 'cranberry mousse', 'cranberry semolina mousse'],
    serving: ('1 bowl', 200.0),
    kcal: (75.0, 120.0),
  ),
  (
    code: 'cardamom-bun',
    typed: [
      'cardamom bun',
      'kardemummabulle',
      'kardamona maizīte',
      'cardamom roll',
    ],
    serving: ('1 bun', 70.0),
    kcal: (340.0, 410.0),
  ),
  (
    code: 'napoleon-cake',
    typed: ['napoleon cake', 'napoleona kūka', 'napoleon', 'mille-feuille'],
    serving: ('1 slice', 120.0),
    kcal: (300.0, 380.0),
  ),
  (
    code: 'curd-cake',
    typed: [
      'biezpienmaize',
      'biezpiena plātsmaize',
      'biezpiena platsmaize',
      'curd cake',
      'quark cake',
    ],
    serving: ('1 piece', 100.0),
    kcal: (240.0, 310.0),
  ),
  (
    code: 'dill-sauce',
    typed: ['dill sauce', 'diļļu mērce', 'dillu merce'],
    serving: ('1 portion', 60.0),
    kcal: (120.0, 190.0),
  ),
  (
    code: 'garlic-sour-cream-sauce',
    typed: [
      'ķiploku mērce',
      'kiploku merce',
      'sour cream garlic sauce',
      'garlic sauce',
    ],
    serving: ('1 portion', 30.0),
    kcal: (230.0, 330.0),
  ),
  (
    code: 'sklandrausis',
    typed: ['sklandrausis', 'sklandrauši', 'rye carrot tart'],
    serving: ('1 sklandrausis', 90.0),
    kcal: (180.0, 260.0),
  ),
  (
    code: 'smoked-cod',
    typed: ['smoked cod', 'kūpināta menca', 'kupinata menca'],
    serving: ('1 portion', 150.0),
    kcal: (90.0, 120.0),
  ),
  (
    code: 'meatball-soup',
    typed: ['meatball soup', 'frikadeļu zupa', 'frikadelu zupa'],
    serving: ('1 bowl', 350.0),
    kcal: (35.0, 65.0),
  ),
  (
    code: 'sauerkraut-soup',
    typed: ['shchi', 'skābu kāpostu zupa', 'sauerkraut soup', 'щи'],
    serving: ('1 bowl', 350.0),
    kcal: (40.0, 70.0),
  ),
];

void main() {
  late LocalFoodTable table;
  late LocalFoodDataSource foods;

  setUpAll(() async {
    table = LocalFoodTable.fromGzip(
      await File(LocalFoodDataSource.assetPath).readAsBytes(),
    );
    foods = LocalFoodDataSource(
      loadTable: () async => table,
      readToggles: () async => null,
    );
  });

  for (final dish in _dishes) {
    group(dish.code, () {
      test('starts at its serving, at its stated energy', () {
        final row = table.foods.singleWhere(
          (f) => f.source == 'fork_dishes' && f.sourceCode == dish.code,
        );
        expect(row.servingSize, dish.serving.$1);
        expect(row.servingGramWeight, dish.serving.$2);
        final first = table.portions[row.foodId]!.first;
        expect((first.label, first.gramWeight), dish.serving);
        expect(row.energyKcal100, inInclusiveRange(dish.kcal.$1, dish.kcal.$2));
      });

      for (final typed in dish.typed) {
        test('"$typed" finds it on the Food tab', () async {
          final found = await foods.fetchSearchWordResults(typed);
          expect(found.map((r) => r.sourceCode), contains(dish.code));
        });
      }
    });
  }
}
