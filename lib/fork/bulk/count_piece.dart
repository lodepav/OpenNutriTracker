// The portion a bare count means when the food's own serving is a measure
// (S198): a photo's 2 hard-boiled eggs logged 2 × "1 cup, chopped", 272 g
// and 422 kcal, beside the row's own "1 large" of 50 g.
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';

/// A serving or portion that weighs out food rather than counting it.
final _measure = RegExp(
  r'\b(cups?|tbsps?|tablespoons?|tsps?|teaspoons?|oz|ounces?|fl|lbs?|'
  r'pounds?|g|grams?|kg|ml|l|liters?|litres?|cubic|inch|inches|chopped|'
  r'diced|sliced|shredded|grated|mashed|pureed|cubed|cubes?)\b',
  caseSensitive: false,
);

/// A portion that holds many of the counted thing, or is not one at all.
final _notOne = RegExp(
  r'\b(packages?|packets?|containers?|bags?|bottles?|jars?|cans?|box(es)?|'
  r'cartons?|recipe|yield|servings?|portions?|meals?|NFS|crust|loaf|pie|'
  r'cake|pizza)\b',
  caseSensitive: false,
);

/// The words a piece's label may hold besides the food's own: its size,
/// or what any counted thing is.
const _pieceWords = {
  'small', 'medium', 'large', 'extra', 'jumbo', 'regular', 'whole', 'piece',
  'slice',
};

final _leadingOne = RegExp(r'^\s*1\s+');
final _parenthetical = RegExp(r'\([^)]*\)');
final _nonLetter = RegExp(r'[^\p{L}]+', unicode: true);

Set<String> _wordsOf(String text) => {
  for (final w in text.toLowerCase().split(_nonLetter))
    if (w.length > 2) w,
};

bool _sameWord(String a, String b) =>
    a == b ||
    (a.startsWith(b) && a.length - b.length <= 2) ||
    (b.startsWith(a) && b.length - a.length <= 2);

/// Which of [meal]'s portions is one of the counted thing, for a bare count
/// of [query]: null unless its serving weighs food out ("1 cup, chopped",
/// "3 oz") and a portion is one piece — a size alone ("1 large"), a piece
/// or slice, or one of the food by name ("1 waffle", "1 patty" of a patty).
/// A medium one when there are several sizes.
int? pieceForCount(MealEntity meal, String query) {
  final serving = meal.servingSize;
  if (meal.servingQuantity != null &&
      (serving == null || !_measure.hasMatch(serving))) {
    return null;
  }
  final named = {..._wordsOf(meal.name ?? ''), ..._wordsOf(query)};
  int? first;
  for (var i = 0; i < meal.portions.length; i++) {
    final label = meal.portions[i].englishLabel ?? meal.portions[i].label;
    if (!_leadingOne.hasMatch(label)) continue;
    final rest = label.replaceFirst(_leadingOne, '').replaceAll(
      _parenthetical,
      '',
    );
    if (_measure.hasMatch(rest) || _notOne.hasMatch(rest)) continue;
    final words = _wordsOf(rest);
    if (words.isEmpty) continue;
    final isPiece = words.every(
      (w) => _pieceWords.contains(w) || named.any((n) => _sameWord(w, n)),
    );
    if (!isPiece) continue;
    if (words.contains('medium')) return i;
    first ??= i;
  }
  return first;
}
