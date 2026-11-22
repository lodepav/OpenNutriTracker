import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/sheet_bottom_inset.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/generated/l10n.dart';
// [fork] S300 ingredient-amount: a serving prefilled, the typed amount's energy and macros
import 'package:opennutritracker/core/domain/usecase/compute_recipe_nutrition_usecase.dart';
import 'package:opennutritracker/fork/recipe/recipe_list.dart' show macroSpans;
import 'package:opennutritracker/fork/units/energy_text.dart';
// [/fork]

class IngredientQuantitySelection {
  final double amount;
  final String unit;
  const IngredientQuantitySelection({required this.amount, required this.unit});
}

/// Modal bottom sheet that asks for the amount + unit of an ingredient.
/// Returns an [IngredientQuantitySelection] or null if cancelled.
Future<IngredientQuantitySelection?> showIngredientQuantityDialog(
  BuildContext context, {
  required MealEntity meal,
  double? initialAmount,
  String? initialUnit,
}) {
  return showModalBottomSheet<IngredientQuantitySelection>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true, // [fork] S487 drag-handle: the platform's (P1)
    builder: (ctx) => _IngredientQuantitySheet(
      meal: meal,
      initialAmount: initialAmount,
      initialUnit: initialUnit,
    ),
  );
}

class _IngredientQuantitySheet extends StatefulWidget {
  final MealEntity meal;
  final double? initialAmount;
  final String? initialUnit;

  const _IngredientQuantitySheet({
    required this.meal,
    this.initialAmount,
    this.initialUnit,
  });

  @override
  State<_IngredientQuantitySheet> createState() =>
      _IngredientQuantitySheetState();
}

class _IngredientQuantitySheetState extends State<_IngredientQuantitySheet> {
  late TextEditingController _amountController;
  late String _unit;

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController(
      text: widget.initialAmount != null
          ? widget.initialAmount!.toString()
          // [fork] S300 ingredient-amount: a new pick starts at one serving when it has a weight
          // : '',
          : _forkServingPrefill(),
          // [/fork]
    );
    _unit = widget.initialUnit ?? _defaultUnit(widget.meal);
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  // [fork] S300 ingredient-amount
  // "1" only where the default unit is a serving that converts to grams.
  // S565 ingredient-prefill-100: else 100 g or ml, so Add never meets an
  // empty field (G3-12)
  String _forkServingPrefill() {
    if (widget.initialUnit != null) return '';
    if (!widget.meal.hasServingValues) return '100';
    return (widget.meal.servingQuantity ?? 0) > 0 ? '1' : '';
  }

