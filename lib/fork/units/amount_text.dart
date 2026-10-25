import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/utils/calc/unit_calc.dart';

/// The unit [intake]'s amounts are shown in, and the factor from its stored
/// amount, as the entry dialog shows them: the food's unit, ounces for grams
/// in imperial units, and "g" for upstream's "g/ml". The entry's own unit
/// says only how it was logged; the amount is never in it.
({String unit, double factor}) shownUnit(IntakeEntity intake, bool imperial) =>
    switch (intake.meal.mealUnit) {
      'g' when imperial => (unit: 'oz', factor: UnitCalc.gToOz(1)),
      'ml' when imperial => (unit: 'fl.oz', factor: UnitCalc.mlToFlOz(1)),
      'g/ml' || null => (unit: 'g', factor: 1.0),
      final unit => (unit: unit, factor: 1.0),
    };
