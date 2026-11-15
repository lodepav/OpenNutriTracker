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
/// in, the stored grams counted in it ("2 slice", not "64 g"). A stored
/// food keeps its serving but not its database portions, and the unit is
/// only a place in the list the food's page showed, so a portion opens as
/// its count only when [meal] (the food with the user's own portions) has
/// one there and the grams are whole or half ones of it; else as the
/// weight, the picker's weight chip.
EditAmount editOpening(
  IntakeEntity intake,
  MealEntity meal, {
  required bool imperial,
}) {
  final unit = intake.unit;
  if (!isPortionUnit(unit)) {
    return (
      unit: unit,
      quantity: intake.amount / convertQuantityToBaseUnit(1, unit, meal),
    );
  }
  final index = effectivePortionIndex(unit);
  final double? perOne = meal.portions.isNotEmpty
      ? (index < meal.portions.length ? meal.portions[index].gramWeight : null)
      : (index == 0 ? meal.scalableServingQuantity : null);
  if (perOne != null && perOne > 0) {
    final halves = intake.amount / perOne * 2;
    if (halves.round() >= 1 && (halves - halves.round()).abs() < 0.02) {
      return (unit: unit, quantity: intake.amount / perOne);
    }
  }
  final weight = amountUnitOptions(
    meal,
    selected: '',
    imperial: imperial,
  ).firstWhere((o) => !o.isPortion).unit;
  return (
    unit: weight,
    quantity: intake.amount / convertQuantityToBaseUnit(1, weight, meal),
  );
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

/// Whether [quantity] in [unit] is the amount as it [opened]: OK then
/// stores the entry's amount and unit as they were logged.
bool editUnchanged(double quantity, String unit, EditAmount opened) =>
    unit == opened.unit && amountText(quantity) == amountText(opened.quantity);

/// What OK stores for [quantity] in [unit]: grams or millilitres, as the
/// food's page logs them. An amount left as it [opened] keeps the logged
/// [intake]'s, so a number rounded to show it moves nothing.
double editStoredAmount(
  double quantity,
  String unit,
  MealEntity meal,
  IntakeEntity intake,
  EditAmount opened,
) {
  if (editUnchanged(quantity, unit, opened)) {
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