  /// The typed amount's energy and macros, or nothing while it can not be
  /// worked out (no amount, no energy figure, a serving without a weight).
  Widget _forkPreview(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: _amountController,
      builder: (context, value, _) {
        final amount = double.tryParse(value.text.replaceAll(',', '.'));
        final n = widget.meal.nutriments;
        final grams = amount == null || amount <= 0
            ? null
            : ComputeRecipeNutritionUseCase().convertAmountToGrams(
                amount: amount,
                unit: _unit,
                servingQuantityG: widget.meal.servingQuantity,
              );
        if (grams == null || n.energyKcal100 == null) {
          return const SizedBox.shrink();
        }
        double of(double? per100) => (per100 ?? 0) * grams / 100;
        final theme = Theme.of(context);
        return Padding(
          padding: const EdgeInsets.only(top: Dimens.spacing8),
          child: Text.rich(
            TextSpan(children: [
              TextSpan(text: energyText(context, of(n.energyKcal100))),
              const TextSpan(text: ' · ', semanticsLabel: ', '),
              ...macroSpans(context, (
                kcal: of(n.energyKcal100),
                carbs: of(n.carbohydrates100),
                fat: of(n.fat100),
                protein: of(n.proteins100),
              )),
            ]),
            key: const ValueKey('ingredient-amount-preview'),
            style: theme.textTheme.bodyMedium,
          ),
        );
      },
    );
  }
  // [/fork]

  String _defaultUnit(MealEntity meal) {
    if (meal.hasServingValues) return 'serving';
    if (meal.isLiquid) return 'ml';
    return 'g';
  }

  List<DropdownMenuItem<String>> _unitItems(BuildContext context) {
    final items = <DropdownMenuItem<String>>[];
    if (widget.meal.hasServingValues) {
      items.add(_unitItem('serving'));
    }
    if (widget.meal.isSolid ||
        (!widget.meal.isLiquid && !widget.meal.isSolid)) {
      items.add(_unitItem('g'));
      items.add(_unitItem('kg'));
      items.add(_unitItem('oz'));
    }
    if (widget.meal.isLiquid ||
        (!widget.meal.isLiquid && !widget.meal.isSolid)) {
      items.add(_unitItem('ml'));
      items.add(_unitItem('l'));
      items.add(_unitItem('fl.oz'));
    }
    return items;
  }

  DropdownMenuItem<String> _unitItem(String unit) {
    return DropdownMenuItem(
      value: unit,
      child: Text(unit, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final palette = isDark ? AppPalette.dark : AppPalette.light;
    final fieldBorder = OutlineInputBorder(
      borderRadius: Dimens.borderRadiusS,
      // [fork] S568 recipes-audit-p3: the theme's 3:1 field edge (S552),
      // not the 1.1:1 hairline (A4)
      // borderSide: BorderSide(color: palette.border, width: Dimens.hairline),
      borderSide: BorderSide(color: palette.textMuted),
      // [/fork]
    );
    return Padding(
      padding: EdgeInsets.only(bottom: sheetBottomInset(context)),
      child: Container(
        // [fork] S487 drag-handle: the handle's own space is above
        // padding: const EdgeInsets.fromLTRB(Dimens.spacing24, Dimens.spacing24, Dimens.spacing24, Dimens.spacing16),
        padding: const EdgeInsets.fromLTRB(Dimens.spacing24, 0, Dimens.spacing24, Dimens.spacing16),
        // [/fork]
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(Dimens.radiusXL),
            topRight: Radius.circular(Dimens.radiusXL),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // [fork] S487 drag-handle
            // Center(
            //   child: Container(
            //     width: 40,
            //     height: 4,
            //     decoration: BoxDecoration(
            //       color: palette.border,
            //       borderRadius: BorderRadius.circular(2),
            //     ),
            //   ),
            // ),
            // const SizedBox(height: Dimens.spacing20),
            // [/fork]
            Text(
              widget.meal.name ?? '?',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              maxLines: 2, // [fork] S486 two-line-names: A6
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: Dimens.spacing16),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextFormField(
                    controller: _amountController,
                    autofocus: true,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                        RegExp(r'^\d+([.,]\d{0,2})?$'),
                      ),
                    ],
                    decoration: InputDecoration(
                      labelText: S.of(context).recipeIngredientAmountLabel,
                      border: fieldBorder,
                      enabledBorder: fieldBorder,
                    ),
                  ),
                ),
                const SizedBox(width: Dimens.spacing12),
                Expanded(
                  flex: 2,
                  child: DropdownButtonFormField<String>(
                    isExpanded: true,
                    itemHeight: null,
                    initialValue: _unit,
                    borderRadius: Dimens.borderRadiusM,
                    decoration: InputDecoration(
                      labelText: S.of(context).recipeIngredientUnitLabel,
                      border: fieldBorder,
                      enabledBorder: fieldBorder,
                    ),
                    items: _unitItems(context),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _unit = value);
                      }
                    },
                  ),
                ),
              ],
            ),
            // [fork] S300 ingredient-amount
            _forkPreview(context),
            // [/fork]
            const SizedBox(height: Dimens.spacing24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: Dimens.spacing16),
                  shape: Dimens.shapeM,
                ),
                onPressed: _onConfirm,
                child: Text(S.of(context).addLabel),
              ),
            ),
            const SizedBox(height: Dimens.spacing8),
          ],
        ),
      ),
    );
  }

  void _onConfirm() {
    final raw = _amountController.text.replaceAll(',', '.');
    final amount = double.tryParse(raw);
    if (amount == null || amount <= 0) {
      Navigator.of(context).pop();
      return;
    }
    Navigator.of(context).pop(
      IngredientQuantitySelection(amount: amount, unit: _unit),
    );
  }
}
