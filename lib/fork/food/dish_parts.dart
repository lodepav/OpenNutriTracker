import 'package:opennutritracker/features/add_meal/domain/usecase/resolve_parsed_meals_usecase.dart';
import 'package:opennutritracker/fork/food/local_food_data_source.dart';
import 'package:opennutritracker/fork/food/served_with.dart';

/// [items] without a food the dish row beside it already holds (S206).
///
/// A model reading a plate lists a dish and then what it sees of it:
/// khachapuri's row is "cheese bread with egg", and the read added a fried
/// egg and cheese besides, about 170 kcal twice; a spaghetti bolognese row
/// came with its spaghetti, a stuffed pepper with a bell pepper. Measured
/// over 1,255 eval reads (2026-11-09): every food so listed was in the
/// dish's own name. A dish row is one whose name, brackets and how it was
/// made aside, has three words or more, or an unmatched one whose query
/// has; the food is the one its query names ([headNoun]).
/// Two rows of one food ("fried egg" and "egg") leave each other alone.
List<ResolvedMealItem> withoutDishParts(List<ResolvedMealItem> items) {
  final dishes = [
    for (final item in items)
      // A dish nothing matched is broken down (D9) into the foods it holds,
      // so its query is the dish: a held-out photo's "buckwheat with meat
      // and mushrooms" came with beef stew meat and mushrooms besides, 889
      // kcal against 285.
      if (item.selected?.name ?? item.parsed.query case final name)
        if (_whatItHolds(name) case final held when nameWords(held).length >= 3)
          (item, held),
  ];
  if (dishes.isEmpty) return items;
  bool isPart(ResolvedMealItem item) {
    final food = headNoun(item.parsed.query, oneWord: true);
    if (food == null || item.selected == null) return false;
    return dishes.any(
      (dish) =>
          !identical(dish.$1, item) &&
          holdsWord(dish.$2, food) &&
          !_sameFood(dish.$1.parsed.query, food),
    );
  }

  return [
    for (final item in items)
      if (!isPart(item)) item,
  ];
}

/// [name] without its brackets and the parts that say how it was made
/// ("made with milk", "whole milk added"): mashed potatoes or oatmeal made
/// with milk do not hold the glass of milk beside them.
String _whatItHolds(String name) => [
  for (final part in name.split('(').first.split(','))
    if (!_howMade.hasMatch(part.trim())) part,
].join(',');

final _howMade = RegExp(r'^made with\b|\badded$', caseSensitive: false);

/// Whether [query] names [food] as its own food: "fried egg" is an egg.
bool _sameFood(String query, String food) {
  final own = headNoun(query, oneWord: true);
  return own != null && wordsAgree(food, own);
}
