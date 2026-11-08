import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/calc/unit_calc.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/util/portion_label.dart';
import 'package:opennutritracker/features/add_meal/util/portion_unit.dart';
import 'package:opennutritracker/features/meal_detail/presentation/bloc/meal_detail_bloc.dart';
import 'package:opennutritracker/features/meal_detail/util/meal_quantity_converter.dart';
import 'package:opennutritracker/fork/amounts/amount_units.dart';
import 'package:opennutritracker/fork/amounts/own_portions.dart';
import 'package:opennutritracker/fork/meal_detail/unit_change.dart';
import 'package:opennutritracker/fork/units/energy_text.dart';
import 'package:opennutritracker/generated/l10n.dart';

/// Seam S195: whether the food's page takes its amount with [AmountPicker]
/// rather than upstream's Quantity field and Unit menu. Upstream's own
/// tests of that menu set it false.
bool forkAmountPicker = true;

/// The amount of a food (S195): the number, typed or moved with − and +,
/// over a row of chips for its units, the food's portions with their
/// weights first, the user's own portions, then grams or ounces, never
/// both. A line says what the amount weighs and its energy. An amount in
/// grams that is a whole number of a portion offers it ("= 2 × slice"),
/// and "+ Portion" saves one of the user's own.
class AmountPicker extends StatelessWidget {
  final MealEntity meal;
  final String unit;
  final TextEditingController controller;
  final FocusNode? focusNode;
  final bool imperial;
  final bool enabled;
  final VoidCallback? onFieldTap;

  /// Sets the amount and the unit together, so the bloc never sees the
  /// new number in the old unit.
  final void Function(String text, String unit) onSet;

  /// Saves the user's portion and returns the food with it; null when it
  /// could not be.
  final Future<MealEntity?> Function(String label, double grams)? onAddPortion;
  final Future<MealEntity?> Function(String label)? onRemovePortion;

  /// Keeps the number when one portion is swapped for another, for a count
  /// the user or a photo gave ("3 bread" read as cups is 3 slices, not 19);
  /// a portion to a weight and back still converts.
  final bool keepCountBetweenPortions;

  const AmountPicker({
    super.key,
    required this.meal,
    required this.unit,
    required this.controller,
    required this.onSet,
    this.focusNode,
    this.imperial = false,
    this.enabled = true,
    this.onFieldTap,
    this.onAddPortion,
    this.onRemovePortion,
    this.keepCountBetweenPortions = false,
  });

