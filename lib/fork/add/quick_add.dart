import 'package:flutter/material.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/custom_text_input_formatter.dart';
import 'package:opennutritracker/fork/display/display_prefs.dart';
import 'package:opennutritracker/fork/units/energy_text.dart';

/// Seam S133: Quick add after the canvas's "Quick add · A". The energy as
/// one big number, or left empty for the macros to add it up; the three
/// macros side by side in the user's macro order; the meal as a chip
/// beside the title and the energy on Add.

/// The energy to log in kcal: the typed one when above 0, else what the
/// macros add up to (4, 9 and 4 kcal a gram), else null.
double? quickAddKcal({
  double? typedKcal,
  double? carbs,
  double? fat,
  double? protein,
}) {
  if (typedKcal != null && typedKcal > 0) return typedKcal;
  final sum = 4.0 * (carbs ?? 0) + 9 * (fat ?? 0) + 4 * (protein ?? 0);
  return sum > 0 ? sum : null;
}

/// The energy field: a big centred number with its unit, hinting at what
/// the macros add up to while it is empty.
class QuickAddEnergyField extends StatelessWidget {
  final TextEditingController controller;

  /// What the macros add up to, in kcal; null when they add up to nothing.
  final double? macrosKcal;

  const QuickAddEnergyField({
    super.key,
    required this.controller,
    required this.macrosKcal,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unit = energyUnit(context);
    final big = theme.textTheme.displayMedium?.copyWith(
      fontWeight: FontWeight.w600,
    );
    return Column(
      children: [
        Semantics(
          identifier: 'quick-add-energy',
          label: 'Energy in $unit',
          child: TextField(
            controller: controller,
            autofocus: true,
            textAlign: TextAlign.center,
            style: big,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: CustomTextInputFormatter.doubleOnly(),
            decoration: InputDecoration(
              border: InputBorder.none,
              hintText: macrosKcal == null
                  ? '0'
                  : '${energyValue(context, macrosKcal!)}',
              hintStyle: big?.copyWith(color: theme.colorScheme.outline),
            ),
          ),
        ),
        Text(unit, style: theme.textTheme.titleMedium),
        const SizedBox(height: Dimens.spacing4),
        Text(
          'or let the macros add it up',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// Carbs, fat and protein in grams, side by side in the macro order, each
/// labelled in its colour.
class QuickAddMacroFields extends StatelessWidget {
  final TextEditingController carbs;
  final TextEditingController fat;
  final TextEditingController protein;

  const QuickAddMacroFields({
    super.key,
    required this.carbs,
    required this.fat,
    required this.protein,
  });

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).brightness == Brightness.dark
        ? AppPalette.dark
        : AppPalette.light;
    final fields = inMacroOrder(
      carbs: ('carbs', carbs, palette.carbs),
      fat: ('fat', fat, palette.fat),
      protein: ('protein', protein, palette.protein),
    );
    return Row(
      children: [
        for (final (i, (name, controller, color)) in fields.indexed) ...[
          if (i > 0) const SizedBox(width: Dimens.spacing8),
          Expanded(
            child: Semantics(
              identifier: 'quick-add-$name',
              child: TextField(
                controller: controller,
                textAlign: TextAlign.center,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: CustomTextInputFormatter.doubleOnly(),
                decoration: InputDecoration(
                  labelText: '$name g',
                  labelStyle: TextStyle(color: color),
                  floatingLabelStyle: TextStyle(color: color),
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
