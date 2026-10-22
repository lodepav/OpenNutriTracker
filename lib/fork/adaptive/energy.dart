/// The energy stored in a change of body weight (D13). Pure Dart; sources
/// in fork/research/phase3-macrofactor-algorithms.md.
library;

/// Hall 2008: fat 39.5 MJ/kg, lean change 7.6 MJ/kg.
const fatKcalPerKg = 9441.0;
const leanKcalPerKg = 1817.0;

/// Forbes's constant: the fat-free share of a change is 10.4 / (10.4 + F).
const _forbesKg = 10.4;

/// The fallback when no fat mass is known (SparkyFitness, ~13 kg of fat).
const flatKcalPerKg = 6000.0;

/// Share of a small weight change that is fat, for [fatMassKg] (Forbes).
double fatShare(double fatMassKg) => fatMassKg / (fatMassKg + _forbesKg);

/// kcal in 1 kg of weight change at [fatMassKg] (Forbes via Hall 2008).
double energyDensity(double fatMassKg) {
  final fat = fatShare(fatMassKg);
  return fat * fatKcalPerKg + (1 - fat) * leanKcalPerKg;
}

/// Body fat % from BMI, age and sex (Deurenberg et al. 1991, adults):
/// 1.20·BMI + 0.23·age − 10.8·sex − 5.4, [sex] 1 male, 0 female, 0.5 for
/// the averaged profile.
double deurenbergBodyFatPercent({
  required double bmi,
  required double age,
  required double sex,
}) => 1.20 * bmi + 0.23 * age - 10.8 * sex - 5.4;

/// Fat mass for a weight, at a body-fat share estimated once: the share
/// moves with the weight by Forbes, but over weeks that is a small effect
/// beside the estimate's own 4-point error, so the share is held.
double fatMassKg(double weightKg, double bodyFatPercent) =>
    weightKg * (bodyFatPercent / 100).clamp(0.03, 0.7);