  double? get _quantity =>
      double.tryParse(controller.text.trim().replaceAll(',', '.'));

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: controller,
    builder: (context, _, _) => _build(context),
  );

  Widget _build(BuildContext context) {
    final palette = paletteOf(context);
    final text = Theme.of(context).textTheme;
    final options = amountUnitOptions(meal, selected: unit, imperial: imperial);
    final quantity = _quantity;
    final fits = quantity == null
        ? null
        : portionThatFits(meal, options, unit, quantity);
    final selected = options.where((o) => o.unit == unit).firstOrNull;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Semantics(
              identifier: 'amount-minus',
              child: IconButton.filledTonal(
                tooltip: 'Less',
                onPressed: enabled && quantity != null
                    ? () => _step(up: false)
                    : null,
                icon: const Icon(Icons.remove),
              ),
            ),
            const SizedBox(width: Dimens.spacing8),
            Expanded(
              child: Semantics(
                identifier: 'amount-field',
                child: TextField(
                  key: const ValueKey('amount-field'),
                  enabled: enabled,
                  controller: controller,
                  focusNode: focusNode,
                  onTap: onFieldTap,
                  textAlign: TextAlign.center,
                  style: text.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                      RegExp(r'^\d+([.,]\d{0,2})?$'),
                    ),
                  ],
                  decoration: InputDecoration(
                    isDense: true,
                    border: const OutlineInputBorder(
                      borderRadius: Dimens.borderRadiusM,
                    ),
                    suffixText: selected == null
                        ? null
                        : _unitWord(context, selected),
                    suffixStyle: text.titleMedium?.copyWith(
                      color: palette.textMuted,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: Dimens.spacing8),
            Semantics(
              identifier: 'amount-plus',
              child: IconButton.filledTonal(
                tooltip: 'More',
                onPressed: enabled ? () => _step(up: true) : null,
                icon: const Icon(Icons.add),
              ),
            ),
          ],
        ),
        const SizedBox(height: Dimens.spacing8),
        Text(
          _summary(context, selected, quantity),
          key: const ValueKey('amount-summary'),
          textAlign: TextAlign.center,
          style: text.bodyMedium?.copyWith(color: palette.textMuted),
        ),
        const SizedBox(height: Dimens.spacing12),
        Wrap(
          spacing: Dimens.spacing8,
          runSpacing: Dimens.spacing4,
          children: [
            for (final (i, option) in options.indexed)
              Semantics(
                identifier: 'amount-unit-$i',
                child: GestureDetector(
                  onLongPress: option.own && onRemovePortion != null
                      ? () => _remove(context, option)
                      : null,
                  child: ChoiceChip(
                    key: ValueKey('amount-unit-${option.unit}'),
                    label: Text(_chipLabel(context, option)),
                    selected: option.unit == unit,
                    onSelected: enabled ? (_) => _choose(option.unit) : null,
                  ),
                ),
              ),
            if (fits != null)
              Semantics(
                identifier: 'amount-fits-portion',
                child: ActionChip(
                  key: const ValueKey('amount-fits'),
                  avatar: const Icon(Icons.swap_horiz_rounded, size: 18),
                  label: Text(
                    '= ${amountText(fits.count)} × '
                    '${_unitWord(context, fits.option)}',
                  ),
                  onPressed: enabled
                      ? () => onSet(amountText(fits.count), fits.option.unit)
                      : null,
                ),
              ),
            if (onAddPortion != null)
              Semantics(
                identifier: 'amount-add-portion',
                child: ActionChip(
                  key: const ValueKey('amount-add-portion'),
                  avatar: const Icon(Icons.bookmark_add_outlined, size: 18),
                  label: const Text('Portion'),
                  onPressed: enabled ? () => _addPortion(context) : null,
                ),
              ),
          ],
        ),
      ],
    );
  }

  void _step({required bool up}) {
    final quantity = _quantity ?? 0;
    final step = amountStep(unit, quantity);
    onSet(amountText(steppedAmount(quantity, step, up: up)), unit);
  }

  /// To [to], keeping the amount: 64 g becomes 2 slices, not 64. The unit
  /// already chosen, chosen again, confirms it.
  void _choose(String to) {
    if (to == unit ||
        keepCountBetweenPortions && isPortionUnit(unit) && isPortionUnit(to)) {
      onSet(controller.text, to);
      return;
    }
    final converted = amountInUnit(controller.text, unit, to, meal);
    final fallback = isPortionUnit(to)
        ? '1'
        : (to == UnitDropdownItem.oz.toString() ||
              to == UnitDropdownItem.flOz.toString())
        ? '3.5'
        : '100';
    onSet(converted ?? fallback, to);
  }

  Future<void> _addPortion(BuildContext context) async {
    final quantity = _quantity;
    final grams = quantity == null || !isWeightUnit(unit)
        ? null
        : convertQuantityToBaseUnit(quantity, unit, meal);
    final portion = await showDialog<(String, double)>(
      context: context,
      builder: (_) => _PortionDialog(grams: grams),
    );
    if (portion == null) return;
    final (label, weight) = portion;
    final updated = await onAddPortion!(label, weight);
    if (updated == null) return;
    final index = updated.portions.lastIndexWhere(
      (p) => p is OwnPortionEntity && p.label == label,
    );
    if (index < 0) return;
    final to = portionUnit(index);
    onSet(amountInUnit(controller.text, unit, to, updated) ?? '1', to);
  }

  Future<void> _remove(BuildContext context, AmountUnitOption option) async {
    final label = option.portionLabel!;
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove "$label"?'),
        content: const Text('Your diary keeps what was logged with it.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(S.of(context).dialogCancelLabel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (sure != true) return;
    // The amount in grams first: the portion it is in may be the one going.
    final weight = meal.isLiquid
        ? UnitDropdownItem.ml.toString()
        : UnitDropdownItem.g.toString();
    final inGrams = amountInUnit(controller.text, unit, weight, meal);
    final keptLabel =
        isPortionUnit(unit) &&
            effectivePortionIndex(unit) < meal.portions.length
        ? meal.portions[effectivePortionIndex(unit)].label
        : null;
    final updated = await onRemovePortion!(label);
    if (updated == null) return;
    if (!isPortionUnit(unit) || keptLabel == label) {
      if (isPortionUnit(unit)) onSet(inGrams ?? '100', weight);
      return;
    }
    // Another portion was chosen; its place in the list may have moved.
    final index = updated.portions.indexWhere((p) => p.label == keptLabel);
    if (index >= 0) onSet(controller.text, portionUnit(index));
  }

  /// "slice", "g", "fl oz": the unit as one word.
  String _unitWord(BuildContext context, AmountUnitOption option) {
    final s = S.of(context);
    if (option.isPortion) {
      if (option.own) return option.portionLabel!;
      return householdPortionLabel(
            option.portionLabel,
            languageCode: Localizations.localeOf(context).languageCode,
            textIsLocalized: _localized(option),
          ) ??
          s.servingLabel;
    }
    return switch (UnitDropdownItem.g.fromString(storedUnit(option.unit))) {
      UnitDropdownItem.g || UnitDropdownItem.gml => s.gramUnit,
      UnitDropdownItem.ml => s.milliliterUnit,
      UnitDropdownItem.oz => s.ozUnit,
      UnitDropdownItem.flOz => s.flOzUnit,
      UnitDropdownItem.serving => s.servingLabel,
    };
  }

  bool _localized(AmountUnitOption option) {
    if (meal.portions.isEmpty) return meal.servingSizeIsLocalized;
    final index = effectivePortionIndex(option.unit);
    return index < meal.portions.length && meal.portions[index].localized;
  }

  /// "slice · 32 g", or the weight unit's word.
  String _chipLabel(BuildContext context, AmountUnitOption option) {
    final word = _unitWord(context, option);
    if (!option.isPortion) return word;
    return '$word · ${_weight(context, option.grams!)}';
  }

  /// [grams] as the profile reads weights: "32 g" or "1.1 oz"; "ml" for a
  /// drink.
  String _weight(BuildContext context, double grams) {
    final s = S.of(context);
    if (imperial) {
      final oz = meal.isLiquid
          ? UnitCalc.mlToFlOz(grams)
          : UnitCalc.gToOz(grams);
      return '${oz.toStringAsFixed(1)} ${meal.isLiquid ? s.flOzUnit : s.ozUnit}';
    }
    return '${amountText(grams.roundToDouble())} '
        '${meal.isLiquid ? s.milliliterUnit : s.gramUnit}';
  }

  /// "2 × slice = 64 g · 158 kcal", or "158 kcal" for a weight.
  String _summary(
    BuildContext context,
    AmountUnitOption? selected,
    double? quantity,
  ) {
    if (quantity == null || quantity <= 0 || selected == null) {
      return 'Type an amount';
    }
    final grams = convertQuantityToBaseUnit(quantity, unit, meal);
    final kcal = kcalForQuantity(quantity, unit, meal);
    final energy = kcal == null ? '' : ' · ${energyText(context, kcal)}';
    if (!selected.isPortion) {
      return kcal == null ? '' : energyText(context, kcal);
    }
    return '${amountText(quantity)} × ${_unitWord(context, selected)} = '
        '${_weight(context, grams)}$energy';
  }
}

