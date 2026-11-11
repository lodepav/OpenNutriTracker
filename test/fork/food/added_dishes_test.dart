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
