part of 'bulk_add_screen.dart';

/// One parsed row of the bulk-add list: its match, amount, unit and
/// energy.
extension _BulkAddRow on _BulkAddScreenState {
  /// One food (D35): a check to keep it, its name (a tap picks another
  /// match) and energy, what is doubtful about it, and its amount as the
  /// food page shows one, − and + either side of a button that opens the
  /// amount picker.
  Widget _buildRow(BuildContext context, BulkAddLoadedState state, int index) {
    final row = state.rows[index];
    final theme = Theme.of(context);
    final palette = paletteOf(context);
    final meal = row.meal;
    final faded = row.skipped || !row.isResolved;
    final energy = _energyLabel(context, row);
    final note = _rowNote(context, row);
    final actions = _rowActions(context, index, row);
    final error = _quantityErrors[index];

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 16, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Checkbox(
            key: ValueKey('bulk-add-keep-$index'),
            value: !row.skipped,
            onChanged: (_) => _toggleSkipped(index, row),
          ),
          Expanded(
            child: Opacity(
              opacity: row.skipped ? 0.5 : 1,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // the name is a 48 dp tap target that picks another match
                  InkWell(
                    onTap: row.isResolved
                        ? () => _showCandidatePicker(index, row)
                        : null,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 48),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // User content: shrinks before ellipsizing;
                                // a long database name takes up to three
                                // lines (A6)
                                AutoSizeText(
                                  _rowTitle(row),
                                  maxLines: 3,
                                  minFontSize: 12,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    decoration: row.skipped
                                        ? TextDecoration.lineThrough
                                        : null,
                                  ),
                                ),
                                // The brand says which food this is, and
                                // shows even beside a warning (#847).
                                if (meal?.brands != null)
                                  Text(
                                    meal!.brands!,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: palette.textMuted,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          if (energy.isNotEmpty && !faded) ...[
                            const SizedBox(width: 8),
                            Text(energy, style: theme.textTheme.titleSmall),
                          ],
                        ],
                      ),
                    ),
                  ),
                  ?note,
                  if (!faded) _buildAmountRow(context, state, index, row),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        _quantityErrorText(context, error),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ),
                  if (actions.isNotEmpty)
                    Wrap(
                      spacing: 4,
                      children: [
                        for (final action in actions)
                          TextButton(
                            onPressed: action.onPressed,
                            child: Text(action.label),
                          ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// What is doubtful about the row, the gravest first: no match, an
  /// uncertain one, a count the app could not read, an amount the app
  /// chose. A breakdown under way, or the dish an ingredient belongs to,
  /// when nothing is.
  Widget? _rowNote(BuildContext context, BulkAddRow row) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    Widget line(String text, Color color, [IconData? icon]) => Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                // orange text is too faint on the light theme: the colour
                // goes on the icon, the words stay in the body colour
                color: icon == null ? color : null,
              ),
            ),
          ),
        ],
      ),
    );
    if (!row.isResolved) {
      return line(S.of(context).bulkAddNoMatchLabel, scheme.error);
    }
    if (_dishBreakdown.isPending(row)) {
      return line(DishStrings.breakingDown, scheme.tertiary);
    }
    if (row.isLowConfidence) {
      return line(
        S.of(context).bulkAddUncertainLabel,
        scheme.tertiary,
        Icons.warning_amber_rounded,
      );
    }
    if (row.amountNeedsCheck) {
      return line(
        S.of(context).bulkAddCheckAmountLabel,
        scheme.tertiary,
        Icons.straighten_rounded,
      );
    }
    // Only that the number is the app's, not the user's (#864): muted.
    if (row.amountIsProvisional) {
      return line(
        S.of(context).bulkAddDefaultAmountLabel,
        scheme.onSurfaceVariant,
      );
    }
    // under its dish's heading it needs no line of its own
    if (row.dishIngredient case final ingredient?
        when !_separateDishes.contains(ingredient.group)) {
      return null;
    } else if (row.dishIngredient case final ingredient?) {
      return line(DishStrings.ingredientOf(ingredient.dish), scheme.tertiary);
    }
    return null;
  }

  void _toggleSkipped(int index, BulkAddRow row) {
    // The portion typed is no longer the dish's: its field follows the
    // rows again, and the next edit scales those left.
    _portionBase.remove(row.dishIngredient?.group);
    _bloc.add(ToggleRowSkippedEvent(index));
  }

  /// What the row is called, on screen and in any message about it: the
  /// matched food, or the words the user typed when nothing matched.
  String _rowTitle(BulkAddRow row) =>
      row.meal?.name ?? row.resolved.parsed.query;

  /// The row's actions besides keeping it: a quick add for no match, the
  /// breakdown of a doubtful dish, and a separate dish's recipe and undo.
  List<({String label, VoidCallback onPressed})> _rowActions(
    BuildContext context,
    int index,
    BulkAddRow row,
  ) => [
    if (!row.isResolved)
      (
        label: S.of(context).quickAddCardLabel,
        onPressed: () => _showQuickAdd(row),
      ),
    // on demand, for a doubtful row; and once per
    // breakdown, saving it as a recipe
    if (_dishBreakdown.canBreakDown(row) && !row.skipped)
      (label: DishStrings.breakDownAction, onPressed: () => _breakDown(row)),
    // a dish logged as one has these under its rows instead
    if (_bloc.state case BulkAddLoadedState(:final rows)
        when isFirstOfDishGroup(rows, index) &&
            _separateDishes.contains(row.dishIngredient!.group)) ...[
      (
        label: DishStrings.saveAsRecipe,
        onPressed: () => _saveDishRecipe(row.dishIngredient!.group),
      ),
      (
        label: DishStrings.logAsOneDish,
        onPressed: () =>
            _logDishSeparately(row.dishIngredient!.group, separately: false),
      ),
    ],
  ];

  /// − [the amount] +: the amount as the food page says it ("3 × potato ·
  /// 234 g", "150 g"), a tap opening the amount picker, − and + moving it
  /// by a portion or 10 g.
  Widget _buildAmountRow(
    BuildContext context,
    BulkAddLoadedState state,
    int index,
    BulkAddRow row,
  ) {
    final quantity = double.tryParse(row.amountText.replaceAll(',', '.'));
    final unit = row.effectiveUnit;
    final label = quantity == null || quantity <= 0
        ? 'Set the amount'
        : isPortionUnit(unit)
        ? '${amountText(quantity)} × ${_unitLabel(context, unit, row)}'
              '${_portionWeightLabel(context, row).replaceFirst('≈', ' ·')}'
        : '${amountText(quantity)} ${_unitLabel(context, unit, row)}';
    void step({required bool up}) {
      final from = quantity ?? 0;
      final next = steppedAmount(from, amountStep(unit, from), up: up);
      if (_quantityErrors.containsKey(index)) _clearQuantityError(index);
      _bloc.add(ChangeRowAmountEvent(index, amountText(next)));
    }

    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 4),
      child: Row(
        children: [
          IconButton.filledTonal(
            key: ValueKey('bulk-add-less-$index'),
            tooltip: 'Less',
            visualDensity: VisualDensity.compact,
            onPressed: quantity == null ? null : () => step(up: false),
            icon: const Icon(Icons.remove),
          ),
          const SizedBox(width: 4),
          Flexible(
            child: OutlinedButton(
              key: ValueKey('bulk-add-unit-$index'),
              onPressed: () =>
                  _openAmountPicker(index, state.usesImperialUnits),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                shape: const StadiumBorder(),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const Icon(Icons.arrow_drop_down_rounded),
                ],
              ),
            ),
          ),
          const SizedBox(width: 4),
          IconButton.filledTonal(
            key: ValueKey('bulk-add-more-$index'),
            tooltip: 'More',
            visualDensity: VisualDensity.compact,
            onPressed: () => step(up: true),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }

  /// Says which of the three failures this is. They used to render
  /// identically, as the field's own name.
  String _quantityErrorText(
    BuildContext context,
    BulkAddQuantityError error,
  ) => switch (error) {
    BulkAddQuantityError.malformed => S.of(context).bulkAddRowQuantityInvalid,
    BulkAddQuantityError.tooSmall => S.of(context).bulkAddRowQuantityTooSmall,
    BulkAddQuantityError.tooLarge =>
      S.of(context).bulkAddRowQuantityTooLarge(bulkAddMaxQuantity),
  };

  /// The row's amount in the food page's picker, in a sheet: each change
  /// reaches the row as it is made. The user's own portions are not among
  /// the row's units, so one of those reaches it as its weight.
  Future<void> _openAmountPicker(int index, bool imperial) async {
    final start = _bloc.state;
    if (start is! BulkAddLoadedState || index >= start.rows.length) return;
    final row = start.rows[index];
    final base = row.meal;
    if (base == null) return;
    final meal = withOwnPortions(base, await OwnPortions.current.of(base));
    if (!mounted) return;

    /// The amount to the row; with [unitChosen], the unit too, which
    /// answers the row's "check the amount" even when it is the one shown.
    void send(String text, String unit, MealEntity meal, bool unitChosen) {
      final current = _bloc.state;
      if (current is! BulkAddLoadedState || index >= current.rows.length) {
        return;
      }
      final allowed = current.rows[index].allowedUnits;
      var (amount, to) = (text, unit);
      if (!allowed.contains(to)) {
        final weight = meal.isLiquid
            ? UnitDropdownItem.ml.toString()
            : UnitDropdownItem.g.toString();
        to = allowed.contains(weight)
            ? weight
            : UnitDropdownItem.gml.toString();
        amount = amountInUnit(text, unit, to, meal) ?? text;
      }
      if (unitChosen || current.rows[index].effectiveUnit != to) {
        _bloc.add(ChangeRowUnitEvent(index, to));
      }
      if (_quantityErrors.containsKey(index)) _clearQuantityError(index);
      _bloc.add(ChangeRowAmountEvent(index, amount));
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => _RowAmountSheet(
        base: base,
        meal: meal,
        unit: row.effectiveUnit,
        text: row.amountText,
        imperial: imperial,
        send: send,
      ),
    );
  }

  /// "≈ 120 g" under a count of portions; empty for a weight or volume.
  String _portionWeightLabel(BuildContext context, BulkAddRow row) {
    final meal = row.meal;
    if (meal == null || !isPortionUnit(row.effectiveUnit)) return '';
    final quantity = double.tryParse(row.amountText.replaceAll(',', '.'));
    if (quantity == null || quantity <= 0) return '';
    final base = convertQuantityToBaseUnit(quantity, row.effectiveUnit, meal);
    final s = S.of(context);
    return '≈ ${base.round()} ${meal.isLiquid ? s.milliliterUnit : s.gramUnit}';
  }

  /// Empty when the amount is not yet usable or the food has no energy value.
  String _energyLabel(BuildContext context, BulkAddRow row) {
    final meal = row.meal;
    if (meal == null) return '';
    final quantity = double.tryParse(row.amountText.replaceAll(',', '.'));
    if (quantity == null || quantity <= 0) return '';
    final kcal = kcalForQuantity(quantity, row.effectiveUnit, meal);
    return kcal == null ? '' : EnergyDisplay.formatWithUnit(context, kcal);
  }

  /// Takes the row because one of the six units is not a fixed word: the
  /// food names its own portion, and "3 slice" says what "3 serving" only
  /// implies. Display only — the value behind it stays `serving` (#864).
  String _unitLabel(BuildContext context, String unit, BulkAddRow row) {
    // A named portion shows its own word — "slice", "cup" — which is the
    // whole point of offering more than one. Only when the text is in the
    // reader's language: the backend says per portion whether it is, and
    // showing English to the other eight locales is what #966 gated.
    final portions = row.meal?.portions ?? const [];
    if (isPortionUnit(unit) && portions.isNotEmpty) {
      final index = effectivePortionIndex(unit);
      if (index < portions.length) {
        final portion = portions[index];
        final label = householdPortionLabel(
          portion.label,
          languageCode: Localizations.localeOf(context).languageCode,
          textIsLocalized: portion.localized,
        );
        if (label != null) return label;
      }
    }
    return _fixedUnitLabel(context, unit, row);
  }

  String _fixedUnitLabel(BuildContext context, String unit, BulkAddRow row) =>
      switch (UnitDropdownItem.g.fromString(storedUnit(unit))) {
        UnitDropdownItem.g => S.of(context).gramUnit,
        UnitDropdownItem.ml => S.of(context).milliliterUnit,
        // "g", as the food page's picker says it (S195)
        UnitDropdownItem.gml => S.of(context).gramUnit,
        UnitDropdownItem.oz => S.of(context).ozUnit,
        UnitDropdownItem.flOz => S.of(context).flOzUnit,
        UnitDropdownItem.serving =>
          householdPortionLabel(
                row.meal?.servingSize,
                languageCode: Localizations.localeOf(context).languageCode,
                textIsLocalized: row.meal?.servingSizeIsLocalized ?? false,
              ) ??
              S.of(context).servingLabel,
      };
}