/// Names a portion of the food and its weight; prefilled with the amount
/// on the page when it is a weight.
class _PortionDialog extends StatefulWidget {
  final double? grams;

  const _PortionDialog({this.grams});

  @override
  State<_PortionDialog> createState() => _PortionDialogState();
}

class _PortionDialogState extends State<_PortionDialog> {
  final _name = TextEditingController();
  late final _grams = TextEditingController(
    text: widget.grams == null ? '' : amountText(widget.grams!.roundToDouble()),
  );

  @override
  void dispose() {
    _name.dispose();
    _grams.dispose();
    super.dispose();
  }

  (String, double)? get _value {
    final name = _name.text.trim();
    final grams = double.tryParse(_grams.text.trim().replaceAll(',', '.'));
    return name.isEmpty || grams == null || grams <= 0 ? null : (name, grams);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Add a portion'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          identifier: 'portion-name',
          child: TextField(
            key: const ValueKey('portion-name'),
            controller: _name,
            autofocus: true,
            textCapitalization: TextCapitalization.none,
            decoration: const InputDecoration(
              labelText: 'Name',
              hintText: 'slice, bowl, piece',
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
        const SizedBox(height: Dimens.spacing12),
        Semantics(
          identifier: 'portion-grams',
          child: TextField(
            key: const ValueKey('portion-grams'),
            controller: _grams,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^\d+([.,]\d{0,1})?$')),
            ],
            decoration: InputDecoration(
              labelText: 'Weight of one',
              suffixText: S.of(context).gramUnit,
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(S.of(context).dialogCancelLabel),
      ),
      TextButton(
        key: const ValueKey('portion-save'),
        onPressed: _value == null ? null : () => Navigator.pop(context, _value),
        child: const Text('Save'),
      ),
    ],
  );
}
