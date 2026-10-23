import 'dart:math';

import 'package:opennutritracker/fork/adaptive/adaptive_store.dart';

/// How the energy left after protein splits between carbs and fat
/// (MacroFactor's diet styles).
enum MacroStyle {
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

  /// 1.6 g/kg is where the gain from more protein levels off (Morton et
  /// al. 2018); lean mass takes more per kg for the same grams.
  static const defaultPerKg = 1.8;
  static const defaultPerKgLean = 2.2;

  /// Protein's share of energy is held to this, so a small target still
  /// leaves room for carbs and fat.
  static const maxProteinShare = 0.6;
  static const ketoCarbsG = 30.0;

  const MacroProgram({
    this.style = MacroStyle.balanced,
    this.proteinGPerKg = defaultPerKg,
    this.leanMass = false,
  });

  Map<String, Object> toJson() => {
    'style': style.name,
    'proteinGPerKg': proteinGPerKg,
    'leanMass': leanMass,
  };

  static MacroProgram fromJson(Map<dynamic, dynamic> json) => MacroProgram(
    style: MacroStyle.values.byName(json['style'] as String),
    proteinGPerKg: (json['proteinGPerKg'] as num).toDouble(),
    leanMass: json['leanMass'] as bool,
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

  String get summary =>
      '${style.label}, protein ${proteinGPerKg.toStringAsFixed(1)} g/kg'
      '${leanMass ? ' of lean mass' : ''}';
}
