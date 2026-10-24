/// What the resolver takes off a row that is a variant the query did not
/// ask for. Phase 4's names showed table families whose plain member loses
/// a tie to a variant: "bacon" logged "Bacon, meatless", "schnitzel"
/// "Vegan schnitzel" and "meat dumplings" "Dumpling, no meat", each at the
/// same score as the plain row and picked by the shorter name. The
/// size moves such a row behind its siblings without dropping it under the
/// confidence floor when it is the only row.
const unaskedVariantPenalty = 0.2;

/// The words that make a row a different food from the one named: meat
/// left out, or a baby food. Not "unprepared": USDA's word for a food as
/// sold, the raw row a recipe ingredient wants ("Pork, cured, bacon,
/// unprepared").
final _variantWords = RegExp(
  r'\b(meatless|no meat|without meat|vegan|vegetarian|imitation|substitute|'
  r'baby food|toddler|infant)\b',
  caseSensitive: false,
);

/// A row that is only a food's skin: USDA names it as a part of its own
/// ("Potatoes, raw, skin", "Potatoes, boiled, cooked in skin, skin, with
/// salt"). "boiled potatoes" logged the boiled peel, and "potatoes" the raw
/// one. Not "skin eaten" or "skin removed", which say how the food was had.
final _skinOnly = RegExp(
  r',\s*skin\b(?!\s+(eaten|not eaten|removed))',
  caseSensitive: false,
);

/// [unaskedVariantPenalty] when [name] carries one of the variant words, or
/// is only a skin, and [query] does not say so, else 0.
double unaskedVariant(String? name, String query) {
  final asked = query.toLowerCase();
  if (_skinOnly.hasMatch(name ?? '') && !asked.contains('skin')) {
    return unaskedVariantPenalty;
  }
  final match = _variantWords.firstMatch(name ?? '');
  if (match == null) return 0;
  final word = match[0]!.toLowerCase();
  return asked.contains(word) ? 0 : unaskedVariantPenalty;
}
