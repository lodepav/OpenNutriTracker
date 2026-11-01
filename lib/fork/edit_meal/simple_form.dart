import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';

/// Whether the per-serving form can save [meal] as it is. It writes a
/// serving and amount of 100 in g/ml, so a food with any other shape (from
/// the advanced form, a label or an import) would silently lose it.
bool simpleFormKeeps(MealEntity meal) {
  bool isHundred(String? text) =>
      text == null || text.isEmpty || double.tryParse(text) == 100;
  return (meal.servingQuantity == null || meal.servingQuantity == 100) &&
      isHundred(meal.mealQuantity) &&
      const {null, '', 'gml', 'g/ml'}.contains(meal.mealUnit);
}
