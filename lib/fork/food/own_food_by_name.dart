/// The user's own food or recipe is a match for a meal read by the app
/// (S178) only by its name: the same words, in any order ("khachapuri,
/// adjarian" for a saved "Adjarian khachapuri"), as the photo prompt asks a
/// saved dish to be named (S172) or as the user typed it. A partial or word
/// match, as the Food tab finds one, put a saved "Chicken with rice and
/// peas" ahead of the generic chicken and rice the meal named.
bool namesOwnFood(String name, String query) {
  final words = _words(name);
  final asked = _words(query);
  return words.isNotEmpty &&
      words.length == asked.length &&
      words.containsAll(asked);
}

Set<String> _words(String text) => text
    .toLowerCase()
    .split(RegExp(r'[^\p{L}\p{N}]+', unicode: true))
    .where((w) => w.isNotEmpty)
    .toSet();
