import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';

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
ResultSections sectionResults(List<MealEntity> merged) {
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
  return (own: own, basic: basic, products: groups.values.toList());
}

/// The words of [meal]'s name in any order and case, so "Cooked Basmati
/// Rice" and "Basmati rice, cooked" are one product, whatever the brand. A
/// product without a name is alone.
Object productGroupKey(MealEntity meal) {
  final words =
      (meal.name ?? '')
          .toLowerCase()
          .split(RegExp(r'[^\p{L}\p{N}]+', unicode: true))
          .where((w) => w.isNotEmpty)
          .toList()
        ..sort();
  return words.isEmpty ? meal : words.join(' ');
}
