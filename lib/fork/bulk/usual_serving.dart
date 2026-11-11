// An amount far from the food's usual serving, marked on a photo's review
// (D47): the read sizes foods 20-60% off, and an amount three times or a
// third of a serving is more often a misread than a meal.
import 'package:opennutritracker/features/add_meal/presentation/bloc/bulk_add_bloc.dart';
import 'package:opennutritracker/features/add_meal/util/portion_unit.dart';
import 'package:opennutritracker/features/meal_detail/presentation/bloc/meal_detail_bloc.dart';
import 'package:opennutritracker/features/meal_detail/util/meal_quantity_converter.dart';
import 'package:opennutritracker/fork/amounts/amount_units.dart';
import 'package:opennutritracker/fork/bulk/amount_question.dart';
import 'package:opennutritracker/fork/bulk/meal_scale.dart';

/// Above this many servings, or below one over it, an amount is unusual.
const usualServingBound = 3.0;

final _g = UnitDropdownItem.g.toString();
final _ml = UnitDropdownItem.ml.toString();
final _gml = UnitDropdownItem.gml.toString();

/// The usual serving offered on [row], as a chip that sets it ("150 g", "1
/// egg"); null when its amount is within a third and three times the food's
/// serving, or there is nothing to compare: no serving in the table, no
/// usable amount, or a row no size may change ([isScalableRow]: a weighed
/// plate, a count the note states, a row left out or at the app's default).
///
/// Compared in grams or millilitres. A counted row is never unusual for
/// its number of pieces alone: a whole count is what was seen, so it is
/// unusual only above three pieces (and three servings), or below one
/// piece (and a third of a serving).
AmountChoice? usualServingFor(
  BulkAddRow row, {
  String? note,
  required bool imperial,
}) {
  final meal = row.meal;
  if (meal == null || !isScalableRow(row, note: note)) return null;
  final serving = meal.scalableServingQuantity;
  final amount = double.tryParse(row.amountText.trim().replaceAll(',', '.'));
  if (serving == null || serving <= 0 || amount == null || amount <= 0) {
    return null;
  }
  final unit = row.effectiveUnit;
  final ratio = convertQuantityToBaseUnit(amount, unit, meal) / serving;
  final counted = isPortionUnit(unit);
  final high = ratio > usualServingBound && (!counted || amount > 3);
  final low = ratio < 1 / usualServingBound && (!counted || amount < 1);
  if (!high && !low) return null;

  // a counted row is offered pieces, when a piece weighs anything
  if (counted) {
    final piece = convertQuantityToBaseUnit(1, unit, meal);
    final word = pieceWordIn(meal, unit);
    if (word != null && piece > 1) {
      final pieces = serving / piece;
      final count = pieces < 0.75 ? 0.5 : (pieces * 2).roundToDouble() / 2;
      return countChoiceOf(count, word, unit);
    }
  }

  // else a weight, in the unit the row is shown in
  final allowed = row.allowedUnits;
  final String weight;
  if (isWeightUnit(unit)) {
    weight = unit;
  } else {
    weight = meal.isLiquid && allowed.contains(_ml)
        ? _ml
        : meal.isSolid && allowed.contains(_g)
        ? _g
        : _gml;
  }
  final shown = imperial
      ? imperialWeightOf(meal, allowed, weight) ?? weight
      : weight;
  final perOne = convertQuantityToBaseUnit(1, shown, meal);
  if (perOne <= 0) return null;
  final value = friendlyAmount(serving / perOne, shown);
  if (value <= 0) return null;
  return weightChoiceOf(value, shown);
}
