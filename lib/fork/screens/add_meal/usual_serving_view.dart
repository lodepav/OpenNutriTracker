import 'package:flutter/material.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/fork/bulk/amount_question.dart';
import 'package:opennutritracker/fork/dish/dish_strings.dart';

/// Under a photo's row whose amount is far from the food's usual serving
/// (D47): a quiet line saying the serving, and one chip that takes it.
class UsualServingView extends StatelessWidget {
  /// The usual serving, as the chip sets it.
  final AmountChoice serving;

  /// The row's index, for the keys.
  final int index;
  final VoidCallback onTake;

  const UsualServingView({
    super.key,
    required this.serving,
    required this.index,
    required this.onTake,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      container: true,
      child: Wrap(
        key: ValueKey('bulk-add-usual-serving-$index'),
        spacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            DishStrings.usualServing(serving.label),
            semanticsLabel: DishStrings.usualServing(serving.spoken),
            style: theme.textTheme.bodySmall?.copyWith(
              color: paletteOf(context).textMuted,
            ),
          ),
          Semantics(
            identifier: 'bulk-add-usual-serving-take',
            child: ActionChip(
              key: ValueKey('bulk-add-usual-serving-take-$index'),
              label: Text(
                DishStrings.useUsualServing(serving.label),
                semanticsLabel: DishStrings.useUsualServing(serving.spoken),
              ),
              materialTapTargetSize: MaterialTapTargetSize.padded,
              onPressed: onTake,
            ),
          ),
        ],
      ),
    );
  }
}
