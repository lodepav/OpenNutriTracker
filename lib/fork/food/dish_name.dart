import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';

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
