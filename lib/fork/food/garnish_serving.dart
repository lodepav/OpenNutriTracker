/// The most a garnish starts at when no amount was stated (S98): a photo's
/// parsley, dill and green onion came in at the 100 g default, grated
/// parmesan at USDA's 100 g cup, 420 kcal, where a plate holds a spoon, and
/// a sauce's garlic at USDA's 136 g cup, 203 kcal, where it holds a clove
/// or two.
const herbServingGrams = 5.0;

/// The same for grated cheese: about two tablespoons.
const gratedCheeseServingGrams = 10.0;

const _gramsPerOunce = 28.349523125;

/// A herb by its own name, or a row that names it first: "Dill weed, fresh",
/// "Parsley, raw", "Coriander (cilantro) leaves, raw", "Green Onion",
/// "Garlic, raw"; never a food that holds one ("Pickles, dill", "Lemon dill
/// sauce", "Garlic bread").
final _herb = RegExp(
  r'^(fresh\s+|chopped\s+)*(dill|parsley|cilantro|coriander|chives|basil|'
  r'mint|spearmint|green onions?|spring onions?|scallions?|garlic)'
  r'(\s+(weed|leaves|sprigs|cloves?))?$',
  caseSensitive: false,
);

/// "Onions, green, raw" and "Onions, spring or scallions (includes tops and
/// bulb), raw": the table names a green onion by the onion.
final _greenOnionRow = RegExp(
  r'^onions?, (green|spring)\b',
  caseSensitive: false,
);

final _grated = RegExp(r'\b(grated|shredded)\b', caseSensitive: false);
final _cheese = RegExp(
  r'\b(cheese|parmesan|parmigiano|pecorino|grana padano)\b',
  caseSensitive: false,
);

/// A food that comes with the garnish is the food ("Pasta, with grated
/// cheese").
final _comesWith = RegExp(r'\b(with|in)\b[^,]*', caseSensitive: false);
final _parenthetical = RegExp(r'\([^)]*\)');

/// What a garnish named [name] starts at, at most, in grams; null for any
/// other food.
double? garnishGrams(String? name) {
  if (name == null) return null;
  final plain = name.replaceAll(_parenthetical, ' ');
  final head = plain.split(',').first.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (_herb.hasMatch(head) || _greenOnionRow.hasMatch(name)) {
    return herbServingGrams;
  }
  final own = plain.replaceAll(_comesWith, '');
  if (_grated.hasMatch(own) && _cheese.hasMatch(own)) {
    return gratedCheeseServingGrams;
  }
  return null;
}

/// [garnishGrams] in ounces, for an imperial profile.
double? garnishOunces(String? name) => switch (garnishGrams(name)) {
  final grams? => grams / _gramsPerOunce,
  null => null,
};
