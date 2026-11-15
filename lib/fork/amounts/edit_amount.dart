import 'package:flutter/widgets.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/util/portion_unit.dart';
import 'package:opennutritracker/features/meal_detail/util/meal_quantity_converter.dart';
import 'package:opennutritracker/fork/amounts/amount_picker.dart';
import 'package:opennutritracker/fork/amounts/amount_units.dart';

/// The Edit item dialog's amount (S220), in the picker's unit, with the
/// logged amount counted in it.
typedef EditAmount = ({String unit, double quantity});

/// Where the Edit item dialog opens for [intake]: in the unit it was logged
/// in, the stored grams counted in it ("2 slice", not "64 g"). A portion no
/// longer on [meal] (the food with the user's own portions) opens as the
/// weight, the picker's weight chip.
EditAmount editOpening(
  IntakeEntity intake,
  MealEntity meal, {
  required bool imperial,
}) {
  var unit = intake.unit;
  var perOne = convertQuantityToBaseUnit(1, unit, meal);
  final gone =
      isPortionUnit(unit) &&
      meal.portions.isNotEmpty &&
      effectivePortionIndex(unit) >= meal.portions.length;
  if (gone || perOne <= 0) {
    unit = amountUnitOptions(
      meal,
      selected: '',
      imperial: imperial,
    ).firstWhere((o) => !o.isPortion).unit;
    perOne = convertQuantityToBaseUnit(1, unit, meal);
  }
  return (unit: unit, quantity: intake.amount / perOne);
}

/// [quantity] in [from] as the same weight in [to]: what a leftover is taken
/// from once another unit chip is chosen. Unrounded; [quantity] back when
/// [to] weighs nothing.
double quantityInUnit(
  double quantity,
  String from,
  String to,
  MealEntity meal,
) {
  final perOne = convertQuantityToBaseUnit(1, to, meal);
  if (perOne <= 0) return quantity;
  return convertQuantityToBaseUnit(quantity, from, meal) / perOne;
}

/// What OK stores for [quantity] in [unit]: grams or millilitres, as the
/// food's page logs them. A portion count left as it [opened] keeps the
/// logged [intake]'s amount, so a count rounded to show it moves nothing.
double editStoredAmount(
  double quantity,
  String unit,
  MealEntity meal,
  IntakeEntity intake,
  EditAmount opened,
) {
  if (unit == opened.unit &&
      isPortionUnit(unit) &&
      amountText(quantity) == amountText(opened.quantity)) {
    return intake.amount;
  }
  return convertQuantityToBaseUnit(quantity, unit, meal);
}

/// [unit] of [meal] as the picker's chips name it, for the leftover field.
String editUnitWord(
  BuildContext context,
  MealEntity meal,
  String unit, {
  required bool imperial,
}) => amountUnitWord(
  context,
  meal,
  amountUnitOptions(
    meal,
    selected: unit,
    imperial: imperial,
  ).firstWhere((o) => o.unit == unit),
);
