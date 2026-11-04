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
    final title = Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
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
          Semantics(
            identifier: 'bulk-add-dish-menu',
            child: PopupMenuButton<VoidCallback>(
              tooltip: 'Dish actions',
              icon: Icon(
                Icons.more_vert_rounded,
                color: scheme.onSecondaryContainer,
              ),
              onSelected: (action) => action(),
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: () => _saveDishRecipe(group),
                  child: const Text(DishStrings.saveAsRecipe),
                ),
                PopupMenuItem(
                  value: () => _logDishSeparately(group),
                  child: const Text(DishStrings.logSeparately),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    final portion = Padding(
      padding: const EdgeInsets.only(left: 44, bottom: 8),
      child: Row(
        children: [
          IconButton.filledTonal(
            key: const ValueKey('bulk-add-dish-less'),
            style: IconButton.styleFrom(backgroundColor: scheme.surface),
            tooltip: 'Less',
            visualDensity: VisualDensity.compact,
            onPressed: grams > 0
                ? () => _stepDish(group, grams, up: false)
                : null,
            icon: const Icon(Icons.remove),
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Semantics(
              identifier: 'bulk-add-dish-portion',
              child: OutlinedButton(
                key: const ValueKey('bulk-add-dish-portion'),
                onPressed: () => _editDishPortion(group, controller),
                style: OutlinedButton.styleFrom(
                  backgroundColor: scheme.surface,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  shape: const StadiumBorder(),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        grams > 0
                            ? '${DishStrings.portion} ${grams.round()} g'
                            : DishStrings.portion,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const Icon(Icons.arrow_drop_down_rounded),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          IconButton.filledTonal(
            key: const ValueKey('bulk-add-dish-more'),
            style: IconButton.styleFrom(backgroundColor: scheme.surface),
            tooltip: 'More',
            visualDensity: VisualDensity.compact,
            onPressed: grams > 0
                ? () => _stepDish(group, grams, up: true)
                : null,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
    );
    return Container(
      color: scheme.secondaryContainer,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [title, portion],
      ),
    );
  }

  /// The dish's portion moved by 10 g, or 25 g from 200 g, its foods
  /// scaled with it.
  void _stepDish(Object group, double grams, {required bool up}) {
    final next = steppedAmount(grams, grams < 200 ? 10 : 25, up: up);
    _scaleDish(group, amountText(next));
    _endPortionEdit(group);
  }

  /// The dish's portion typed, in a sheet: each figure scales its foods as
  /// it is typed.
  Future<void> _editDishPortion(
    Object group,
    TextEditingController controller,
  ) async {
    controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: controller.text.length,
    );
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => Padding(
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
            TextField(
              key: const ValueKey('bulk-add-dish-portion-field'),
              controller: controller,
              autofocus: true,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(bulkAddQuantityPattern),
              ],
              decoration: const InputDecoration(
                labelText: DishStrings.portion,
                suffixText: 'g',
                border: OutlineInputBorder(),
              ),
              onChanged: (value) => _scaleDish(group, value),
            ),
            const SizedBox(height: 16),
            FilledButton(
              key: const ValueKey('bulk-add-dish-portion-done'),
              onPressed: () => Navigator.pop(context),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
    _endPortionEdit(group);
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
}
