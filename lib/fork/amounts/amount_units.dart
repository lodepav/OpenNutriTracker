import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/util/portion_unit.dart';
import 'package:opennutritracker/features/meal_detail/presentation/bloc/meal_detail_bloc.dart';
import 'package:opennutritracker/features/meal_detail/util/meal_quantity_converter.dart';
import 'package:opennutritracker/fork/amounts/own_portions.dart';

/// One chip of the amount picker (S195): a unit the amount can be in.
class AmountUnitOption {
  /// The value the sheet and the bloc take: `g`, `serving`, `serving#2`.
  final String unit;

  /// The food's own words for a portion, as published ("1 slice (32 g)");
  /// null for a weight or volume.
  final String? portionLabel;

  /// What one weighs, in grams or millilitres; null for a weight unit.
  final double? grams;

  /// The user's own portion.
  final bool own;

  const AmountUnitOption(
    this.unit, {
    this.portionLabel,
    this.grams,
    this.own = false,
  });

  bool get isPortion => grams != null;
}

final _g = UnitDropdownItem.g.toString();
final _ml = UnitDropdownItem.ml.toString();
final _gml = UnitDropdownItem.gml.toString();
final _oz = UnitDropdownItem.oz.toString();
final _flOz = UnitDropdownItem.flOz.toString();
final _serving = UnitDropdownItem.serving.toString();

bool isWeightUnit(String unit) => {_g, _ml, _gml, _oz, _flOz}.contains(unit);

/// The units [meal] can be logged in, portions first: each of its
/// portions (the user's own last), or its one serving; then one weight
/// for the profile, grams or ounces, or a volume for a drink, never both
/// systems. [selected] is always among them, so a unit the page opened at
/// (an ounce on a metric profile) still shows as chosen.
List<AmountUnitOption> amountUnitOptions(
  MealEntity meal, {
  required String selected,
  required bool imperial,
}) {
  final options = <AmountUnitOption>[
    if (meal.portions.isNotEmpty)
      for (final (i, p) in meal.portions.indexed)
        AmountUnitOption(
          portionUnit(i),
          portionLabel: p.label,
          grams: p.gramWeight,
          own: p is OwnPortionEntity,
        )
    else if (meal.scalableServingQuantity case final serving?)
      AmountUnitOption(
        _serving,
        portionLabel: meal.servingSize,
        grams: serving,
      ),
    if (meal.isLiquid)
      AmountUnitOption(imperial ? _flOz : _ml)
    else if (meal.isSolid)
      AmountUnitOption(imperial ? _oz : _g)
    else ...[
      AmountUnitOption(_gml),
      if (imperial) AmountUnitOption(_oz),
    ],
  ];
  if (selected.isNotEmpty && !options.any((o) => o.unit == selected)) {
    options.add(AmountUnitOption(selected));
  }
  return options;
}

/// How far the − and + move [quantity] in [unit]: one portion (a half
/// below one), 10 g or ml, one ounce.
double amountStep(String unit, double quantity) {
  if (isPortionUnit(unit)) return quantity < 1 ? 0.5 : 1;
  if (unit == _oz || unit == _flOz) return 1;
  return 10;
}

/// [quantity] one [step] up or down, onto the step's grid: 64 g goes to
/// 70 or 60, not 74 or 54. Never below one step.
double steppedAmount(double quantity, double step, {required bool up}) {
  const eps = 1e-9;
  final next = up
      ? ((quantity + eps) / step).floorToDouble() * step + step
      : ((quantity - eps) / step).ceilToDouble() * step - step;
  return next < step ? step : double.parse(next.toStringAsFixed(2));
}

/// A portion that [quantity] in a weight [unit] is a whole or half number
/// of, within 5%: 64 g of bread is 2 slices of 32 g. The user's own first,
/// then the food's; null when none fits, or [unit] is not a weight.
({AmountUnitOption option, double count})? portionThatFits(
  MealEntity meal,
  List<AmountUnitOption> options,
  String unit,
  double quantity,
) {
  if (!isWeightUnit(unit) || quantity <= 0) return null;
  final grams = convertQuantityToBaseUnit(quantity, unit, meal);
  final portions = [
    ...options.where((o) => o.isPortion && o.own),
    ...options.where((o) => o.isPortion && !o.own),
  ];
  for (final option in portions) {
    final exact = grams / option.grams!;
    final count = (exact * 2).roundToDouble() / 2;
    if (count < 1 || count > 20) continue;
    if ((exact - count).abs() / count <= 0.05) {
      return (option: option, count: count);
    }
  }
  return null;
}

/// [value] as the amount field shows it: whole, or to two decimals.
String amountText(double value) {
  final rounded = double.parse(value.toStringAsFixed(2));
  return rounded == rounded.roundToDouble()
      ? rounded.toInt().toString()
      : rounded.toString();
}
