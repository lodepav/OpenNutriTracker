part of 'bulk_add_screen.dart';

/// One parsed row of the bulk-add list: its match, amount, unit, energy
/// and macros.
extension _BulkAddRow on _BulkAddScreenState {
  /// One food, as the Diary lists a logged one (D37): a 32 dp picture, its
  /// name and its macros under it, its energy and amount on the trailing
  /// edge. A tap opens its amount (the food page's picker, with another
  /// match a tap away). A food that needs a look shows a warning in place
  /// of its picture and a short note, and comes first. A swipe to the left
  /// leaves it out, with Undo; a left-out food says so and puts it back.
  Widget _buildRow(BuildContext context, BulkAddLoadedState state, int index) {
    final row = state.rows[index];
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final palette = paletteOf(context);
    final meal = row.meal;
    final faded = row.skipped || !row.isResolved;
    final energy = _energyLabel(context, row);
    final note = _rowNote(context, row);
    final doubtful = rowNeedsLook(row) && !row.skipped;
    final macros = faded ? null : rowMacros(row);
    final actions = _rowActions(context, index, row);
    final error = _quantityErrors[index];
    final warn = _warnColor(context);
    final radius = BorderRadius.circular(Dimens.radiusM);
    final emoji = meal == null ? null : OffKinds.emojiFor(meal);

    final thumb = Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: radius,
        color: doubtful ? warn.withValues(alpha: 0.16) : palette.surfaceMuted,
      ),
      child: doubtful
          ? Icon(Icons.priority_high_rounded, size: 18, color: warn)
          : emoji != null
          ? ExcludeSemantics(
              child: Text(emoji, style: const TextStyle(fontSize: 18)),
            )
          : Icon(Icons.restaurant_rounded, size: 18, color: palette.textMuted),
    );

    final line = Row(
      children: [
        thumb,
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // User content: shrinks before ellipsizing (A6)
              AutoSizeText(
                _rowTitle(row),
                maxLines: 2,
                minFontSize: 11,
                overflow: TextOverflow.ellipsis,
                style: textTheme.titleSmall?.copyWith(
                  color: palette.textStrong,
                  decoration: row.skipped ? TextDecoration.lineThrough : null,
                ),
              ),
              // The brand says which food this is, and shows beside a
              // warning (#847).
              if (meal?.brands != null)
                Text(
                  meal!.brands!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodySmall?.copyWith(
                    color: palette.textMuted,
                  ),
                ),
              ?note,
              // an amount the meal's Size leaves, while a size is chosen
              if (_mealScale.factor != 1 &&
                  _mealScale.isPinned(row) &&
                  _mealScale.isEligible(row))
                Text(
                  DishStrings.setByYou,
                  key: ValueKey('bulk-add-set-by-you-$index'),
                  style: textTheme.bodySmall?.copyWith(
                    color: palette.textMuted,
                  ),
                ),
              if (macros != null) ...[
                const SizedBox(height: 2),
                MacrosLine(
                  carbs: macros.carbs,
                  fat: macros.fat,
                  protein: macros.protein,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 8),
        if (!faded)
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.sizeOf(context).width * 0.4,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (energy.isNotEmpty)
                  Text(
                    energy,
                    maxLines: 1,
                    style: textTheme.labelMedium?.copyWith(
                      color: palette.textStrong,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
          ),
      ],
    );

    final card = Container(
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: radius,
        border: Border.all(
          color: doubtful ? warn.withValues(alpha: 0.6) : palette.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: Colors.transparent,
            borderRadius: radius,
            child: InkWell(
              borderRadius: radius,
              onTap: faded
                  ? null
                  : () => _openAmountPicker(index, state.usesImperialUnits),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  // faded is what was left out, not its Put back
                  child: Opacity(opacity: row.skipped ? 0.55 : 1, child: line),
                ),
              ),
            ),
          ),
          // − [the amount] +, under the name, as the proposal had it
          if (!faded)
            Padding(
              padding: const EdgeInsets.fromLTRB(52, 0, 12, 6),
              child: _buildAmountRow(context, state, index, row),
            ),
          // the one amount a photo's review asks about
          if (_amountQuestion case final question?
              when !faded && question.isFor(row))
            Padding(
              padding: const EdgeInsets.fromLTRB(52, 0, 12, 6),
              child: Builder(
                builder: (context) {
                  _sayAmountAnswer(context);
                  return AmountQuestionView(
                    question: question,
                    row: row,
                    index: index,
                    onChosen: (choice) => _answerAmount(index, choice),
                  );
                },
              ),
            ),
          if (row.skipped || error != null || actions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(52, 0, 12, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (row.skipped)
                    TextButton.icon(
                      key: ValueKey('bulk-add-put-back-$index'),
                      onPressed: () => _toggleSkipped(index, row),
                      icon: const Icon(Icons.undo_rounded, size: 18),
                      label: const Text('Left out · Put back'),
                    ),
                  if (error != null)
                    Text(
                      _quantityErrorText(context, error),
                      style: textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
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
        ],
      ),
    );

    // A swipe leaves the food out and the row stays, faded, to put it
    // back; screen readers get the same as an action.
    return Semantics(
      customSemanticsActions: {
        CustomSemanticsAction(
          label: row.skipped ? 'Put back' : 'Leave out',
        ): () =>
            _toggleSkipped(index, row),
      },
      child: Dismissible(
        key: ValueKey('bulk-add-row-$index'),
        direction: row.skipped
            ? DismissDirection.none
            : DismissDirection.endToStart,
        background: Container(
          alignment: AlignmentDirectional.centerEnd,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            color: theme.colorScheme.errorContainer,
            borderRadius: radius,
          ),
          child: Text(
            'Leave out',
            style: textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onErrorContainer,
            ),
          ),
        ),
        confirmDismiss: (_) async {
          _leaveOut(index, row);
          return false;
        },
        child: card,
      ),
    );
  }

  /// The amount as the food page says it: "3 × potato · 234 g", "150 g",
  /// or a prompt to set one. In imperial units a weight reads as the Diary
  /// will show it once logged, "12.3 oz": the model's grams are the
  /// app's, not the user's.
  String _amountLabel(BuildContext context, BulkAddRow row, bool imperial) {
    final quantity = double.tryParse(row.amountText.replaceAll(',', '.'));
    final unit = row.effectiveUnit;
    if (quantity == null || quantity <= 0) return 'Set the amount';
    if (isPortionUnit(unit)) {
      return '${amountText(quantity)} × ${_unitLabel(context, unit, row)}'
          '${_portionWeightLabel(context, row, imperial).replaceFirst('≈', ' ·')}';
    }
    // only where it is edited in that unit too
    if (row.meal case final meal?
        when imperial &&
            (_shownEditUnit(row, true) != null ||
                diaryUnit(meal, true).unit == unit)) {
      return diaryAmountText(
        convertQuantityToBaseUnit(quantity, unit, meal),
        meal,
        true,
      );
    }
    return '${amountText(quantity)} ${_unitLabel(context, unit, row)}';
  }

  /// The unit an imperial profile edits [row]'s weight in, the one its
  /// amount is shown in ("oz" for grams); null when the row is shown in
  /// its own unit. What the user types or steps is in the unit shown.
  String? _shownEditUnit(BulkAddRow row, bool imperial) =>
      shownEditUnit(row, imperial);

  /// The amber of a card that needs a look: the tertiary colour, which is
  /// the app's warning hue.
  Color _warnColor(BuildContext context) =>
      Theme.of(context).colorScheme.tertiary;

  /// Leaves the food out, with Undo on the snackbar.
  void _leaveOut(int index, BulkAddRow row) {
    _toggleSkipped(index, row);
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Left out: ${_rowTitle(row)}'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () {
              final current = _bloc.state;
              if (current is BulkAddLoadedState &&
                  index < current.rows.length &&
                  current.rows[index].skipped) {
                _toggleSkipped(index, current.rows[index]);
              }
            },
          ),
        ),
      );
  }

  /// What is doubtful about the row, the gravest first: no match, an
  /// uncertain one, a count the app could not read, an amount the app
  /// chose; as a short amber note. A breakdown under way, or the dish an
  /// ingredient belongs to, when nothing is.
  Widget? _rowNote(BuildContext context, BulkAddRow row) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final warn = _warnColor(context);
    Widget pill(String text, Color color) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: theme.textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
    Widget line(String text, Color color) =>
        Text(text, style: theme.textTheme.bodySmall?.copyWith(color: color));
    if (!row.isResolved) {
      return pill(S.of(context).bulkAddNoMatchLabel, scheme.error);
    }
    if (_dishBreakdown.isPending(row)) {
      return line(DishStrings.breakingDown, scheme.tertiary);
    }
    if (row.isLowConfidence) {
      return pill(S.of(context).bulkAddUncertainLabel, warn);
    }
    if (row.amountNeedsCheck) {
      return pill(S.of(context).bulkAddCheckAmountLabel, warn);
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
        when _separateDishes.contains(ingredient.group)) {
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
    final label = _amountLabel(context, row, state.usesImperialUnits);
    void step({required bool up}) {
      // in the unit shown: an ounce, not 10 g of a row shown in ounces
      final shown = _shownEditUnit(row, state.usesImperialUnits);
      final converted = shown == null
          ? null
          : amountInUnit(row.amountText, row.effectiveUnit, shown, row.meal!);
      final unit = shown ?? row.effectiveUnit;
      // nothing to convert (empty or 0): up from nothing, in the unit shown
      final from = shown == null
          ? quantity ?? 0
          : double.tryParse(converted ?? '') ?? 0;
      final next = amountText(
        steppedAmount(from, amountStep(unit, from), up: up),
      );
      if (_quantityErrors.containsKey(index)) _clearQuantityError(index);
      _pinRow(index);
      _bloc.add(
        shown == null
            ? ChangeRowAmountEvent(index, next)
            : SetRowInShownUnitEvent(index, shown, next),
      );
    }

    return Row(
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
            onPressed: () => _openAmountPicker(index, state.usesImperialUnits),
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
    // opened in the unit the row is shown in, so the number typed is in it
    final shown = _shownEditUnit(row, imperial);
    final unit = shown ?? row.effectiveUnit;
    final text = shown == null
        ? row.amountText
        : amountInUnit(row.amountText, row.effectiveUnit, shown, base) ??
              row.amountText;

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
      if (_quantityErrors.containsKey(index)) _clearQuantityError(index);
      _pinRow(index);
      // typed in the unit shown, which the user did not choose: the row
      // asks to check its amount still, as it would in metric units
      if (!unitChosen &&
          to == shown &&
          current.rows[index].effectiveUnit != to) {
        _bloc.add(SetRowInShownUnitEvent(index, to, amount));
        return;
      }
      if (unitChosen || current.rows[index].effectiveUnit != to) {
        _bloc.add(ChangeRowUnitEvent(index, to));
      }
      _bloc.add(ChangeRowAmountEvent(index, amount));
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheet) => _RowAmountSheet(
        base: base,
        meal: meal,
        unit: unit,
        text: text,
        imperial: imperial,
        send: send,
        // another of the foods the search found, from the sheet (D37)
        onOtherMatch: row.resolved.candidates.length > 1
            ? () {
                Navigator.pop(sheet);
                _showCandidatePicker(index, row);
              }
            : null,
      ),
    );
  }

  /// "≈ 120 g" under a count of portions, "≈ 4.2 oz" as the Diary says it
  /// in imperial units; empty for a weight or volume.
  String _portionWeightLabel(
    BuildContext context,
    BulkAddRow row,
    bool imperial,
  ) {
    final meal = row.meal;
    if (meal == null || !isPortionUnit(row.effectiveUnit)) return '';
    final quantity = double.tryParse(row.amountText.replaceAll(',', '.'));
    if (quantity == null || quantity <= 0) return '';
    final base = convertQuantityToBaseUnit(quantity, row.effectiveUnit, meal);
    if (imperial) return '≈ ${diaryAmountText(base, meal, true)}';
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

  /// Picks another match for the food; null when the search found one.
  final VoidCallback? onOtherMatch;

  const _RowAmountSheet({
    required this.base,
    required this.meal,
    required this.unit,
    required this.text,
    required this.imperial,
    required this.send,
    this.onOtherMatch,
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
        Row(
          children: [
            if (widget.onOtherMatch case final other?) ...[
              Expanded(
                child: OutlinedButton.icon(
                  key: const ValueKey('bulk-add-other-match'),
                  onPressed: other,
                  icon: const Icon(Icons.swap_horiz_rounded),
                  label: const Text('Other match'),
                ),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: FilledButton(
                key: const ValueKey('bulk-add-amount-done'),
                onPressed: () => Navigator.pop(context),
                child: const Text('Done'),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}
