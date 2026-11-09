import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/fork/food/local_food_data_source.dart';
import 'package:opennutritracker/fork/food/portion_words.dart';

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

/// Words that describe a food or its portion without naming it, which a
/// product's name need not hold.
const _describes = {
  'grated',
  'shredded',
  'diced',
  'toasted',
  'creamy',
  'crispy',
  'homemade',
  'hot',
  'cold',
  'warm',
  'small',
  'large',
  'whole',
  'plain',
  'mixed',
  'thick',
  'thin',
  'bowl',
  'plate',
  'cup',
  'glass',
  'serving',
  'portion',
  'spoon',
  'handful',
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
  return sides.isNotEmpty &&
      holdsWord(sides, head) &&
      !_holdsAsFood(food, head);
}

/// Whether [food], a row's name before its "with", names [word] as its
/// food: outside its brackets, or in one of the other names they hold
/// before that name's own joint. "melted cheese" found "Pork chop with
/// cheese, baked (karbonāde ar sieru, pork cutlet with melted cheese)" and
/// logged 534 kcal on a photo's French onion soup.
bool _holdsAsFood(String food, String word) {
  final open = food.indexOf('(');
  if (open < 0) return holdsWord(food, word);
  if (holdsWord(food.substring(0, open), word)) return true;
  return food
      .substring(open + 1)
      .replaceAll(')', '')
      .split(',')
      .any(
        (alias) => nameWords(alias)
            .takeWhile((w) => !_joints.contains(w))
            .any((w) => wordsAgree(word, spelling(w))),
      );
}

/// [ranked] without the Open Food Facts products that are not the food a
/// model's [query] names (S205): their name lacks its food ([headNoun]).
/// A model names foods in English: a photo's "baked casserole with cheese
/// and tomato" logged a "Black beans" product, and a typed "griķi ar
/// sēnēm" an Oatly "Creamy oat fraiche", 468 kcal, on "cream". Table rows
/// always hold the words the search matched, so only products are read.
List<MealEntity> withoutUnrelatedProducts(
  List<MealEntity> ranked,
  String query,
) {
  final food = headNoun(query, oneWord: true);
  if (food == null) return ranked;
  // Half the food's other words too, rounded up, not only its last: a
  // photo's "cabbage soup with carrots and meat" logged a "Carrot &
  // Coriander Soup", 123 kcal against 626. Every word was too many: "beef
  // ragu" is a "tomato beef ragu", "Vanilla curd snack" a glazed one.
  final others = [
    for (final w in nameWords(
      (withoutShapeWords(query) ?? query).split(',').first,
    ).takeWhile((w) => !_joints.contains(w)))
      if (!_howMade.contains(w) && !_describes.contains(w) && w.length > 2)
        if (!wordsAgree(food, spelling(w))) spelling(w),
  ];
  final needed = (others.length + 1) ~/ 2;
  return [
    for (final meal in ranked)
      if (meal.source != MealSourceEntity.off ||
          (holdsWord(meal.name ?? '', food) &&
              others
                      .where(
                        (w) =>
                            holdsWord('${meal.name} ${meal.brands ?? ''}', w),
                      )
                      .length >=
                  needed))
        meal,
  ];
}

/// The words of what a dish [query] names after its first "with", "and"
/// or "in": "sausage" in "braised cabbage with sausage".
List<String> _sides(String query) {
  final words = nameWords(query.split(',').first);
  final at = words.indexWhere((w) => w == 'with' || w == 'and' || w == 'in');
  if (at < 1) return const [];
  return [
    for (final w in words.skip(at + 1))
      if (!_joints.contains(w) && !_howMade.contains(w) && w.length > 2)
        spelling(w),
  ];
}

/// [ranked] without the rows that are only part of the dish a model's
/// [query] names (S205): none of the words after its "with" are in them.
/// "braised cabbage with sausage" logged M&S's "Braised Red Cabbage", 155
/// kcal for a plate. With nothing left the dish is broken down (D9), into
/// the cabbage and the sausage both.
List<MealEntity> withoutMissingSides(List<MealEntity> ranked, String query) {
  final sides = _sides(query);
  if (sides.isEmpty) return ranked;
  return [
    for (final meal in ranked)
      if (sides.any((side) => holdsWord(meal.name ?? '', side))) meal,
  ];
}
