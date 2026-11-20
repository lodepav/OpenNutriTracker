import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/presentation/bloc/bulk_add_bloc.dart';

/// [meal]'s name as a review row shows it: one of the fork's own dishes
/// without its trailing list of other names, "Plov, chicken (chicken pilaf,
/// pilau, palov)" as "Plov, chicken". The stored name keeps the list, which
/// search matches. Any other food's brackets are part of its name
/// ("Aubergine, fried without fat (pan)") and stay.
String shownDishName(MealEntity meal) {
  final name = meal.name ?? '';
  if (meal.backendSource != 'fork_dishes' || !name.endsWith(')')) return name;
  final open = name.indexOf(' (');
  return open > 0 ? name.substring(0, open) : name;
}

/// What a review row is called, on screen and in any message about it: the
/// matched food, or the words the user typed when nothing matched.
String shownRowTitle(BulkAddRow row) => switch (row.meal) {
  final meal? when meal.name != null => shownDishName(meal),
  _ => row.resolved.parsed.query,
};
