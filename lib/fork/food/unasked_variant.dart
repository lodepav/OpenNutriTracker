/// What the resolver takes off a row that is a variant the query did not
/// ask for. Phase 4's names showed table families whose plain member loses
/// a tie to a variant: "bacon" logged "Bacon, meatless", "schnitzel"
/// "Vegan schnitzel" and "meat dumplings" "Dumpling, no meat", each at the
/// same score as the plain row and picked by the shorter name. The
/// size moves such a row behind its siblings without dropping it under the
/// confidence floor when it is the only row (1.0 less this and the
/// no-portion 0.15 is 0.55, over 0.45). It is more than a plural costs, so
/// a singular variant trails a plural plain row: "tomato" scores "Tomato,
/// green, pickled" 1.0 and "Tomatoes, raw" 0.75, and 0.2 kept the pickle.
const unaskedVariantPenalty = 0.3;

/// The words that make a row a different food from the one named: meat
/// left out, a baby food, or Canadian bacon (a loin: "bacon, cooked,
/// pan-fried" logged it at a third of bacon's energy). Not "unprepared":
/// USDA's word for a food as sold, the raw row a recipe ingredient wants
/// ("Pork, cured, bacon, unprepared").
final _variantWords = RegExp(
  r'\b(meatless|no meat|without meat|vegan|vegetarian|imitation|substitute|'
  r'baby food|toddler|infant|canadian)\b',
  caseSensitive: false,
);

/// A lighter make of the food: a wrap's caesar dressing logged "Salad
/// dressing, caesar, fat-free" at a quarter of the regular one's energy,
/// and a burger's "beef patty" the 97% lean one. Any wording of lighter in
/// the query asks for one.
final _lighter = RegExp(
  r'\b(fat[- ]free|non-?fat|(reduced|low)[- ]?(fat|calorie|sodium)|lowfat|'
  r'9\d% lean)',
  caseSensitive: false,
);
final _asksLighter = RegExp(
  r'\b(fat[- ]free|non-?fat|reduced|low|lowfat|lean|light|lite|skim|diet)',
  caseSensitive: false,
);

/// A dry mix as sold, not a dish made from one: "tortilla, wheat flour"
/// logged the tortilla mix. "Potato, scalloped, from dry mix" is the dish.
final _mix = RegExp(r'(?<!from |from dry )\bmix\b', caseSensitive: false);

/// A query naming the skin to say it is left off: "potatoes, boiled, cooked
/// without skin" logged the boiled peel.
final _asksSkin = RegExp(
  r'(?<!without |no )\bskin(?!less)',
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

/// A food kept in brine or vinegar, a different taste and often salt:
/// "tomato" logged "Tomato, green, pickled". Asked for by "pickle" too.
final _pickled = RegExp(r'\bpickled\b', caseSensitive: false);

/// Turkey standing in for the usual meat, named after the title: "bacon"
/// logged "Bacon, turkey, unprepared". A row titled turkey is turkey.
final _turkeyAfterTitle = RegExp(r',.*\bturkey\b', caseSensitive: false);

/// A row named for what it lacks: "pepperoni pizza" logged "Pizza, with
/// meat other than pepperoni", which holds the query's every word.
final _lacks = RegExp(
  r'\b(?:other than|without|no)\s+(\w+)',
  caseSensitive: false,
);

/// [unaskedVariantPenalty] when [name] carries one of the variant words, or
/// is only a skin, pickled, lighter or made with turkey, and [query] does
/// not say so, or lacks a food [query] names; else 0.
double unaskedVariant(String? name, String query) {
  final asked = query.toLowerCase();
  final row = name ?? '';
  if (_skinOnly.hasMatch(row) && !_asksSkin.hasMatch(asked)) {
    return unaskedVariantPenalty;
  }
  if (_pickled.hasMatch(row) && !asked.contains('pickl')) {
    return unaskedVariantPenalty;
  }
  if (_lighter.hasMatch(row) && !_asksLighter.hasMatch(asked)) {
    return unaskedVariantPenalty;
  }
  if (_mix.hasMatch(row) && !asked.contains('mix')) {
    return unaskedVariantPenalty;
  }
  if (_turkeyAfterTitle.hasMatch(row) && !asked.contains('turkey')) {
    return unaskedVariantPenalty;
  }
  for (final lack in _lacks.allMatches(row)) {
    if (RegExp('\\b${lack[1]!.toLowerCase()}').hasMatch(asked)) {
      return unaskedVariantPenalty;
    }
  }
  final match = _variantWords.firstMatch(row);
  if (match == null) return 0;
  final word = match[0]!.toLowerCase();
  return asked.contains(word) ? 0 : unaskedVariantPenalty;
}
