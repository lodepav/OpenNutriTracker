import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:opennutritracker/core/domain/entity/custom_activity_template_entity.dart';
import 'package:opennutritracker/core/domain/entity/physical_activity_entity.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/calc/unit_calc.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/features/activity_detail/presentation/bloc/activity_detail_bloc.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:opennutritracker/fork/activity/entry_hints.dart'; // [fork] S553
import 'package:provider/provider.dart';

/// Bottom sheet for the Activity Detail screen.
///
/// For compendium activities this is the quantity-in-minutes field plus
/// an Add button — unchanged from #70. For the Custom activity it adds
/// an optional name field, a "Save as template" checkbox, and a "Pick
/// from saved" affordance (#70 follow-up) so people who do the same
/// workout repeatedly can avoid retyping the kcal each time.
class ActivityDetailBottomSheet extends StatefulWidget {
  final Future<void> Function(
    BuildContext, {
    String? templateName,
    bool saveAsTemplate,
  })
  onAddButtonPressed;
  final PhysicalActivityEntity activityEntity;
  final TextEditingController quantityTextController;
  final ActivityDetailBloc activityDetailBloc;

  const ActivityDetailBottomSheet({
    super.key,
    required this.onAddButtonPressed,
    required this.quantityTextController,
    required this.activityEntity,
    required this.activityDetailBloc,
  });

  @override
  State<ActivityDetailBottomSheet> createState() =>
      _ActivityDetailBottomSheetState();
}

class _ActivityDetailBottomSheetState extends State<ActivityDetailBottomSheet> {
  final TextEditingController _nameController = TextEditingController();
  bool _saveAsTemplate = false;

  /// Set from the first tap on Add until its save ends. The save can wait
  /// for the tracked-day lock (#1317) with the screen still open, and a
  /// second tap would log the activity, and credit its energy, twice.
  bool _saving = false;

