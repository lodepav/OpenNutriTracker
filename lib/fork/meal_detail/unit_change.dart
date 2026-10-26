import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/util/portion_unit.dart';
import 'package:opennutritracker/features/meal_detail/presentation/bloc/meal_detail_bloc.dart';
import 'package:opennutritracker/features/meal_detail/util/meal_quantity_converter.dart';

/// The amount in [toUnit] that weighs what [text] in [fromUnit] does, so a
/// unit change keeps the food's amount: 180 g becomes 1 serving, not 180
/// servings (S164). Grams and millilitres whole, other units to a tenth;
/// null when [text] is no amount.
String? amountInUnit(
  String text,
  String fromUnit,
  String toUnit,
  MealEntity meal,
) {
  final quantity = double.tryParse(text.trim().replaceAll(',', '.'));
  if (quantity == null || quantity <= 0) return null;
  final base = convertQuantityToBaseUnit(quantity, fromUnit, meal);
  final perOne = convertQuantityToBaseUnit(1, toUnit, meal);
  if (perOne <= 0) return null;
  final value = base / perOne;
  final whole = {
    UnitDropdownItem.g.toString(),
    UnitDropdownItem.ml.toString(),
    UnitDropdownItem.gml.toString(),
  }.contains(storedUnit(toUnit));
  final rounded = whole ? value.roundToDouble() : (value * 10).round() / 10;
  if (rounded <= 0) return null;
  return rounded == rounded.roundToDouble()
      ? rounded.toInt().toString()
      : rounded.toString();
}
