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

/// [intake]'s amount as the app shows it on every list (H4): in
/// [shownUnit], whole when it is, else to one decimal, as "7.1 oz".
String amountText(IntakeEntity intake, bool imperial) {
  final shown = shownUnit(intake, imperial);
  final n = intake.amount * shown.factor;
  final text = n == n.roundToDouble()
      ? n.toInt().toString()
      : n.toStringAsFixed(1);
  return '$text ${shown.unit}';
}

/// [unit] as a screen reader should say it: "grams", not "g" (A5). An
/// unknown unit is said as written.
String spokenUnit(String unit) => switch (unit) {
  'g' || 'g/ml' => 'grams',
  'mg' => 'milligrams',
  'µg' || 'mcg' => 'micrograms',
  'ml' => 'millilitres',
  'oz' => 'ounces',
  'fl.oz' || 'fl oz' => 'fluid ounces',
  'kcal' => 'kilocalories',
  'kJ' => 'kilojoules',
  _ => unit,
};

/// Whether a serving's own text, as "1 serving (10 g)", names the
/// [quantity] the serving adds; a text naming no weight agrees. Some
/// databases carry a text and a quantity that disagree (S142).
bool servingTextAgrees(String text, double? quantity) {
  final named = RegExp(r'([\d.,]+)\s*(?:g|ml)\b').firstMatch(text);
  final value = double.tryParse(named?.group(1)?.replaceAll(',', '.') ?? '');
  if (value == null || quantity == null) return true;
  return (value - quantity).abs() < 0.5;
}
