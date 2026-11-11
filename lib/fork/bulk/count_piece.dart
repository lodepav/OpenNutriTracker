// The portion a bare count means (S198, S213): a photo's 2 hard-boiled eggs
// logged 2 × "1 cup, chopped", 272 g and 422 kcal, beside the row's own
// "1 large" of 50 g.
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
/// or what any counted thing is. "1 fruit" of a peach, "1 link" of a
/// sausage, "1 bun-size or griller link" of a bratwurst (S213).
const _pieceWords = {
  ..._sizeWords,
  'whole',
  'piece',
  'slice',
  'any',
  'size',
  'individual',
  'single',
  'each',
  'item',
  'fruit',
  'link',
  'bun',
  'griller',
  'sandwich',
  'patty',
  'fillet',
  'steak',
  'chop',
  'cutlet',
  'breast',
  'thigh',
  'drumstick',
  'wing',
  'egg',
};

/// Words that size a piece away from the usual one.
const _sizeWords = {
  'small',
  'medium',
  'large',
  'extra',
  'jumbo',
  'regular',
  'mini',
  'miniature',
  'bite',
};

/// The middle of a size ladder, which a bare count means.
const _middleWords = {'medium', 'regular'};

/// A part of the food rather than one of it.
const _partWords = {'slice', 'piece'};

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
/// of [query]: a portion that is one piece — a size alone ("1 large"), a
/// piece or slice, or one of the food by name ("1 waffle", "1 patty" of a
/// patty, "1 sausage"). A medium or regular one of a size ladder, else the
/// first whole one with no size ("1 fruit" of an avocado before its "1
/// slice"), else the first with no size ("1 piece" of a chocolate candy
/// before its "1 miniature/bite size"; "1 hamburger bun" before "1
/// miniature/small hamburger bun"), else the first. Null when no portion is
/// one piece, and the count takes the food's serving.
///
/// Whatever the serving is (S213): a "1 serving" of 100 g made 2 pancakes
/// 200 g beside the row's own pancakes, and a steak's "1 serving" stood for
/// a steak only by chance. Before S213 only a serving that weighs food out
/// ("1 cup, chopped", "3 oz") gave way to a piece. A medium or regular one
/// is taken whatever the serving is ("3 bacon" is three medium slices), and
/// so is a whole one with no size; a slice, a piece or another sized one
/// still gives way only to such a serving, so "3 bread" beside an unnamed
/// serving keeps it rather than three slices.
int? pieceForCount(MealEntity meal, String query) {
  final serving = meal.servingSize;
  // A serving that weighs food out, or none: the only kind a slice or a
  // sized piece takes the place of, as before S213.
  final servingWeighs =
      meal.servingQuantity == null ||
      (serving != null && _measure.hasMatch(serving));
  final named = {..._wordsOf(meal.name ?? ''), ..._wordsOf(query)};
  int? first, plain, whole, sizedWhole;
  for (var i = 0; i < meal.portions.length; i++) {
    final label = meal.portions[i].englishLabel ?? meal.portions[i].label;
    if (!_leadingOne.hasMatch(label)) continue;
    final rest = label
        .replaceFirst(_leadingOne, '')
        .replaceAll(_parenthetical, '');
    if (_measure.hasMatch(rest) || _notOne.hasMatch(rest)) continue;
    final words = _wordsOf(rest);
    if (words.isEmpty) continue;
    final isPiece = words.every(
      (w) => _pieceWords.contains(w) || named.any((n) => _sameWord(w, n)),
    );
    if (!isPiece) continue;
    final part = words.any(_partWords.contains);
    // "1 slice, any size" of pork is no piece of it: the serving stands
    if (part && words.contains('any')) continue;
    if (words.any(_middleWords.contains)) return i;
    final sized = words.any(_sizeWords.contains);
    if (!part) {
      sized ? sizedWhole ??= i : whole ??= i;
    }
    if (!sized) plain ??= i;
    first ??= i;
  }
  if (whole != null) return whole;
  return servingWeighs ? plain ?? sizedWhole ?? first : null;
}
