import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';

/// [merged] (`mergeAndRankMeals`) with its first three reference rows —
/// USDA, BLS, the fork's dishes — no lower than second, fourth and sixth
/// among the remote rows. The text score favours a product named in the
/// query's own words: on "cooked basmati rice" twenty brands of "Cooked
/// Basmati Rice" scored above "Rice, white, long-grain, ..., cooked",
/// which no word basmati names, and the first reference row was
/// twenty-first. The user's own meals and recipes stay above.
List<MealEntity> referenceUp(List<MealEntity> merged) {
  final start = merged.indexWhere(
    (m) =>
        m.source != MealSourceEntity.custom &&
        m.source != MealSourceEntity.recipe,
  );
  if (start < 0) return merged;
  final remote = merged.sublist(start);
  final at = <int>[
    for (var i = 0; i < remote.length; i++)
      if (remote[i].source == MealSourceEntity.fdc) i,
  ].take(3).toList();
  final lifted = [
    for (var i = 0; i < remote.length; i++)
      if (!at.contains(i)) remote[i],
  ];
  // Both the place a row had and the place it is due rise with k, so each
  // insert lands after the one before it.
  for (var k = 0; k < at.length; k++) {
    final place = at[k] < 2 * k + 1 ? at[k] : 2 * k + 1;
    lifted.insert(place, remote[at[k]]);
  }
  return [...merged.sublist(0, start), ...lifted];
}
