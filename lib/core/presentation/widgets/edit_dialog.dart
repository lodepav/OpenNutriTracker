import 'package:flutter/material.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/utils/calc/unit_calc.dart';
import 'package:opennutritracker/core/utils/custom_text_input_formatter.dart';
import 'package:opennutritracker/fork/units/energy_text.dart'; // [fork] S142
import 'package:opennutritracker/generated/l10n.dart';

class EditDialog extends StatefulWidget {
  // [fork] S83 tap-delete: what the dialog returns for Delete, a plain tap
  // path beside the long-press drag (WCAG 2.5.7)
  static const deleteResult = -1.0;
  // [/fork]
  final IntakeEntity intakeEntity;
  final bool usesImperialUnits;

  const EditDialog({
    super.key,
    required this.intakeEntity,
    required this.usesImperialUnits,
  });

  @override
  State<StatefulWidget> createState() => _EditDialogState();
}

class _EditDialogState extends State<EditDialog> {
  /// The fractions offered for what was left uneaten.
  static const leftoverFractions = {'¼': 0.25, '⅓': 1 / 3, '½': 0.5, '¾': 0.75};

  late TextEditingController amountEditingController;
  final leftoverEditingController = TextEditingController();

  /// The amount as logged, in the units shown, which what is left over is
  /// taken from.
  late final double _loggedAmount;

  // [fork] S142 energy-only: a Quick add with only its energy (100 "gml"
  // of a made-up food) is edited as its energy, not a quantity (H2)
  late final double? _kcalPerUnit = _energyOnlyKcalPerUnit(
    widget.intakeEntity,
  );

  static double? _energyOnlyKcalPerUnit(IntakeEntity intake) {
    final meal = intake.meal;
    final kcal100 = meal.nutriments.energyKcal100 ?? 0;
    final energyOnly =
        meal.mealUnit == 'gml' &&
        meal.mealQuantity == '100' &&
        meal.servingQuantity == null &&
        (meal.servingSize ?? '').isEmpty &&
        kcal100 > 0;
    return energyOnly ? kcal100 / 100 : null;
  }

  double _shownEnergy(double kcal) =>
      usesKj(context, listen: false) ? UnitCalc.kcalToKj(kcal) : kcal;
  // [/fork]

  @override
  void initState() {
    super.initState();
    double initialAmount = switch (_kcalPerUnit) {
      // [fork] S142
      final perUnit? => _shownEnergy(widget.intakeEntity.amount * perUnit),
      // [/fork]
      _ => _convertValue(
        widget.intakeEntity.amount,
        widget.intakeEntity.meal.mealUnit,
      ),
    };
    _loggedAmount = initialAmount;
    amountEditingController = TextEditingController(
      text: _amountText(initialAmount), // [fork] S83
    );
  }

  @override
  void dispose() {
    amountEditingController.dispose();
    leftoverEditingController.dispose();
    super.dispose();
  }

  /// Sets the amount to what was logged minus what was left, so the new
  /// amount shows in its own field before it is saved. A leftover that is
  /// not a number, or more than was logged, changes nothing.
  void _onLeftoverChanged(String text) {
    final left = double.tryParse(text.replaceAll(',', '.'));
    if (left == null || left < 0 || left > _loggedAmount) return;
    amountEditingController.text = _amountText(_loggedAmount - left); // [fork] S83
  }

  void _onLeftoverFraction(double fraction) {
    leftoverEditingController.text = _amountText(_loggedAmount * fraction); // [fork] S83
    _onLeftoverChanged(leftoverEditingController.text);
  }

  // [fork] S83 amount-text: "100" rather than "100.00", at most two
  // decimals and no trailing zeros
  static String _amountText(double value) => value
      .toStringAsFixed(2)
      .replaceFirst(RegExp(r'\.?0+$'), '');
  // [/fork]

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      // [fork] S83: the dialog names the food it edits
      title: Text(widget.intakeEntity.meal.name ?? S.of(context).editItemDialogTitle),
      // [/fork]
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextFormField(
            controller: amountEditingController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: CustomTextInputFormatter.doubleOnly(),
            decoration: InputDecoration(
              // [fork] S142
              labelText: _kcalPerUnit != null
                  ? S.of(context).mealEnergyLabel
                  : S.of(context).quantityLabel,
              suffixText: _shownUnit,
              // [/fork]
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: leftoverEditingController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: CustomTextInputFormatter.doubleOnly(),
            onChanged: _onLeftoverChanged,
            decoration: InputDecoration(
              labelText: S.of(context).leftoverLabel,
              // [fork] S142: the field above already shows what is left, so
              // the text says so rather than "taken off" again (H1); it
              // wraps rather than being cut (A6)
              helperText:
                  "What you didn't eat; the ${_kcalPerUnit != null ? 'energy' : 'quantity'} above goes down by it",
              helperMaxLines: 3,
              suffixText: _shownUnit,
              // [/fork]
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final MapEntry(key: label, value: fraction)
                  in leftoverFractions.entries)
                ActionChip(
                  label: Text(label),
                  onPressed: () => _onLeftoverFraction(fraction),
                ),
            ],
          ),
        ],
      ),
      // [fork] S83 tap-delete; Material order: Delete on its own on the
      // left in the error colour (S168), then Cancel, then the confirming OK
      // on the right
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actions: [
        TextButton(
          style: TextButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.error,
          ),
          onPressed: () => Navigator.of(context).pop(EditDialog.deleteResult),
          child: Text(S.of(context).dialogDeleteLabel),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(S.of(context).dialogCancelLabel),
            ),
            // [/fork]
            TextButton(
              onPressed: () {
                final newAmount = double.tryParse(
                  amountEditingController.text.replaceAll(',', '.'),
                );
                if (newAmount == null || newAmount <= 0) return; // [fork] S83
                Navigator.of(context).pop(
                  switch (_kcalPerUnit) {
                    // [fork] S142
                    final perUnit? =>
                      kcalFromInput(context, newAmount) / perUnit,
                    // [/fork]
                    _ => _convertBackToMetricValue(
                      newAmount,
                      widget.intakeEntity.meal.mealUnit,
                    ),
                  },
                );
              },
              child: Text(S.of(context).dialogOKLabel),
            ),
          ], // [fork] S168
        ), // [fork] S168
      ],
    );
  }

  double _convertValue(double value, String? unit) {
    switch (unit) {
      case 'g':
        return widget.usesImperialUnits ? UnitCalc.gToOz(value) : value;
      case 'ml':
        return widget.usesImperialUnits ? UnitCalc.mlToFlOz(value) : value;
      default:
        return value;
    }
  }

  double _convertBackToMetricValue(double value, String? unit) {
    switch (unit) {
      case 'g':
        return widget.usesImperialUnits ? UnitCalc.ozToG(value) : value;
      case 'ml':
        return widget.usesImperialUnits ? UnitCalc.flOzToMl(value) : value;
      default:
        return value;
    }
  }

  // [fork] S142: the energy's unit for an energy-only entry, and "g" for
  // upstream's "gml" rather than the code word
  String get _shownUnit => _kcalPerUnit != null
      ? (usesKj(context) ? 'kJ' : 'kcal')
      : _convertUnit(widget.intakeEntity.meal.mealUnit ?? '');
  // [/fork]

  String _convertUnit(String unit) {
    switch (unit) {
      case 'g':
        return widget.usesImperialUnits ? 'oz' : 'g';
      case 'ml':
        return widget.usesImperialUnits ? 'fl.oz' : 'ml';
      case 'gml': // [fork] S142
        return 'g';
      default:
        return unit;
    }
  }
}
