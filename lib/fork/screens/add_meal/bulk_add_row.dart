part of 'bulk_add_screen.dart';

/// One parsed row of the bulk-add list: its match, amount, unit and
/// energy.
extension _BulkAddRow on _BulkAddScreenState {
  Widget _buildRow(BuildContext context, BulkAddLoadedState state, int index) {
    final row = state.rows[index];
    final theme = Theme.of(context);
    final meal = row.meal;

    final title = _rowTitle(row);
    final faded = row.skipped || !row.isResolved;

    // Both rows below decide between one line and two, so they need the width
    // they were actually given rather than the screen's.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final available = constraints.maxWidth;
          final actions = _rowActions(context, index, row);
          // A `TextButton` is its label plus Material's padding, floored at
          // its minimum size. At 2x on a 320dp screen the German "skip"
          // alone measures 353px of the 288 this row gets, and a `Row`
          // answers that by squeezing the name to nothing and overflowing
          // by 65 anyway. #824.
          final actionsWidth = actions.fold<double>(
            0,
            (sum, action) => sum + _actionWidth(context, action.label),
          );
          // Below this the name has no share of the line worth reading, so
          // the controls take a line of their own and leave it the width.
          final stacked =
              available - actionsWidth <
              MediaQuery.textScalerOf(context).scale(72);

          final buttons = [
            for (final action in actions)
              TextButton(
                onPressed: action.onPressed,
                child: Text(action.label),
              ),
          ];

          final titleBlock = InkWell(
            onTap: row.isResolved
                ? () => _showCandidatePicker(index, row)
                : null,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // User content: shrink to fit before ellipsizing; a long
                // database name takes up to three lines (A6)
                AutoSizeText(
                  title,
                  maxLines: 3,
                  minFontSize: 12,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    decoration: row.skipped ? TextDecoration.lineThrough : null,
                  ),
                ),
                // The brand names *which* food this is; a warning only
                // qualifies it. They were alternatives, and that inverted
                // the intent below: the more doubtful a row looked, the
                // less identifying detail it showed. #847 found the cost
                // on a Pixel 6 — "Spiegeleier" resolved to Haribo's gummy
                // sweets, and because the row also carried a unit warning,
                // the word "Haribo" never reached the screen. The one
                // field that gives the mistake away is the one a warning
                // used to hide, so it is now unconditional.
                if (meal?.brands != null)
                  Text(meal!.brands!, style: theme.textTheme.bodySmall),
                // in progress, or an AI ingredient
                if (_dishBreakdown.isPending(row))
                  Text(
                    DishStrings.breakingDown,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.tertiary,
                    ),
                  )
                // under its dish's heading it needs no line of its own
                else if (row.dishIngredient case final ingredient?
                    when _separateDishes.contains(ingredient.group))
                  Text(
                    DishStrings.ingredientOf(ingredient.dish),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.tertiary,
                    ),
                  ),
                if (!row.isResolved)
                  Text(
                    S.of(context).bulkAddNoMatchLabel,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  )
                else if (row.isLowConfidence)
                  // orange text is too faint
                  // to read on the light theme, so the orange goes on an
                  // icon and the words are in the body colour
                  Row(
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        size: 16,
                        color: theme.colorScheme.tertiary,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          S.of(context).bulkAddUncertainLabel,
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ],
                  )
                // A bare count the app could not interpret. Shown
                // below a doubtful match, because a wrong food
                // matters more than a wrong unit on the right one.
                else if (row.amountNeedsCheck)
                  Text(
                    S.of(context).bulkAddCheckAmountLabel,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.tertiary,
                    ),
                  )
                // Last, and the quietest of the four. The others say
                // something is probably wrong; this only says the number
                // is the app's rather than the user's, so it takes the
                // muted surface colour instead of an accent. #864.
                else if (row.amountIsProvisional)
                  Text(
                    S.of(context).bulkAddDefaultAmountLabel,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          );
          // the name is a 48 dp tap target; a skipped one fades, but not
          // its Include, which has to stay readable
          final forkTitle = Opacity(
            opacity: row.skipped ? 0.5 : 1.0,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: titleBlock,
            ),
          );

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (stacked)
                // Stretched, so each label is bounded by the line rather
                // than by whatever is left of it.
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [forkTitle, ...buttons],
                )
              else
                // Unchanged wherever they fit, which is every ordinary
                // text size: name on the left, controls on the right.
                Row(
                  children: [
                    Expanded(child: forkTitle),
                    ...buttons,
                  ],
                ),
              if (!faded)
                _buildAmountRow(context, state, index, row, available),
            ],
          );
        },
      ),
    );
  }

  /// What the row is called, on screen and in any message about it: the
  /// matched food, or the words the user typed when nothing matched.
  String _rowTitle(BulkAddRow row) =>
      row.meal?.name ?? row.resolved.parsed.query;

  /// The controls on a row, as label and action rather than as widgets, so
  /// that what is measured cannot drift from what is drawn.
  List<({String label, VoidCallback onPressed})> _rowActions(
    BuildContext context,
    int index,
    BulkAddRow row,
  ) => [
    if (!row.isResolved)
      (label: S.of(context).quickAddCardLabel, onPressed: _showQuickAdd),
    // on demand, for a doubtful row; and once per
    // breakdown, saving it as a recipe
    if (_dishBreakdown.canBreakDown(row))
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
    (
      label: row.skipped
          ? S.of(context).bulkAddIncludeLabel
          : S.of(context).bulkAddSkipLabel,
      onPressed: () => _bloc.add(ToggleRowSkippedEvent(index)),
    ),
  ];

  /// The width a text button needs for [label]: the label itself, Material's
  /// horizontal padding at its widest, and never less than the narrowest a
  /// button is allowed to be.
  double _actionWidth(BuildContext context, String label) => math.max(
    _minButtonWidth,
    _textWidth(context, label, Theme.of(context).textTheme.labelLarge) +
        _buttonPadding,
  );

  static const _buttonPadding = 24.0;
  static const _minButtonWidth = 64.0;

  /// The width [text] needs at the current text scale.
  ///
  /// Measured rather than estimated. These rows have to choose between one
  /// line and two, and an estimate wide enough to be safe for the widest
  /// possible glyphs is about twice too wide for a real font — it would
  /// stack the controls on screens where they comfortably fit.
  double _textWidth(BuildContext context, String text, TextStyle? style) =>
      (TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout()).width;

  Widget _buildAmountRow(
    BuildContext context,
    BulkAddLoadedState state,
    int index,
    BulkAddRow row,
    double available,
  ) {
    final controller = _amountControllers.putIfAbsent(
      index,
      () => TextEditingController(text: row.amountText),
    );
    if (controller.text != row.amountText) {
      controller.text = row.amountText;
    }

    final theme = Theme.of(context);
    // The quantity box was a flat 110px while every label beside it grew with
    // the text scale, so at 2x on a 320dp screen this row wanted 532px of a
    // 288px slot and overflowed by 244. It scales now, like the other fixed
    // widths in the app. #824.
    final fieldWidth = MediaQuery.textScalerOf(context).scale(110);
    final unitWidth = _unitDropdownWidth(context, row);
    final energyText = _energyLabel(context, row);
    final energyWidth = _textWidth(
      context,
      energyText,
      theme.textTheme.titleSmall,
    );
    // Nothing flexes 532px into 288px. Where the three do not fit, they take
    // a line each rather than share one: the unit is a whole word in some
    // locales, and a clipped unit is not a narrower reading of the amount,
    // it is a wrong one.
    final stacked = available < fieldWidth + 12 + unitWidth + 8 + energyWidth;

    final field = TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      // Same shape the manual-entry field enforces, so the two paths accept
      // exactly the same input.
      inputFormatters: [
        FilteringTextInputFormatter.allow(bulkAddQuantityPattern),
      ],
      decoration: InputDecoration(
        labelText: S.of(context).quantityLabel,
        isDense: true,
        border: const OutlineInputBorder(),
      ),
      onChanged: (value) {
        // The complaint belonged to the text that is no longer there.
        // Re-checking as they type would put it back mid-keystroke, which
        // is the thing `amountText` is a String to avoid; the next submit
        // asks again.
        if (_quantityErrors.containsKey(index)) _clearQuantityError(index);
        _bloc.add(ChangeRowAmountEvent(index, value));
      },
    );

    final unit = DropdownButton<String>(
      value: row.effectiveUnit,
      items: _unitItems(context, row),
      // Only when it has a line to fill; on a shared line it takes the width
      // its longest unit needs, which is what `stacked` was measured against.
      isExpanded: stacked,
      onChanged: (value) {
        if (value != null) _bloc.add(ChangeRowUnitEvent(index, value));
      },
    );

    // A count of portions, and the weight it was taken to be.
    final grams = _portionWeightLabel(context, row);
    final energy = grams.isEmpty
        ? Text(energyText, style: theme.textTheme.titleSmall)
        : Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(energyText, style: theme.textTheme.titleSmall),
              Text(
                grams,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          );

    final error = _quantityErrors[index];

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (stacked)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                field,
                const SizedBox(height: 8),
                unit,
                const SizedBox(height: 4),
                Align(alignment: AlignmentDirectional.centerEnd, child: energy),
              ],
            )
          // Unchanged wherever it fits, which is every ordinary text size:
          // the figure stays on the same line, pushed to the trailing edge.
          else
            Row(
              children: [
                SizedBox(width: fieldWidth, child: field),
                const SizedBox(width: 12),
                unit,
                const Spacer(),
                energy,
              ],
            ),
          // The whole width, not the field's. `errorText` would put this
          // inside a 110px box, where every one of the three sentences
          // ellipsizes to nothing worth reading — and the decimal rule, the
          // one constraint stated nowhere else in the UI, is the longest of
          // them.
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

  /// What the unit dropdown needs to show its longest unit without clipping
  /// it: the dropdown sizes itself to its widest item, plus its arrow.
  double _unitDropdownWidth(BuildContext context, BulkAddRow row) {
    final style = Theme.of(context).textTheme.titleMedium;
    var widest = 0.0;
    for (final unit in row.allowedUnits) {
      widest = math.max(
        widest,
        _textWidth(context, _unitLabel(context, unit, row), style),
      );
    }
    return widest + _dropdownArrowWidth;
  }

  static const _dropdownArrowWidth = 24.0;

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

  List<DropdownMenuItem<String>> _unitItems(
    BuildContext context,
    BulkAddRow row,
  ) => [
    for (final unit in row.allowedUnits)
      DropdownMenuItem(
        value: unit,
        child: Text(
          _unitLabel(context, unit, row),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
  ];

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
        UnitDropdownItem.gml => S.of(context).gramMilliliterUnit,
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
