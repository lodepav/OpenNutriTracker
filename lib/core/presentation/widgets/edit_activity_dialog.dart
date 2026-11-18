import 'package:flutter/material.dart';
import 'package:opennutritracker/core/domain/entity/user_activity_entity.dart';
import 'package:opennutritracker/core/utils/calc/unit_calc.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:provider/provider.dart';

class EditActivityDialog extends StatefulWidget {
  final UserActivityEntity activityEntity;
  // [fork] S278 activity-dialog-delete: what the dialog returns for Delete,
  // below any minutes or kcal it returns
  static const deleteResult = -1.0;
  // [/fork]

  const EditActivityDialog({super.key, required this.activityEntity});

  @override
  State<EditActivityDialog> createState() => _EditActivityDialogState();
}

class _EditActivityDialogState extends State<EditActivityDialog> {
  late TextEditingController _quantityController;
  bool _didSeed = false;

  bool get _isCustom => widget.activityEntity.physicalActivityEntity.isCustom;

  @override
  void initState() {
    super.initState();
    _quantityController = TextEditingController();
  }

  @override
  void dispose() {
    _quantityController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final usesKj = context.watch<EnergyUnitProvider>().usesKilojoules;
    // For Custom activities the dialog respects the user's Energy unit
    // setting (#177): the displayed value, suffix, and the parsed
    // result handed back to the caller all stay in the unit the user
    // is reading. The caller continues to receive a kcal figure
    // (everything on disk is kcal), so the conversion is local here.
    if (!_didSeed) {
      _didSeed = true;
      final storedKcal = _isCustom
          ? (widget.activityEntity.userKcal ?? widget.activityEntity.burnedKcal)
          : widget.activityEntity.duration;
      final displayValue = (_isCustom && usesKj)
          ? UnitCalc.kcalToKj(storedKcal)
          : storedKcal;
      _quantityController.text = displayValue.toInt().toString();
    }

    final suffix = _isCustom
        ? (usesKj ? S.of(context).kjLabel : S.of(context).kcalLabel)
        : S.of(context).minuteShortLabel;

    return AlertDialog(
      // [fork] S278 activity-dialog-name: named for the activity, as the
      // food dialog is for the food (S83)
      title: Text(widget.activityEntity.physicalActivityEntity.getName(context)),
      // title: Text(S.of(context).editItemDialogTitle),
      // [/fork]
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            identifier: 'edit-activity-quantity-input',
            child: TextFormField(
              controller: _quantityController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: _isCustom
                    ? (usesKj
                        ? S.of(context).mealEnergyLabel
                        : S.of(context).customActivityKcalLabel)
                    : S.of(context).quantityLabel,
                suffixText: suffix,
              ),
            ),
          ),
        ],
      ),
      // [fork] S278 activity-dialog-delete: Material order, as in the food
      // dialog (S83): Delete on its own on the left in the error colour
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actions: [
        TextButton(
          style: TextButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.error,
          ),
          onPressed: () =>
              Navigator.of(context).pop(EditActivityDialog.deleteResult),
          child: Text(S.of(context).dialogDeleteLabel),
        ),
        // a Wrap: at 200% font Cancel and OK are wider than a 360 dp screen
        Wrap(
          alignment: WrapAlignment.end,
          children: [
      // [/fork]
        // [fork] S277 activity-dialog-cancel-first: Cancel before OK, as
        // every other dialog has them; the upstream order moved below
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(S.of(context).dialogCancelLabel),
        ),
        // [/fork]
        TextButton(
          onPressed: () {
            final parsed = double.tryParse(_quantityController.text);
            if (parsed != null && parsed > 0) {
              final result = (_isCustom && usesKj)
                  ? UnitCalc.kjToKcal(parsed)
                  : parsed;
              Navigator.of(context).pop(result);
            }
          },
          child: Text(S.of(context).dialogOKLabel),
        ),
        // [fork] S277 activity-dialog-cancel-first
        // TextButton(
        //   onPressed: () => Navigator.of(context).pop(),
        //   child: Text(S.of(context).dialogCancelLabel),
        // ),
        // [/fork]
        // [fork] S278 activity-dialog-delete
          ],
        ),
        // [/fork]
      ],
    );
  }
}
