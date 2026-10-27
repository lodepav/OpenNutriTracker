import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/fork/food/local_food_data_source.dart';

/// The All list in sections (the search-duplicates canvas, layout C): the
/// user's own meals and recipes, the basic foods (USDA, BLS, the fork's
/// dishes), then the products, one group per name. On "cooked basmati
/// rice" fourteen brands of one product filled the list a row each, about
/// 20 kcal apart, above every USDA row.
typedef ResultSections = ({
  List<MealEntity> own,
  List<MealEntity> basic,
  List<List<MealEntity>> products,
});

/// [merged] (`mergeAndRankMeals`) split into [ResultSections], each in
/// [merged]'s order; a group stands where its first product stood.
///
/// The basic foods take [basicOrder]'s order instead, the Food search's
/// own: it knows a pickled or dry row from the plain one, where the text
/// score put "Tomato, green, pickled" first on "tomato" for its title.
/// A group whose name holds none of [query]'s words goes last: OFF finds
/// products by brand too, and "cashews, raw" listed a sleep formula by
/// the brand RAW.
ResultSections sectionResults(
  List<MealEntity> merged, {
  List<MealEntity> basicOrder = const [],
  String query = '',
}) {
  final own = <MealEntity>[];
  final basic = <MealEntity>[];
  final groups = <Object, List<MealEntity>>{};
  for (final meal in merged) {
    switch (meal.source) {
      case MealSourceEntity.custom || MealSourceEntity.recipe:
        own.add(meal);
      case MealSourceEntity.fdc:
        basic.add(meal);
      case MealSourceEntity.off || MealSourceEntity.unknown:
        groups.putIfAbsent(productGroupKey(meal), () => []).add(meal);
    }
  }
  final place = Map<MealEntity, int>.identity();
  for (var i = 0; i < basicOrder.length; i++) {
    place.putIfAbsent(basicOrder[i], () => i);
  }
  int at(MealEntity meal) => place[meal] ?? basicOrder.length;
  final sortedBasic = [for (final (i, meal) in basic.indexed) (i, meal)]
    ..sort((a, b) {
      final byPlace = at(a.$2).compareTo(at(b.$2));
      return byPlace != 0 ? byPlace : a.$1.compareTo(b.$1);
    });
  final asked = contentWords(query);
  bool named(List<MealEntity> group) =>
      asked.isEmpty ||
      nameWords(
        group.first.name,
      ).any((w) => asked.any((q) => wordsAgree(q, w)));
  final products = groups.values.toList();
  return (
    own: own,
    basic: [for (final (_, meal) in sortedBasic) meal],
    products: [...products.where(named), ...products.where((g) => !named(g))],
  );
}

/// The words of [meal]'s name in any order and case, a plural as its
/// singular, so "Cooked Basmati Rice" and "Basmati rice, cooked" are one
/// product, whatever the brand, and "Cashews" and "Cashew" one too. A
/// product without a name is alone.
Object productGroupKey(MealEntity meal) {
  final words = [for (final w in nameWords(meal.name)) _singular(w)]..sort();
  return words.isEmpty ? meal : words.join(' ');
}

String _singular(String word) {
  if (word.length <= 3 || !word.endsWith('s') || word.endsWith('ss')) {
    return word;
  }
  if (word.endsWith('ies')) return '${word.substring(0, word.length - 3)}y';
  if (word.endsWith('oes')) return word.substring(0, word.length - 2);
  return word.substring(0, word.length - 1);
}

/// [name]'s words, lower-cased.
List<String> nameWords(String? name) => (name ?? '')
    .toLowerCase()
    .split(RegExp(r'[^\p{L}\p{N}]+', unicode: true))
    .where((w) => w.isNotEmpty)
    .toList();

/// [query]'s words that name the food, without the ones that only describe
/// it ([describingWords]), each as the table spells it.
Set<String> contentWords(String query) => {
  for (final w in nameWords(query))
    if (!describingWords.contains(w)) spelling(w),
};

/// The energy range a group's row shows: [kcals] without the values far
/// from the middle one, when three or more leave a middle. One product
/// labelled cooked with dry rice's values stretched "Cooked Basmati Rice"
/// to 125–345, and a per-serving label "Pumpkin Seeds" to 95–643. Null
/// when there is nothing to show.
({double low, double high})? typicalRange(List<double> kcals) {
  if (kcals.isEmpty) return null;
  final sorted = [...kcals]..sort();
  if (sorted.length < 3) return (low: sorted.first, high: sorted.last);
  final middle = sorted[sorted.length ~/ 2];
  final kept = [
    for (final k in sorted)
      if (k >= middle / 1.5 && k <= middle * 1.5) k,
  ];
  return kept.isEmpty
      ? (low: middle, high: middle)
      : (low: kept.first, high: kept.last);
}
