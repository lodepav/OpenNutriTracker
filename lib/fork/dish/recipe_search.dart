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
  final queryWords = tokenize(_fold(query));
  if (queryWords.isEmpty) return false;
  final nameWords = tokenize(_fold(name ?? ''));
  return queryWords.every((q) => nameWords.any((t) => wordsAgree(q, t)));
}

const _plain = {
  'ā': 'a',
  'č': 'c',
  'ē': 'e',
  'ģ': 'g',
  'ī': 'i',
  'ķ': 'k',
  'ļ': 'l',
  'ņ': 'n',
  'š': 's',
  'ū': 'u',
  'ž': 'z',
  'ä': 'a',
  'ö': 'o',
  'ü': 'u',
  'õ': 'o',
  'ą': 'a',
  'ę': 'e',
  'ė': 'e',
  'į': 'i',
  'ų': 'u',
  'ł': 'l',
};

/// Latvian and neighbouring letters to plain ones, so "sklandu rausi"
/// typed on an English keyboard finds "Sklandu rauši".
String _fold(String text) =>
    text.toLowerCase().split('').map((c) => _plain[c] ?? c).join();
