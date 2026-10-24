// Phase 4: names the models gave for photographed and typed food, and the
// ingredient names of their dish breakdowns, each pinned to the table row it
// should log. Collected from the Opus, Sonnet and Haiku replays (233 dish
// names, 162 ingredients, and the typed meals' foods); these are the ones a
// person would check first.
// Runs the app's resolver over the bundled table (eval_model.dart's
// `tableMatch`), as staple_foods_test.dart does.
//
// A known miss is skipped with what it logs now, so a fix shows up as a
// test to unskip.
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
  'schnitzel': 'Pork schnitzel, fried',
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
};

/// Model name → (the row it should log, what it logs now).
const _knownMisses = {
  // Upstream's tie-break picks the shorter sibling, and pins egg and rice
  // as its own known misses (resolver_relevance.dart).
  'egg': ('Egg, whole, boiled or poached', 'Egg, creamed'),
  'rice': ('Rice, cooked, NFS', 'Rice, fried, NFS'),
  'white rice': ('Rice, white, cooked, NS as to fat', 'glutinous rice'),
  'potatoes': ('Potato, boiled, NFS', 'Potatoes, raw, skin: the skin alone'),
  'potato, raw': ('Potatoes, flesh and skin, raw', 'Potatoes, raw, skin'),
  'grilled chicken breast': (
    'Chicken breast, grilled without sauce, skin not eaten',
    'with sauce, skin eaten',
  ),
  'eggs': ('Egg, whole, raw', 'Eggs, Grade A, Large, egg yolk'),
  'greek yogurt': ('a plain Greek yogurt', 'Yogurt, Greek, with oats'),
  'coffee': ('a brewed coffee', 'Coffee, Latte'),
  // A brand row or a diet row wins on the shortest name.
  'cola': ('Soft drink, cola', 'Beverages, ZEVIA, cola, 0 kcal'),
  'coke': ('Soft drink, cola', 'nothing'),
  // A bare word ranks a dish that holds it.
  'granola': ('a granola cereal', 'Cookie, granola'),
  'salad': ('Salad, NFS', 'Salmon salad'),
  'fries': ('Potato, french fries, NFS', 'Yuca fries'),
  'tomato sauce': ('Tomato sauce, for use with vegetables', 'steak sauce'),
  'tomato paste': ('Tomato products, canned, paste', 'a pasta dish'),
  'fried chicken fillet': ('Chicken breast fillet, fried', 'a sandwich'),
  'mushroom cream sauce': (
    'Button mushroom sauce, from white basic sauce, cream and white wine',
    'beef, potatoes and vegetables in a sauce',
  ),
  'pancakes with meat': (
    'Pancakes, filled with meat',
    'Egg sandwich on griddle/pancake, with meat',
  ),
  'potato pie': ('a potato pie', 'Pie, sweet potato'),
  'cutlet': ('a cooked cutlet', 'Veal, leg, ... cutlet, boneless, raw'),
  // A variant still wins when it is the only row with every word.
  'meat dumplings': ('Pelmeni, or a meat dumpling', 'Dumpling, no meat'),
  'baby potatoes': ('Potatoes, boiled', 'Baby Toddler sweet potatoes'),
  // The table's porridge and bread soup are savoury BLS rows.
  'porridge': ('a sweet porridge', 'Porridge, roasted, with vegetable stock'),
  'bread soup': ('a sweet bread soup', 'with vegetable stock, 43 kcal'),
  // Every word must match, and the butter row says "without salt".
  'butter, unsalted': ('Butter, without salt', 'a pretzel, "no butter"'),
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
      for (final MapEntry(key: name, value: (row, now))
          in _knownMisses.entries) {
        test(
          '"$name" logs "$row"',
          () async => expect((await tableMatch(foods, name))?.name, row),
          skip: 'known miss: logs $now',
        );
      }
    },
    skip: File(LocalFoodDataSource.assetPath).existsSync()
        ? false
        : 'run fork/tools/build_food_db.py first',
  );
}
