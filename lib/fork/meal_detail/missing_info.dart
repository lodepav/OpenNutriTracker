import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';

/// What [meal] lacks per 100 g to be logged, energy named in [energyUnit]:
/// the food sheet needs energy and all three macros. Empty when it can be.
List<String> missingForLog(MealEntity meal, String energyUnit) {
  final n = meal.nutriments;
  return [
    if (n.energyKcal100 == null) 'energy ($energyUnit)',
    if (n.carbohydrates100 == null) 'carbs',
    if (n.fat100 == null) 'fat',
    if (n.proteins100 == null) 'protein',
  ];
}

/// The food sheet's reason it can't log, naming what is missing.
String missingForLogText(List<String> missing) =>
    "Can't log this food: it has no ${_list(missing)} per 100 g. "
    'Edit it to add them.';

String _list(List<String> items) => items.length < 2
    ? items.join()
    : '${items.sublist(0, items.length - 1).join(', ')} or ${items.last}';
