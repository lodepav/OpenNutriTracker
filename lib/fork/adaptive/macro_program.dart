import 'dart:math';

import 'package:opennutritracker/fork/adaptive/adaptive_store.dart';

/// How the energy left after protein splits between carbs and fat
/// (MacroFactor's diet styles). [perKg] is the fork's own: fat per kg of
/// body weight, the rest carbs. [balanced] and [lowFat] are no longer
/// offered, but a program saved with one keeps it.
enum MacroStyle {
  perKg('Fat per kg', 'Fat per kg of body weight, the rest carbs'),
  balanced('Balanced', 'Fat 30% of energy, the rest carbs'),
  lowFat('Low fat', 'Fat 20% of energy, the rest carbs'),
  lowCarb('Low carb', 'Carbs 25% of energy, the rest fat'),
  keto('Keto', 'Carbs 30 g, the rest fat');

  final String label;
  final String explanation;

  const MacroStyle(this.label, this.explanation);
}

/// Protein in grams per kg of body weight, or of lean mass, and a
/// [MacroStyle] for the rest; the grams follow the day's target, so a
/// weekday's shift moves carbs and fat and leaves protein.
class MacroProgram {
  final MacroStyle style;
  final double proteinGPerKg;

  /// Per kg of lean mass (weight less body fat) instead of body weight.
  final bool leanMass;

  /// Fat per kg of body weight, for [MacroStyle.perKg].
  final double fatGPerKg;

  /// Moderate, high and very high: 1.6 g/kg is where the gain from more
  /// protein levels off (Morton et al. 2018), 2.0 the top of the ISSN's
  /// range for building muscle (Jäger et al. 2017) and 2.2 the gym's one
  /// gram per pound. Per kg of lean mass the same grams for a body of 15%
  /// fat.
  static const proteinPresets = [1.6, 2.0, 2.2];
  static const proteinPresetsLean = [1.9, 2.4, 2.6];
  static const defaultPerKg = 1.6;
  static const defaultPerKgLean = 1.9;

  /// Low, moderate and high: about what physique athletes eat (0.8 to 1.0
  /// g/kg). Under 20% of energy from fat is not advised (ADA/ACSM 2009).
  static const fatPresets = [0.6, 0.8, 1.0];
  static const defaultFatPerKg = 0.8;
  static const minFatShare = 0.2;

  /// Protein's share of energy is held to this, so a small target still
  /// leaves room for carbs and fat.
  static const maxProteinShare = 0.6;
  static const ketoCarbsG = 30.0;

  const MacroProgram({
    this.style = MacroStyle.perKg,
    this.proteinGPerKg = defaultPerKg,
    this.leanMass = false,
    this.fatGPerKg = defaultFatPerKg,
  });

  MacroProgram copyWith({
    MacroStyle? style,
    double? proteinGPerKg,
    bool? leanMass,
    double? fatGPerKg,
  }) => MacroProgram(
    style: style ?? this.style,
    proteinGPerKg: proteinGPerKg ?? this.proteinGPerKg,
    leanMass: leanMass ?? this.leanMass,
    fatGPerKg: fatGPerKg ?? this.fatGPerKg,
  );

  Map<String, Object> toJson() => {
    'style': style.name,
    'proteinGPerKg': proteinGPerKg,
    'leanMass': leanMass,
    'fatGPerKg': fatGPerKg,
  };

  /// A program saved before fat per kg takes its default.
  static MacroProgram fromJson(Map<dynamic, dynamic> json) => MacroProgram(
    style: MacroStyle.values.byName(json['style'] as String),
    proteinGPerKg: (json['proteinGPerKg'] as num).toDouble(),
    leanMass: json['leanMass'] as bool,
    fatGPerKg: (json['fatGPerKg'] as num?)?.toDouble() ?? defaultFatPerKg,
  );

  /// The grams for a day's [kcal], for a body of [weightKg] at
  /// [bodyFatPercent].
  FixedMacros macrosFor({
    required double kcal,
    required double weightKg,
    required double bodyFatPercent,
  }) {
    final energy = max(kcal, 0.0);
    final basisKg = leanMass ? weightKg * (1 - bodyFatPercent / 100) : weightKg;
    final proteinG = min(proteinGPerKg * basisKg, energy * maxProteinShare / 4);
    final rest = energy - 4 * proteinG;
    double fatFromShare(double share) => min(energy * share, rest) / 9;
    double carbsFromKcal(double carbKcal) => min(carbKcal, rest) / 4;
    final (carbsG, fatG) = switch (style) {
      // Protein first, then fat, as far as the energy goes.
      MacroStyle.perKg => () {
        final fat = min(fatGPerKg * weightKg, rest / 9);
        return ((rest - 9 * fat) / 4, fat);
      }(),
      MacroStyle.balanced || MacroStyle.lowFat => () {
        final fat = fatFromShare(style == MacroStyle.balanced ? 0.3 : 0.2);
        return ((rest - 9 * fat) / 4, fat);
      }(),
      MacroStyle.lowCarb || MacroStyle.keto => () {
        final carbs = carbsFromKcal(
          style == MacroStyle.lowCarb ? energy * 0.25 : ketoCarbsG * 4,
        );
        return (carbs, (rest - 4 * carbs) / 9);
      }(),
    };
    return FixedMacros(proteinG: proteinG, carbsG: carbsG, fatG: fatG);
  }

  /// Grams per pound where body weight is in pounds, else per kg.
  String summary({bool perLb = false}) =>
      '${style == MacroStyle.perKg ? 'Fat ${perWeight(fatGPerKg, perLb)} ${unitOf(perLb)}' : style.label}, '
      'protein ${perWeight(proteinGPerKg, perLb)} ${unitOf(perLb)}'
      '${leanMass ? ' of lean mass' : ''}';

  static const lbPerKg = 2.20462;

  /// [gPerKg] as shown: one decimal per kg, two per pound, as 2.2 g/kg is
  /// 1.0 g/lb and 1.6 is 0.73.
  static String perWeight(double gPerKg, bool perLb) {
    if (!perLb) return gPerKg.toStringAsFixed(1);
    final text = (gPerKg / lbPerKg).toStringAsFixed(2);
    return text.endsWith('0') ? text.substring(0, text.length - 1) : text;
  }

  static String unitOf(bool perLb) => perLb ? 'g/lb' : 'g/kg';
}
