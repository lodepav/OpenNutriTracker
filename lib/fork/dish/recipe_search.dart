import 'package:opennutritracker/features/add_meal/util/soft_text_score.dart';
import 'package:opennutritracker/fork/food/local_food_data_source.dart';

/// Whether every word of [query] is a word of [name], up to an ending, by
/// the food table's own rule (`wordsAgree`). Phase 1c.5: the model names a
/// saved dish its own way ("khachapuri, adjarian" for "Adjarian
/// khachapuri", "pelmeni" for "Pelmenis"), which upstream's whole-string
/// match misses.
///
/// Used beside upstream's match, never instead of it, so a half-typed word
/// ("khach") still finds the recipe.
bool nameHasQueryWords(String? name, String query) {
  final queryWords = tokenize(query);
  if (queryWords.isEmpty) return false;
  final nameWords = tokenize(name);
  return queryWords.every((q) => nameWords.any((t) => wordsAgree(q, t)));
}
