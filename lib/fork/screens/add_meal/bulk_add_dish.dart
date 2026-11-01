part of 'bulk_add_screen.dart';

/// A dish's heading and actions in the review list (canvas "AI dish A",
/// D24): the rows of one dish logged as one entry, at a portion that
/// scales them all.
extension _BulkAddDish on _BulkAddScreenState {
  Widget _buildDishHeading(
    BuildContext context,
    BulkAddLoadedState state,
    DishHeading heading,
  ) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final group = heading.group;
    final folded = _foldedDishes.contains(group);
    final grams = dishPortion(state.rows, heading.members);
    final controller = _portionControllers.putIfAbsent(
      group,
      () => TextEditingController(),
    );
    // the rows' sum, except while the user is typing the portion
    if (!_portionBase.containsKey(group)) {
      final text = grams > 0 ? grams.round().toString() : '';
      if (controller.text != text) controller.text = text;
    }
    final dish = state.rows[heading.members.first].dishIngredient!.dish;
    return Container(
      color: scheme.secondaryContainer,
      padding: const EdgeInsets.fromLTRB(4, 8, 16, 8),
      child: Row(
        children: [
          Semantics(
            identifier: 'bulk-add-dish-fold',
            child: IconButton(
              tooltip: folded ? DishStrings.showFoods : DishStrings.hideFoods,
              icon: Icon(
                folded ? Icons.expand_more_rounded : Icons.expand_less_rounded,
              ),
              onPressed: () => _toggleDishFolded(group),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AutoSizeText(
                  dish.isEmpty
                      ? dish
                      : dish[0].toUpperCase() + dish.substring(1),
                  maxLines: 2,
                  minFontSize: 12,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: scheme.onSecondaryContainer,
                  ),
                ),
                Text(
                  DishStrings.dishSummary(
                    heading.members.length,
                    EnergyDisplay.formatWithUnit(
                      context,
                      dishKcal(state.rows, heading.members),
                    ),
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSecondaryContainer,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: MediaQuery.textScalerOf(context).scale(110),
            child: Semantics(
              identifier: 'bulk-add-dish-portion',
              child: Focus(
                onFocusChange: (focused) {
                  if (!focused) return _endPortionEdit(group);
                  // a new portion replaces the old, not a digit of it
                  controller.selection = TextSelection(
                    baseOffset: 0,
                    extentOffset: controller.text.length,
                  );
                },
                child: TextField(
                  controller: controller,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(bulkAddQuantityPattern),
                  ],
                  decoration: InputDecoration(
                    labelText: DishStrings.portion,
                    suffixText: 'g',
                    isDense: true,
                    // a field, not more of the heading's tint
                    filled: true,
                    fillColor: scheme.surface,
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (value) => _scaleDish(group, value),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Sets each of the dish's rows to its share of a portion of [text]
  /// grams.
  void _scaleDish(Object group, String text) {
    final state = _bloc.state;
    if (state is! BulkAddLoadedState) return;
    final base = _portionBase.putIfAbsent(
      group,
      () => portionBase(state.rows, dishMembers(state.rows, group)),
    );
    final grams = double.tryParse(text.trim().replaceAll(',', '.'));
    if (grams == null || grams <= 0) return;
    final amounts = scaledAmounts(state.rows, base, grams);
    if (amounts == null) return;
    for (final MapEntry(:key, :value) in amounts.entries) {
      if (_quantityErrors.containsKey(key)) _clearQuantityError(key);
      _bloc.add(ChangeRowAmountEvent(key, value));
    }
  }

  Widget _buildDishActions(BuildContext context, Object group) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    child: Wrap(
      spacing: 4,
      children: [
        TextButton(
          onPressed: () => _saveDishRecipe(group),
          child: const Text(DishStrings.saveAsRecipe),
        ),
        Semantics(
          identifier: 'bulk-add-dish-separate',
          child: TextButton(
            onPressed: () => _logDishSeparately(group),
            child: const Text(DishStrings.logSeparately),
          ),
        ),
      ],
    ),
  );
}
