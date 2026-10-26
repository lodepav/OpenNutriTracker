import 'package:flutter/material.dart';
import 'package:horizontal_picker/horizontal_picker.dart';
import 'package:opennutritracker/core/domain/entity/body_weight_unit_entity.dart';
import 'package:opennutritracker/core/utils/calc/unit_calc.dart';
import 'package:opennutritracker/features/profile/presentation/utils/profile_picker_bounds.dart';
import 'package:opennutritracker/features/profile/presentation/widgets/body_weight_input.dart';
import 'package:opennutritracker/generated/l10n.dart';

/// Outcome of [SetTargetWeightDialog]. The dialog has three exits:
///
///   * Cancel — returns `null` from `showDialog`.
///   * OK with a value — returns a [TargetWeightDialogResult] with [value]
///     set (in kg) and [clear] false. Caller persists the new target.
///   * Clear (only offered when a target is already set) — returns a result
///     with [clear] true and [value] null. Caller writes `null` back to the
///     user record.
///
/// Keeping clear separate from "OK with value" means a user who never wanted
/// a target in the first place isn't forced to commit to an arbitrary number
/// just to back out of the dialog.
class TargetWeightDialogResult {
  /// Weight in kilograms, or null when [clear] is true.
  final double? value;
  final bool clear;

  const TargetWeightDialogResult.value(this.value) : clear = false;
  const TargetWeightDialogResult.cleared()
      : value = null,
        clear = true;
}

class SetTargetWeightDialog extends StatefulWidget {
  /// Initial weight to centre the picker on, in kilograms. When the user has
  /// no existing target the caller typically seeds this from current weight.
  final double initialKg;

  /// Whether the user already has a target set. Controls whether the
  /// "Clear target" action is offered alongside the OK / Cancel buttons.
  final bool hasExistingTarget;

  final BodyWeightUnit unit;

  const SetTargetWeightDialog({
    super.key,
    required this.initialKg,
    required this.hasExistingTarget,
    required this.unit,
  });

  @override
  State<SetTargetWeightDialog> createState() => _SetTargetWeightDialogState();
}

class _SetTargetWeightDialogState extends State<SetTargetWeightDialog> {
  // Picker display value for kg / lb paths.
  late double _pickerDisplayWeight;

  // Stones path: kg from BodyWeightInput, null if invalid/empty.
  double? _stKg;

  // [fork] S111 typed-weigh-in: kg and lb can be typed too, as a target
  // far off took flings and drags on the 0.1 ruler (JC3). The field
  // follows the ruler; whichever moved last is saved.
  bool _typedLast = false;
  // [/fork]

  @override
  void initState() {
    super.initState();
    _pickerDisplayWeight = _toDisplay(widget.initialKg);
    _stKg = widget.initialKg;
  }

  double _toDisplay(double kg) {
    switch (widget.unit) {
      case BodyWeightUnit.kg:
        return kg;
      case BodyWeightUnit.lb:
        return UnitCalc.kgToLbs(kg);
      case BodyWeightUnit.st:
        return 0; // placeholder — st uses BodyWeightInput
    }
  }

  double _pickerWeightToKg(double display) {
    switch (widget.unit) {
      case BodyWeightUnit.kg:
        return display;
      case BodyWeightUnit.lb:
        return UnitCalc.lbsToKg(display);
      case BodyWeightUnit.st:
        return display; // unreachable
    }
  }

  void _submitValue() {
    final double kg;
    if (widget.unit == BodyWeightUnit.st || _typedLast /* [fork] S111 */) {
      final valid = _stKg;
      if (valid == null) {
        Navigator.of(context).pop();
        return;
      }
      kg = valid;
    } else {
      final isImperial = widget.unit == BodyWeightUnit.lb;
      final display = clampWeightSelection(
        _pickerDisplayWeight,
        minSelectableWeight(_pickerDisplayWeight, isImperial),
      );
      kg = _pickerWeightToKg(display);
    }
    Navigator.of(context).pop(TargetWeightDialogResult.value(kg));
  }

  @override
  Widget build(BuildContext context) {
    final isImperial = widget.unit == BodyWeightUnit.lb;
    final minWeight = minSelectableWeight(_pickerDisplayWeight, isImperial);
    final maxWeight = maxSelectableWeight(_pickerDisplayWeight, isImperial);
    // [fork] S111: a typed weight out of range says so, and OK waits for it
    final invalid =
        (widget.unit == BodyWeightUnit.st || _typedLast) && _stKg == null;
    final error = invalid ? S.of(context).onboardingWrongWeightLabel : null;
    // [/fork]

    return AlertDialog(
      title: Text(S.of(context).profileTargetWeightLabel),
      content: Wrap(
        children: [
          Column(
            children: [
              if (widget.unit == BodyWeightUnit.st)
                BodyWeightInput(
                  initialKg: widget.initialKg,
                  unit: BodyWeightUnit.st,
                  identifierPrefix: 'set-target-weight-dialog',
                  autofocus: true,
                  errorText: error, // [fork] S111
                  onChangedKg: (kg) => setState(() => _stKg = kg),
                )
              else
                // [fork] S111: the typed field below says the weight; the
                // ruler is dimmed while a typed weight is the one saved
                ExcludeSemantics(
                  child: Opacity(
                  opacity: _typedLast ? 0.38 : 1,
                  child: HorizontalPicker(
                  height: 100,
                  backgroundColor: Colors.transparent,
                  minValue: minWeight,
                  maxValue: maxWeight,
                  initialPosition: InitialPosition.center,
                  divisions: 1000,
                  suffix: isImperial
                      ? S.of(context).lbsLabel
                      : S.of(context).kgLabel,
                  onChanged: (value) {
                    setState(() {
                      _pickerDisplayWeight = value;
                      _typedLast = false; // [fork] S111
                    });
                  },
                ),
                ),
                ),
              // [/fork]
              // [fork] S111 typed-weigh-in
              if (widget.unit != BodyWeightUnit.st)
                BodyWeightInput(
                  // Reseeded as the ruler moves.
                  key: ValueKey(_pickerDisplayWeight.toStringAsFixed(1)),
                  initialKg: _pickerWeightToKg(
                    double.parse(_pickerDisplayWeight.toStringAsFixed(1)),
                  ),
                  unit: widget.unit,
                  identifierPrefix: 'set-target-weight-dialog',
                  errorText: error,
                  onChangedKg: (kg) => setState(() {
                    _stKg = kg;
                    _typedLast = true;
                  }),
                ),
              // [/fork]
            ],
          ),
        ],
      ),
      actions: <Widget>[
        if (widget.hasExistingTarget)
          TextButton(
            onPressed: () => Navigator.of(context).pop(
              const TargetWeightDialogResult.cleared(),
            ),
            child: Text(S.of(context).profileTargetWeightClearAction),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(S.of(context).dialogCancelLabel),
        ),
        TextButton(
          onPressed: invalid ? null : _submitValue, // [fork] S111
          child: Text(S.of(context).dialogOKLabel),
        ),
      ],
    );
  }
}
