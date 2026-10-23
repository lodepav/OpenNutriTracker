import 'package:opennutritracker/core/domain/entity/body_weight_unit_entity.dart';
import 'package:opennutritracker/core/utils/calc/unit_calc.dart';

/// [kg] in the user's body weight unit, to a tenth.
String weightText(double kg, BodyWeightUnit unit) => switch (unit) {
  BodyWeightUnit.kg => '${kg.toStringAsFixed(1)} kg',
  BodyWeightUnit.lb => '${UnitCalc.kgToLbs(kg).toStringAsFixed(1)} lb',
  BodyWeightUnit.st => switch (UnitCalc.kgToStLb(kg, poundsDecimals: 1)) {
    (final st, final lb) => '$st st ${lb.toStringAsFixed(1)} lb',
  },
};

/// A change of [kg], signed, in kg or (for lb and st) pounds.
String weightChangeText(double kg, BodyWeightUnit unit) {
  final shown = unit == BodyWeightUnit.kg ? kg : kg * 2.20462;
  return '${shown > 0 ? '+' : ''}${shown.toStringAsFixed(1)} '
      '${unit == BodyWeightUnit.kg ? 'kg' : 'lb'}';
}