/// The row's amount in the food page's picker (S195, D35). The sheet holds
/// its own field, disposed with it rather than while it closes.
class _RowAmountSheet extends StatefulWidget {
  final MealEntity base;
  final MealEntity meal;
  final String unit;
  final String text;
  final bool imperial;
  final void Function(String text, String unit, MealEntity meal, bool chosen)
  send;

  const _RowAmountSheet({
    required this.base,
    required this.meal,
    required this.unit,
    required this.text,
    required this.imperial,
    required this.send,
  });

  @override
  State<_RowAmountSheet> createState() => _RowAmountSheetState();
}

class _RowAmountSheetState extends State<_RowAmountSheet> {
  late final _controller = TextEditingController(text: widget.text);
  late String _unit = widget.unit;
  late MealEntity _meal = widget.meal;
  var _setting = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_typed);
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_typed)
      ..dispose();
    super.dispose();
  }

  void _typed() {
    if (!_setting) widget.send(_controller.text, _unit, _meal, false);
  }

  Future<MealEntity> _reload() async {
    final own = await OwnPortions.current.of(widget.base);
    if (mounted) setState(() => _meal = withOwnPortions(widget.base, own));
    return _meal;
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      16,
      0,
      16,
      16 + MediaQuery.viewInsetsOf(context).bottom,
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          widget.base.name ?? '',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 16),
        AmountPicker(
          meal: _meal,
          unit: _unit,
          controller: _controller,
          imperial: widget.imperial,
          keepCountBetweenPortions: true,
          onSet: (text, to) {
            _unit = to;
            _setting = true;
            _controller.text = text;
            _setting = false;
            widget.send(text, to, _meal, true);
            setState(() {});
          },
          onAddPortion: (label, grams) async {
            await OwnPortions.current.add(widget.base, label, grams);
            return _reload();
          },
          onRemovePortion: (label) async {
            await OwnPortions.current.remove(widget.base, label);
            return _reload();
          },
        ),
        const SizedBox(height: 16),
        FilledButton(
          key: const ValueKey('bulk-add-amount-done'),
          onPressed: () => Navigator.pop(context),
          child: const Text('Done'),
        ),
      ],
    ),
  );
}
