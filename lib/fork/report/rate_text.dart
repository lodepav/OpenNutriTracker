import 'package:opennutritracker/core/domain/entity/body_weight_unit_entity.dart';

/// A weekly rate at two decimals with its sign, "+0.12" or "-0.18"; one
/// that rounds to nothing is "0.00", never "-0.00".
String signedRate(double rate) {
  final text = rate.toStringAsFixed(2);
  if (double.parse(text) == 0) return '0.00';
  // a true minus, as signedText draws it
  return rate > 0 ? '+$text' : text.replaceFirst('-', '\u2212');
}

/// A week's change in kg as shown: in kg, or in pounds for lb and st
/// (stones are too coarse), rounded to two decimals, as the rate dialog
/// picks them (0.25); 0 for one that rounds to nothing.
double weeklyRateShown(double kgPerWeek, BodyWeightUnit unit) {
  // Not UnitCalc.kgToLbs, which rounds to a tenth first.
  final v = unit == BodyWeightUnit.kg ? kgPerWeek : kgPerWeek * 2.20462;
  final shown = double.parse(v.toStringAsFixed(2));
  return shown == 0 ? 0 : shown;
}

/// Unsigned, trailing zeros trimmed: "0.25", "0.5", "1", "0".
({String digits, String unit}) _rate(double kgPerWeek, BodyWeightUnit unit) {
  final digits = weeklyRateShown(
    kgPerWeek,
    unit,
  ).abs().toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
  return (digits: digits, unit: unit == BodyWeightUnit.kg ? 'kg' : 'lb');
}

/// "−0.16 kg a week" (a true minus), "+0.04 lb a week", "0 kg a week".
String weeklyRateText(double kgPerWeek, BodyWeightUnit unit) {
  final r = _rate(kgPerWeek, unit);
  final sign = r.digits == '0' ? '' : (kgPerWeek < 0 ? '−' : '+');
  return '$sign${r.digits} ${r.unit} a week';
}

/// "0.25 kg a week", for where a word says which way.
String unsignedRateText(double kgPerWeek, BodyWeightUnit unit) {
  final r = _rate(kgPerWeek, unit);
  return '${r.digits} ${r.unit} a week';
}

/// [weeklyRateText] as spoken: "down 0.16 kg a week", "up …", "steady".
String weeklyRateSpoken(double kgPerWeek, BodyWeightUnit unit) {
  final r = _rate(kgPerWeek, unit);
  if (r.digits == '0') return 'steady';
  return '${kgPerWeek < 0 ? 'down' : 'up'} ${r.digits} ${r.unit} a week';
}
