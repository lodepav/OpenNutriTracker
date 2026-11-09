import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/fork/food/local_food_data_source.dart';

/// The words that join a dish's main food to what comes with it.
const _joints = {'with', 'and', 'in', 'ar', 'un', 'su', 'mit', 'z', 'w'};

/// Words that say how a food was made: the food in "carrots, cooked" is the
/// carrots.
const _howMade = {
  'cooked',
  'boiled',
  'steamed',
  'fried',
  'baked',
  'grilled',
  'roasted',
  'raw',
  'stewed',
  'braised',
  'sliced',
  'chopped',
  'melted',
  'fresh',
};

/// The food [query] names: the last word before its first comma or joint
/// that is not how it was made ("melted butter" → butter, "pork with
/// vegetables" → pork). Null for a one-word query, which has no other word
/// to have matched on, unless [oneWord].
String? headNoun(String query, {bool oneWord = false}) {
  final words = nameWords(query.split(',').first);
  if (words.length < (oneWord ? 1 : 2)) return null;
  final head = words.takeWhile((w) => !_joints.contains(w)).toList();
  final food = head.where((w) => !_howMade.contains(w));
  return food.isEmpty ? null : spelling(food.last);
}

/// [name] split at its first " with ": the food, then what is served with
/// it. The food keeps the name's brackets, where a fork dish keeps its
/// other names.
(String, String) _foodAndSides(String name) {
  final at = RegExp(r',?\s+with\s+', caseSensitive: false).firstMatch(name);
  if (at == null) return (name, '');
  final rest = name.substring(at.end);
  final bracket = rest.indexOf('(');
  return (
    name.substring(0, at.start) + (bracket < 0 ? '' : rest.substring(bracket)),
    bracket < 0 ? rest : rest.substring(0, bracket),
  );
}

/// Whether a word of [text] is [word] up to its ending.
bool holdsWord(String text, String word) =>
    nameWords(text).any((t) => wordsAgree(word, spelling(t)));

/// [ranked] without the rows that are another food served with the one
/// [query] names (S205): the food is only in the row's "with" part.
/// "melted butter" found "Brussels sprouts, stewed, with melted butter",
/// "meat sauce" found "Meatballs, ..., with sauce", each matching every
/// word the name has. Such a row is never the food asked for, so it is
/// left out; with nothing left, the item is unresolved and a model's read
/// breaks it down (D9) instead of logging the other food.
List<MealEntity> withoutServedWith(List<MealEntity> ranked, String query) {
  final head = headNoun(query);
  if (head == null) return ranked;
  return [
    for (final meal in ranked)
      if (!_onlyServedWith(meal.name ?? '', head)) meal,
  ];
}

bool _onlyServedWith(String name, String head) {
  final (food, sides) = _foodAndSides(name);
  return sides.isNotEmpty && holdsWord(sides, head) && !holdsWord(food, head);
}
