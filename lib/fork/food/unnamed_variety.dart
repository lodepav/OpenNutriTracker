/// Words a portion label sizes or shapes a thing with, which say how much,
/// not which kind: "1 small", "1 thick slice", "1 bite size cookie", "1
/// large single serving bag".
const _sizeWords = {
  'small',
  'medium',
  'large',
  'regular',
  'thin',
  'thick',
  'extra',
  'mini',
  'miniature',
  'jumbo',
  'bite',
  'size',
  'whole',
  'single',
  'serving',
  'very',
  'personal',
};

final _parenthetical = RegExp(r'\([^)]*\)');
final _nonLetter = RegExp(r'[^\p{L}]+', unicode: true);

/// Whether [label] names a kind of the thing the text's [tokens] counted
/// that the text did not name (S197): a word right before a word the text
/// matched, which is neither matched nor a size, as "grape" in "1 grape
/// tomato" for "2 tomatoes" and "baby" in "1 baby potato" for "4 roast
/// potatoes". A word after it ("1 cup, chopped") says how it was cut, and
/// a row of it still means a cup. The words are English, so [label] is the
/// English one; [matches] is the matcher's own word test.
bool namesUnaskedKind(
  String label,
  Set<String> tokens,
  bool Function(String token, String term) matches,
) {
  bool matched(String w) => tokens.any((t) => matches(t, w));
  // A comma ends a phrase: "1 piece, large pizza" is a piece of a large
  // pizza, and "1 cup, cooked" a cup.
  for (final phrase in label.replaceAll(_parenthetical, ' ').split(',')) {
    final words = phrase
        .toLowerCase()
        .split(_nonLetter)
        .where((w) => w.length >= 3)
        .toList();
    for (var i = 1; i < words.length; i++) {
      final before = words[i - 1];
      if (matched(words[i]) &&
          !matched(before) &&
          !_sizeWords.contains(before)) {
        return true;
      }
    }
  }
  return false;
}
