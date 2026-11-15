import 'package:flutter/material.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/utils/calc/unit_calc.dart';
import 'package:opennutritracker/core/utils/custom_text_input_formatter.dart';
import 'package:opennutritracker/fork/units/amount_text.dart' show isEnergyOnly; // [fork] S142
import 'package:opennutritracker/fork/units/energy_text.dart'; // [fork] S142
// [fork] S177 copy-move
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/fork/widget/meal_picker_chip.dart';
// [/fork]
// [fork] S220 edit-in-unit
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/fork/amounts/amount_picker.dart';
import 'package:opennutritracker/fork/amounts/edit_amount.dart';
import 'package:opennutritracker/fork/amounts/own_portions.dart';
// [/fork]
import 'package:opennutritracker/generated/l10n.dart';

class EditDialog extends StatefulWidget {
  // [fork] S83 tap-delete: what the dialog returns for Delete, a plain tap
  // path beside the long-press drag (WCAG 2.5.7)
  static const deleteResult = -1.0;
  // [/fork]
  // [fork] S83 whole-meal: what the dialog returns for the leftovers of
  // the whole meal the entry was logged in (S9, S10)
  static const wholeMealResult = -2.0;
  static const wholeMealLabel = 'Leftovers of the whole meal';
  final bool wholeMeal;
  // [/fork]
  final IntakeEntity intakeEntity;
  final bool usesImperialUnits;
  // [fork] S177 copy-move: the meal, changed here and applied on OK by
  // the caller; null where it cannot be changed
  final ValueNotifier<IntakeTypeEntity>? meal;
  // [/fork]
  // [fork] S220 edit-in-unit: the unit the amount is in, changed here and
  // stored on OK by the caller; null keeps the plain field in grams
  final ValueNotifier<String>? unit;
  // [/fork]

  const EditDialog({
    super.key,
    required this.intakeEntity,
    required this.usesImperialUnits,
    this.meal, // [fork] S177
    this.unit, // [fork] S220
    this.wholeMeal = false, // [fork] S83
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
  late double _loggedAmount; // [fork] S220

  // [fork] S83 select-on-focus: tapping into a field selects what it holds,
  // so typing replaces the amount rather than adding to it
  late final _amountFocus = _selectAllOnFocus(amountEditingController);
  late final _leftoverFocus = _selectAllOnFocus(leftoverEditingController);

  static FocusNode _selectAllOnFocus(TextEditingController controller) {
    final node = FocusNode();
    node.addListener(() {
      if (!node.hasFocus) return;
      controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: controller.text.length,
      );
    });
    return node;
  }
  // [/fork]

  // [fork] S142 energy-only: a Quick add with only its energy (100 "gml"
  // of a made-up food) is edited as its energy, not a quantity (H2)
  late final double? _kcalPerUnit = _energyOnlyKcalPerUnit(
    widget.intakeEntity,
  );

  static double? _energyOnlyKcalPerUnit(IntakeEntity intake) {
    final meal = intake.meal;
    return isEnergyOnly(meal)
        ? (meal.nutriments.energyKcal100 ?? 0) / 100
        : null;
  }

  double _shownEnergy(double kcal) =>
      usesKj(context, listen: false) ? UnitCalc.kcalToKj(kcal) : kcal;
  // [/fork]

  // [fork] S220 edit-in-unit: the amount in the food page's picker, opened
  // in the unit the entry was logged in, with the user's own portions
  MealEntity? _forkMeal;
  late EditAmount _forkOpened;

  Future<void> _forkLoad() async {
    final base = widget.intakeEntity.meal;
    final meal = withOwnPortions(base, await OwnPortions.current.of(base));
    if (!mounted) return;
    final opened = editOpening(
      widget.intakeEntity,
      meal,
      imperial: widget.usesImperialUnits,
    );
    setState(() {
      _forkMeal = meal;
      _forkOpened = opened;
      _loggedAmount = opened.quantity;
      widget.unit!.value = opened.unit;
      amountEditingController.text = _amountText(opened.quantity);
    });
  }

  /// A new unit counts what was logged in it, and a leftover typed in the
  /// old one is cleared rather than read in the new.
  void _forkSet(String text, String to) {
    final unit = widget.unit!;
    setState(() {
      if (to != unit.value) {
        _loggedAmount = quantityInUnit(
          _loggedAmount,
          unit.value,
          to,
          _forkMeal!,
        );
        leftoverEditingController.clear();
      }
      unit.value = to;
      amountEditingController.text = text;
    });
  }
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
    if (widget.unit != null && _kcalPerUnit == null) _forkLoad(); // [fork] S220
  }

  @override
  void dispose() {
    amountEditingController.dispose();
    leftoverEditingController.dispose();
    _amountFocus.dispose(); // [fork] S83
    _leftoverFocus.dispose(); // [fork] S83
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
      // at 200% font on a small screen the fields are taller than it (A6)
      scrollable: true,
      // [/fork]
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // [fork] S177 copy-move
          if (widget.meal case final meal?) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: ValueListenableBuilder(
                valueListenable: meal,
                builder: (context, type, _) => MealPickerChip(
                  key: const Key('fork-edit-meal'),
                  type: type,
                  onChanged: (type) => meal.value = type,
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
          // [/fork]
          // [fork] S220 edit-in-unit: nothing in its place for the moment
          // the own portions load, so no number shows in the wrong unit
          if (widget.unit != null && _kcalPerUnit == null)
            if (_forkMeal case final meal?)
              AmountPicker(
                meal: meal,
                unit: widget.unit!.value,
                controller: amountEditingController,
                focusNode: _amountFocus,
                imperial: widget.usesImperialUnits,
                onSet: _forkSet,
              )
            else
              const SizedBox(height: 48)
          else
          // [/fork]
          TextFormField(
            controller: amountEditingController,
            focusNode: _amountFocus, // [fork] S83
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
            focusNode: _leftoverFocus, // [fork] S83
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
              helperMaxLines: 5, // [fork] S220: 4 lines at 200%, 360 dp
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
          // [fork] S83 whole-meal: 48 dp tall (A1), and its label wraps (A6)
          if (widget.wholeMeal) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                onPressed: () =>
                    Navigator.of(context).pop(EditDialog.wholeMealResult),
                icon: const Icon(Icons.restaurant_rounded),
                label: const Text(EditDialog.wholeMealLabel),
              ),
            ),
          ],
          // [/fork]
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
        // a Wrap: at 200% font Cancel and OK are wider than a 360 dp screen
        Wrap(
          alignment: WrapAlignment.end,
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
                // [fork] S220 edit-in-unit: grams for the amount in the unit
                // chosen, which the caller reads from the notifier
                if (_forkMeal case final meal?) {
                  // nothing changed: the unit stays as it was logged, also
                  // one that opened as its weight
                  if (editUnchanged(
                    newAmount,
                    widget.unit!.value,
                    _forkOpened,
                  )) {
                    widget.unit!.value = widget.intakeEntity.unit;
                    Navigator.of(context).pop(widget.intakeEntity.amount);
                    return;
                  }
                  Navigator.of(context).pop(
                    editStoredAmount(
                      newAmount,
                      widget.unit!.value,
                      meal,
                      widget.intakeEntity,
                      _forkOpened,
                    ),
                  );
                  return;
                }
                // [/fork]
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
      // [fork] S220 edit-in-unit: the leftover in the picker's unit
      : _forkMeal != null
      ? editUnitWord(
          context,
          _forkMeal!,
          widget.unit!.value,
          imperial: widget.usesImperialUnits,
        )
      // [/fork]
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