  Future<void> _onAddPressed() async {
    // Checked here, not only through the disabled button: a second tap
    // can land before the rebuild that disables it.
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final trimmedName = _nameController.text.trim();
      await widget.onAddButtonPressed(
        context,
        templateName: trimmedName.isEmpty ? null : trimmedName,
        saveAsTemplate: _saveAsTemplate,
      );
    } finally {
      // A save that succeeds leaves the screen; one that fails lets the
      // user try again.
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _openTemplatePicker() async {
    final templates =
        await widget.activityDetailBloc.loadCustomActivityTemplates();
    if (!mounted) return;

    final picked = await showModalBottomSheet<CustomActivityTemplateEntity>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: templates.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      S.of(sheetContext).customActivityTemplatesEmpty,
                      style: Theme.of(sheetContext).textTheme.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: templates.length,
                    itemBuilder: (listContext, index) {
                      final template = templates[index];
                      final tileUsesKj = Provider.of<EnergyUnitProvider>(
                        listContext,
                        listen: false,
                      ).usesKilojoules;
                      final tileValue = tileUsesKj
                          ? UnitCalc.kcalToKj(template.typicalKcal)
                          : template.typicalKcal;
                      final tileUnit = tileUsesKj
                          ? S.of(listContext).kjLabel
                          : S.of(listContext).kcalLabel;
                      return ListTile(
                        leading: const Icon(Icons.bookmark_rounded),
                        title: Text(template.name),
                        subtitle: Text('${tileValue.toInt()} $tileUnit'),
                        onTap: () =>
                            Navigator.of(listContext).pop(template),
                      );
                    },
                  ),
          ),
        );
      },
    );

    if (picked != null && mounted) {
      final usesKj =
          Provider.of<EnergyUnitProvider>(context, listen: false)
              .usesKilojoules;
      final displayValue =
          usesKj ? UnitCalc.kcalToKj(picked.typicalKcal) : picked.typicalKcal;
      setState(() {
        _nameController.text = picked.name;
        widget.quantityTextController.text = displayValue.toInt().toString();
      });
    }
  }

  InputDecoration _fieldDecoration(
    BuildContext context, {
    String? labelText,
    String? hintText,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final palette = isDark ? AppPalette.dark : AppPalette.light;
    final accent = Theme.of(context).colorScheme.primary;
    return InputDecoration(
      labelText: labelText,
      hintText: hintText,
      filled: true,
      fillColor: palette.surfaceMuted,
      border: OutlineInputBorder(
        borderRadius: Dimens.borderRadiusM,
        borderSide: BorderSide(color: palette.border, width: Dimens.hairline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: Dimens.borderRadiusM,
        // [fork] S552 field-edge: the hairline read about 1.1:1, 3:1 now
        // borderSide: BorderSide(color: palette.border, width: Dimens.hairline),
        borderSide: BorderSide(color: palette.textMuted, width: Dimens.hairline),
        // [/fork]
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: Dimens.borderRadiusM,
        borderSide: BorderSide(color: accent, width: 1.5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final palette = isDark ? AppPalette.dark : AppPalette.light;
    final isCustom = widget.activityEntity.isCustom;
    // For Custom activities the input field follows the user's Energy
    // unit setting — typing happens in the same unit the rest of the
    // app is showing, with conversion back to the stored kcal handled
    // at save time. For compendium activities the field stays in
    // minutes regardless of the energy unit.
    final usesKj = context.watch<EnergyUnitProvider>().usesKilojoules;
    final customUnitSuffix =
        usesKj ? S.of(context).kjLabel : S.of(context).kcalLabel;
    // [fork] S411 activity-unit-below
    final stackUnit = MediaQuery.textScalerOf(context).scale(16) / 16 >= 1.5;
    // [/fork]
    return BottomSheet(
      elevation: 0,
      backgroundColor: Colors.transparent,
      onClosing: () {},
      enableDrag: false,
      builder: (context) {
        // [fork] S410 activity-sheet-material: the sheet's colour and border
        // move to a Material, so "Save as template"'s ListTile has its ink
        // under it instead of under a coloured DecoratedBox
        // return Container(
        //   decoration: BoxDecoration(
        //     border: Border.all(color: palette.border, width: Dimens.hairline),
        //     color: palette.surface,
        //     borderRadius: const BorderRadius.only(
        //       topLeft: Radius.circular(Dimens.radiusXL),
        //       topRight: Radius.circular(Dimens.radiusXL),
        //     ),
        //     boxShadow: [
        //       BoxShadow(color: palette.shadow, blurRadius: 18, offset: const Offset(0, -6)),
        //     ],
        //   ),
        const corners = BorderRadius.only(
          topLeft: Radius.circular(Dimens.radiusXL),
          topRight: Radius.circular(Dimens.radiusXL),
        );
        return Container(
          decoration: BoxDecoration(
            borderRadius: corners,
            boxShadow: [
              BoxShadow(color: palette.shadow, blurRadius: 18, offset: const Offset(0, -6)),
            ],
          ),
          child: Material(
            color: palette.surface,
            shape: RoundedRectangleBorder(
              borderRadius: corners,
              side: BorderSide(color: palette.border, width: Dimens.hairline),
            ),
        // [/fork]
          // SafeArea(top: false) — keeps the sticky bottom Add button above
          // the gesture-nav strip on devices that don't reserve insets
          // (#156). top:false because the curved top edge handles that side.
          child: SafeArea(
            top: false,
            child: Wrap(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Dimens.spacing16,
                    Dimens.spacing32,
                    Dimens.spacing16,
                    Dimens.spacing8,
                  ),
                  child: Column(
                    children: [
                      if (isCustom) ...[
                        // [fork] S553 activity-entry-words: when this one,
                        // and not Quick add, is the way to log it
                        Padding(
                          padding: const EdgeInsets.only(
                            bottom: Dimens.spacing12,
                          ),
                          child: Text(
                            customActivityWhen,
                            style: Theme.of(context).textTheme.bodySmall,
                            textAlign: TextAlign.center,
                          ),
                        ),
                        // [/fork]
                        Row(
                          children: [
                            Expanded(
                              child: Semantics(
                                identifier: 'activity-detail-template-name-input',
                                container: true,
                                child: TextFormField(
                                  controller: _nameController,
                                  decoration: _fieldDecoration(
                                    context,
                                    labelText: S
                                        .of(context)
                                        .customActivityNameFieldLabel,
                                    hintText: S
                                        .of(context)
                                        .customActivityNameFieldHint,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: Dimens.spacing8),
                            Semantics(
                              identifier: 'activity-detail-pick-template',
                              child: IconButton(
                                tooltip: S
                                    .of(context)
                                    .customActivityPickFromTemplate,
                                icon: const Icon(Icons.bookmark_rounded),
                                onPressed: _openTemplatePicker,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: Dimens.spacing8),
                      ],
                      // [fork] S411 activity-unit-below: at 150% text and
                      // up the Unit goes under the amount, so its label
                      // ("Calories burned") has the whole width
                      // Row(
                      //   children: [
                      //     Expanded(
                      Flex(
                        direction: stackUnit ? Axis.vertical : Axis.horizontal,
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: stackUnit
                            ? CrossAxisAlignment.stretch
                            : CrossAxisAlignment.center,
                        children: [
                          // flex 0 when stacked: the column's height is open
                          Expanded(
                            flex: stackUnit ? 0 : 1,
                      // [/fork]
                            child: Semantics(
                              identifier: 'activity-detail-quantity-input',
                              container: true,
                              child: TextFormField(
                                controller: widget.quantityTextController,
                                keyboardType: TextInputType.number,
                                inputFormatters: <TextInputFormatter>[
                                  FilteringTextInputFormatter.allow(
                                    RegExp(r'[0-9]+[,.]{0,1}[0-9]*'),
                                  ),
                                  TextInputFormatter.withFunction(
                                    (oldValue, newValue) => newValue.copyWith(
                                      text: newValue.text.replaceAll(',', '.'),
                                    ),
                                  ),
                                ],
                                decoration: _fieldDecoration(
                                  context,
                                  // [fork] S553 activity-entry-words: Quick
                                  // add's name for the field; its unit is the
                                  // Unit beside it, which a "(kcal)" would cut
                                  // labelText: isCustom
                                  //     ? (usesKj
                                  //         ? S.of(context).mealEnergyLabel
                                  //         : S
                                  //             .of(context)
                                  //             .customActivityKcalLabel)
                                  //     : S.of(context).quantityLabel,
                                  labelText: isCustom
                                      ? 'Energy burned'
                                      : S.of(context).quantityLabel,
                                  // [/fork]
                                  hintText: isCustom
                                      ? S.of(context).customActivityKcalHint
                                      : null,
                                ),
                              ),
                            ),
                          ),
                          // [fork] S411 activity-unit-below
                          // const SizedBox(width: Dimens.spacing16),
                          // Expanded(
                          const SizedBox(
                            width: Dimens.spacing16,
                            height: Dimens.spacing8,
                          ),
                          Expanded(
                            flex: stackUnit ? 0 : 1,
                          // [/fork]
                            child: DropdownButtonFormField(
                              itemHeight: null,
                              decoration: _fieldDecoration(
                                context,
                                labelText: S.of(context).unitLabel,
                              ),
                              items: <DropdownMenuItem<String>>[
                                DropdownMenuItem(
                                  child: Text(
                                    isCustom
                                        ? customUnitSuffix
                                        : S.of(context).minuteShortLabel,
                                  ),
                                ),
                              ],
                              onChanged: (Object? value) {},
                            ),
                          ),
                        ],
                      ),
                      if (isCustom)
                        // Off by default: people who only ever log one-off
                        // entries shouldn't accumulate template clutter.
                        Semantics(
                          identifier: 'activity-detail-save-as-template',
                          child: CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            controlAffinity: ListTileControlAffinity.leading,
                            value: _saveAsTemplate,
                            onChanged: (value) {
                              setState(() {
                                _saveAsTemplate = value ?? false;
                              });
                            },
                            title: Text(
                              S.of(context).customActivitySaveAsTemplate,
                            ),
                          ),
                        ),
                      SizedBox(
                        width: double.infinity, // Make button full width
                        child: Semantics(
                          identifier: 'activity-detail-add-button',
                          // [fork] S288 activity-add-needs-amount: no Add at
                          // 0 or empty, which would log nothing burned
                          // child: ElevatedButton.icon(
                          child: ValueListenableBuilder(
                            valueListenable: widget.quantityTextController,
                            builder: (context, quantity, _) {
                              final amount = double.tryParse(quantity.text);
                              final none = amount == null || amount <= 0;
                              return ElevatedButton.icon(
                            // onPressed: _saving ? null : _onAddPressed,
                            onPressed: _saving || none ? null : _onAddPressed,
                            // [/fork]
                            style: ElevatedButton.styleFrom(
                              foregroundColor: Theme.of(context)
                                  .colorScheme
                                  .onPrimaryContainer,
                              backgroundColor: Theme.of(context)
                                  .colorScheme
                                  .primaryContainer,
                              shape: Dimens.shapeM,
                              padding: const EdgeInsets.symmetric(
                                vertical: Dimens.spacing16,
                              ),
                            ).copyWith(
                              elevation: ButtonStyleButton.allOrNull(0.0),
                            ),
                            icon: const Icon(Icons.add_rounded),
                            label: Text(S.of(context).addLabel),
                          // [fork] S288 activity-add-needs-amount
                              );
                            },
                          ),
                          // [/fork]
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // [fork] S410 activity-sheet-material: the Material's close
          ),
          // [/fork]
        );
      },
    );
  }
}
