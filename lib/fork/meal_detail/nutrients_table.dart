import 'package:flutter/material.dart';
import 'package:opennutritracker/core/presentation/widgets/app_card.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/energy_display.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/meal_detail/presentation/widgets/meal_detail_nutriments_table.dart'
    show missingNutrientPlaceholder;
import 'package:opennutritracker/generated/l10n.dart';

/// A nutrient's amount as the table shows it: whole above 10, one decimal
/// under it ("25.73" is "26 g", "4.56" is "4.6 g", "0.0" is "0 g"), a space
/// before the unit. Milligrams and micrograms under 1 keep two decimals
/// ("0.04 µg"). A trace that would round to none reads "<0.1" ("<0.01"),
/// so it is not taken for none.
String nutrientAmountText(double value, String unit) {
  if (unit != 'g' && value < 1 && (value * 100).round() < 100) {
    if (value > 0 && value < 0.005) return '<0.01 $unit';
    if ((value * 100).round() % 10 != 0) {
      return '${value.toStringAsFixed(2)} $unit';
    }
  }
  if (value > 0 && value < 0.05) return '<0.1 $unit';
  final tenths = (value * 10).round();
  final shown = value >= 10 || tenths % 10 == 0
      ? '${value.round()}'
      : (tenths / 10).toStringAsFixed(1);
  return '$shown $unit';
}

/// [label] with a capital first letter: "saturated fat" is "Saturated fat".
String nutrientName(String label) =>
    label.isEmpty ? label : label[0].toUpperCase() + label.substring(1);

/// Seam S221: the food page's nutrition table in place of upstream's
/// MealDetailNutrimentsTable, with the same rows and micronutrient switch:
/// its heading inside the card it heads, names in sentence case, amounts by
/// [nutrientAmountText], "Per 100 g" or "Per 100 ml", and each row read as
/// "Fat 21 g" (A5).
class FoodNutrientsTable extends StatelessWidget {
  final MealEntity product;
  final bool usesImperialUnits;
  final double? servingQuantity;
  final String? servingUnit;
  final bool showMicronutrients;

  const FoodNutrientsTable({
    super.key,
    required this.product,
    required this.usesImperialUnits,
    this.servingQuantity,
    this.servingUnit,
    this.showMicronutrients = false,
  });

  /// Per serving on an imperial profile with a serving, as upstream's.
  bool get _perServing => usesImperialUnits && servingQuantity != null;

  double _adjusted(double per100) =>
      _perServing ? per100 * servingQuantity! / 100 : per100;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final theme = Theme.of(context);
    final palette = paletteOf(context);
    final normal =
        theme.textTheme.bodyMedium?.copyWith(color: palette.textStrong) ??
        const TextStyle();
    final muted =
        theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w700,
          color: palette.textMuted,
        ) ??
        const TextStyle();
    final per = _perServing
        ? 'Per serving (${nutrientAmountText(servingQuantity!, servingUnit == null || servingUnit == 'gml' ? (product.isLiquid ? 'ml' : 'g') : servingUnit!)})'
        : 'Per 100 ${product.isLiquid ? 'ml' : 'g'}';
    final n = product.nutriments;

    TableRow row(
      String label,
      double? per100,
      String unit, {
      bool sub = false,
      String? energy,
    }) {
      final name = nutrientName(label);
      final value =
          energy ??
          (per100 == null
              ? missingNutrientPlaceholder
              : nutrientAmountText(_adjusted(per100), unit));
      final spoken = value == missingNutrientPlaceholder
          ? '$name, not known'
          : '$name $value';
      return TableRow(
        children: [
          Padding(
            padding: EdgeInsetsDirectional.only(
              top: Dimens.spacing12,
              bottom: Dimens.spacing12,
              // a part of the row above, set in rather than spaced in
              start: sub ? Dimens.spacing16 : 0,
              end: Dimens.spacing8,
            ),
            child: Semantics(
              label: spoken,
              excludeSemantics: true,
              child: Text(name, style: normal),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Dimens.spacing12),
            child: ExcludeSemantics(
              child: Text(value, style: normal, textAlign: TextAlign.right),
            ),
          ),
        ],
      );
    }

    Widget table(List<TableRow> rows) => Table(
      columnWidths: const {0: FlexColumnWidth(), 1: IntrinsicColumnWidth()},
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      border: TableBorder(
        horizontalInside: BorderSide(
          color: palette.border,
          width: Dimens.hairline,
        ),
      ),
      children: rows,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          color: palette.surfaceMuted,
          padding: const EdgeInsets.fromLTRB(
            Dimens.spacing16,
            Dimens.spacing16,
            Dimens.spacing16,
            Dimens.spacing8,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // The heading heads the table, in its card (critique P3).
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(
                        s.nutritionInfoLabel,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: Dimens.spacing8),
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Semantics(
                      container: true,
                      child: Text(per, style: muted),
                    ),
                  ),
                ],
              ),
              table([
                row(
                  s.energyLabel,
                  n.energyKcal100,
                  '',
                  energy: n.energyKcal100 == null
                      ? null
                      : EnergyDisplay.formatWithUnit(
                          context,
                          _adjusted(n.energyKcal100!.toDouble()),
                        ),
                ),
                row(s.fatLabel, n.fat100, 'g'),
                row(s.saturatedFatLabel, n.saturatedFat100, 'g', sub: true),
                row(s.carbohydrateLabel, n.carbohydrates100, 'g'),
                row(s.sugarLabel, n.sugars100, 'g', sub: true),
                row(s.fiberLabel, n.fiber100, 'g'),
                row(s.proteinLabel, n.proteins100, 'g'),
              ]),
            ],
          ),
        ),
        // The Settings switch decides whether the section exists at all
        // (#1361); the data only decides whether it opens expanded.
        if (showMicronutrients) ...[
          const SizedBox(height: Dimens.spacing8),
          Theme(
            data: theme.copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text(
                s.micronutrientsLabel,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              initiallyExpanded: n.hasMicronutrientData,
              children: [
                AppCard(
                  color: palette.surfaceMuted,
                  padding: const EdgeInsets.symmetric(
                    horizontal: Dimens.spacing16,
                    vertical: Dimens.spacing8,
                  ),
                  child: table([
                    row(
                      s.monounsaturatedFatLabel,
                      n.monounsaturatedFat100,
                      'g',
                      sub: true,
                    ),
                    row(
                      s.polyunsaturatedFatLabel,
                      n.polyunsaturatedFat100,
                      'g',
                      sub: true,
                    ),
                    row(s.transFatLabel, n.transFat100, 'g', sub: true),
                    row(s.cholesterolLabel, n.cholesterol100, 'mg'),
                    row(s.sodiumLabel, n.sodium100, 'mg'),
                    row(s.potassiumLabel, n.potassium100, 'mg'),
                    row(s.magnesiumLabel, n.magnesium100, 'mg'),
                    row(s.calciumLabel, n.calcium100, 'mg'),
                    row(s.ironLabel, n.iron100, 'mg'),
                    row(s.zincLabel, n.zinc100, 'mg'),
                    row(s.phosphorusLabel, n.phosphorus100, 'mg'),
                    row(s.vitaminALabel, n.vitaminA100, 'µg'),
                    row(s.vitaminCLabel, n.vitaminC100, 'mg'),
                    row(s.vitaminDLabel, n.vitaminD100, 'µg'),
                    row(s.vitaminB6Label, n.vitaminB6100, 'mg'),
                    row(s.vitaminB12Label, n.vitaminB12100, 'µg'),
                    row(s.niacinLabel, n.niacin100, 'mg'),
                  ]),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
