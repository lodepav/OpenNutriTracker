// Phase 4: names the models gave for photographed and typed food, and the
// ingredient names of their dish breakdowns, each pinned to the table row it
// should log. Collected from the Opus, Sonnet and Haiku replays (233 dish
// names, 162 ingredients, and the typed meals' foods); these are the ones a
// person would check first.
// Runs the app's resolver over the bundled table (eval_model.dart's
// `tableMatch`), as staple_foods_test.dart does.
//
// A name the table has no right row for is pinned to what it logs, not skipped:
// a skip can't say when it starts passing, and 6 of 26 had, unnoticed.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/fork/food/local_food_data_source.dart';

import 'eval/eval_model.dart';

/// Model name → the row it should log.
const _right = {
  // Dishes and sides, as the photo and text reads named them.
  'mashed potatoes': 'Potatoes, mashed, ready-to-eat',
  'cabbage salad': 'Cabbage salad, NFS',
  'beef stroganoff': 'Beef stroganoff',
  'rye bread': 'Bread, rye',
  'borscht': 'Soup, borscht',
  'potato pancakes': 'Potato pancakes',
  'stuffed cabbage rolls': 'Stuffed cabbage rolls with beef and rice',
  'cabbage rolls': 'Stuffed cabbage rolls with beef and rice',
  'buckwheat': 'Buckwheat, boiled',
  'margherita pizza': 'Pizza margherita (with tomato sauce, mozzarella)',
  'sauerkraut': 'Sauerkraut',
  'braised sauerkraut': 'Sauerkraut, drained, braised without fat',
  'kefir': 'Kefir',
  'potato salad': 'Potato salad, German style',
  'pickled cucumber': 'Pickles, cucumber, sour',
  'caesar salad': 'Caesar salad, with romaine, no dressing',
  'boiled egg': 'Egg, whole, boiled or poached',
  'hard-boiled egg': 'Egg, whole, cooked, hard-boiled',
  'fried egg': 'Egg, whole, cooked, fried',
  'grilled salmon': 'Salmon, grilled',
  'chicken stew': 'Stew, chicken',
  // The fork's chicken schnitzel, with a portion, over the BLS pork one.
  'schnitzel':
      'Chicken schnitzel, breaded, fried (chicken escalope, breaded chicken breast)',
  'cold apple soup': 'Cold apple soup',
  'cucumber': 'Cucumber, raw',
  'red onion': 'Onions, red, raw',
  'raspberries': 'Raspberries, raw',
  'pomegranate': 'Pomegranate, raw',
  'black olives': 'Olives, black',
  'ketchup': 'Ketchup',
  'butter': 'Butter, NFS',
  'beer': 'Beer',
  'soft drink, cola': 'Soft drink, cola',
  'jams and preserves': 'Jams and preserves',
  // Breakdown ingredients, in the table's own words as the prompt asks.
  'salt, table': 'Salt, table',
  'onion, raw': 'Onions, raw',
  'egg, whole, raw': 'Egg, whole, raw',
  'butter, salted': 'Butter, salted',
  'oil, sunflower': 'Sunflower oil',
  'beef, ground, raw': 'Beef, ground, raw',
  'carrot, raw': 'Carrots, raw',
  'milk, whole': 'Milk, whole',
  'sour cream, regular': 'Sour cream, regular',
  'mayonnaise, regular': 'Mayonnaise, regular',
  'garlic, raw': 'Garlic, raw',
  'cabbage, raw': 'Cabbage, raw',
  'dill weed, fresh': 'Dill weed, fresh',
  'cheese, feta': 'Cheese, feta',
  'beets, raw': 'Beets, raw',
  'buckwheat groats, roasted, dry': 'Buckwheat groats, roasted, dry',
  'bread, white': 'Bread, white',
  'cream, heavy whipping': 'Cream, fluid, heavy whipping',
  'herring, pickled': 'Herring, pickled, semi-preserved, drained',
  'cucumber, with peel, raw': 'Cucumber, with peel, raw',
  'pork bacon': 'Pork, cured, bacon, unprepared',
  // The rows lib/fork/food/everyday_row.dart picks (S75).
  'egg': 'Egg, whole, raw, fresh',
  'eggs': 'Eggs, Grade A, Large, egg whole',
  'rice': 'Rice, white, long-grain, regular, enriched, cooked',
  'white rice': 'Rice, white, cooked, NS as to fat',
  'potatoes': 'Potatoes, boiled, cooked without skin, flesh, without salt',
  'baby potatoes': 'Potatoes, boiled, cooked without skin, flesh, without salt',
  'potato, raw': 'Potatoes, flesh and skin, raw',
  'grilled chicken breast':
      'Chicken breast, grilled without sauce, skin not eaten',
  'greek yogurt': 'Yogurt, Greek, NS as to type of milk, plain',
  'coffee': 'Coffee, NS as to type',
  'cola': 'Soft drink, cola',
  'coke': 'Soft drink, cola',
  'granola': 'Cereal, granola',
  'salad':
      'Salad, green, without dressing (garden salad, tossed salad, side salad)',
  'fries': 'Potato, french fries, NFS',
  'tomato sauce': 'Tomato products, canned, sauce',
  'mushroom cream sauce':
      'Button mushroom sauce, from white basic sauce, cream and white wine',
  'cutlet': 'Veal, leg, top round, cap off, cutlet, boneless, cooked, grilled',
  'porridge': 'Oatmeal, regular or quick, made with water, no added fat',
  'bread soup': 'Bread soup (brown bread), with raisins, apple and sour cream',
  'butter, unsalted': 'Butter, without salt',
};

/// Names the table has no right row for, and what they log instead (D11 builds
/// the table). A row added for one fails its test: move it to [_right].
const _noRowYet = {
  'fried chicken fillet': 'Chicken fillet sandwich, fried, on white bun',
  'pancakes with meat': 'Egg sandwich on griddle/pancake, with meat',
  'potato pie': 'Pie, sweet potato',
  'meat dumplings':
      'Cepelinai, potato dumplings with meat (cepelīni, zeppelins)',
};

void main() {
  late LocalFoodDataSource foods;
  setUpAll(() async => foods = await loadFoodTable());

  group(
    'model names',
    () {
      for (final MapEntry(key: name, value: row) in _right.entries) {
        test('"$name" logs "$row"', () async {
          expect((await tableMatch(foods, name))?.name, row);
        });
      }
      for (final MapEntry(key: name, value: now) in _noRowYet.entries) {
        test('"$name" has no row of its own yet, and logs "$now"', () async {
          expect((await tableMatch(foods, name))?.name, now);
        });
      }
    },
    skip: File(LocalFoodDataSource.assetPath).existsSync()
        ? false
        : 'run fork/tools/build_food_db.py first',
  );
}
