import 'package:flutter/material.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/features/home/domain/entity/nutrient_contribution_entity.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:opennutritracker/fork/display/macro_foods.dart'; // [fork] S124

/// Which of today's foods a macro total on the dashboard came from (#1266):
/// the total against its goal, then each food from the most to the least.
/// Tapping a food opens its details.
class NutrientContributionsScreen extends StatelessWidget {
  final MacroNutrient nutrient;
  final List<IntakeEntity> intakes;
  final double total;
  final double goal;

  /// The day and units a food's details open with.
  final DateTime day;
  final bool usesImperialUnits;

  // [fork] S124 macro-foods: the dashboard's other totals, for the switch
  final Map<FoodsMetric, FoodsTotal>? forkTotals;
  // [/fork]

  const NutrientContributionsScreen({
    super.key,
    required this.nutrient,
    required this.intakes,
    required this.total,
    required this.goal,
    required this.day,
    this.usesImperialUnits = false,
    this.forkTotals, // [fork] S124
  });

  static String nutrientLabel(BuildContext context, MacroNutrient nutrient) =>
      switch (nutrient) {
        MacroNutrient.carbs => S.of(context).carbsLabel,
        MacroNutrient.fat => S.of(context).fatLabel,
        MacroNutrient.protein => S.of(context).proteinLabel,
      };

  @override
  Widget build(BuildContext context) {
    // [fork] S124 macro-foods: MacroFactor's foods page (MacroA): a switch
    // between the energy and the macros, each food with its kind and a
    // bar for its share (upstream: one macro's list of tiles).
    return MacroFoodsPage(
      initial: FoodsMetric.of(nutrient),
      intakes: intakes,
      totals: {
        ...?forkTotals,
        FoodsMetric.of(nutrient): (eaten: total, goal: goal),
      },
      day: day,
      usesImperialUnits: usesImperialUnits,
    );
    // [/fork]
  }
}
