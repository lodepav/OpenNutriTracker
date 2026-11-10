import 'package:opennutritracker/fork/food/local_food_data_source.dart';
import 'package:opennutritracker/fork/food/served_with.dart';

/// Vegetables a plate holds cooked, coated or fried, whose product as a
/// snack (fries, crisps, sticks) is another food. Not potatoes, whose
/// fries and crisps are the food.
const _vegetables = {
  'broccoli',
  'carrot',
  'carrots',
  'zucchini',
  'courgette',
  'courgettes',
  'cauliflower',
  'pepper',
  'peppers',
  'onion',
  'onions',
  'eggplant',
  'eggplants',
  'aubergine',
  'aubergines',
  'mushroom',
  'mushrooms',
  'spinach',
  'kale',
  'beet',
  'beets',
  'beetroot',
  'pumpkin',
  'squash',
  'cabbage',
  'celery',
  'celeriac',
  'asparagus',
  'cucumber',
  'parsnip',
  'parsnips',
  'okra',
  'leek',
  'leeks',
  'vegetable',
  'vegetables',
  'veggie',
  'veggies',
};

/// Beans a plate holds as a vegetable, by the word before: not jelly or
/// coffee beans.
const _vegetableBeans = {'green', 'string', 'runner', 'french', 'wax', 'broad'};

/// A vegetable cut and cooked as a snack is that vegetable: "carrot fries".
const _cutAs = {'fries', 'sticks', 'chips', 'crisps'};

/// Words beside which a vegetable names another product: "vegetable oil",
/// "vegetable stock".
const _madeFrom = {
  'oil',
  'oils',
  'stock',
  'broth',
  'bouillon',
  'shortening',
  'margarine',
  'spread',
  'juice',
  'soup',
};

/// The vegetable [query] names as its food ([headNoun]), if any:
/// "broccoli" in "broccoli, battered, fried", "carrot" in "carrot fries";
/// none in "carrot cake", "pepper jack cheese" or "pumpkin seeds".
String? namedVegetable(String query) {
  final words = nameWords(
    query.split(',').first.split(RegExp(r'\s(with|in|and)\s')).first,
  );
  if (words.any(_madeFrom.contains)) return null;
  final head = headNoun(query, oneWord: true);
  if (head == null) return null;
  final at = words.lastIndexOf(head);
  final before = at > 0 ? words[at - 1] : null;
  if (_cutAs.contains(head) && before != null) {
    return _vegetables.contains(before) ? before : null;
  }
  if (head == 'beans') {
    return _vegetableBeans.contains(before) ? head : null;
  }
  return _vegetables.contains(head) ? head : null;
}
