import 'package:flutter/material.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/fork/bulk/cooking_fat.dart';
import 'package:opennutritracker/fork/dish/dish_strings.dart';

/// The meal card's question about the fat a photo's meal was cooked or
/// dressed with (D48): None, then three amounts; none chosen until tapped.
class CookingFatView extends StatelessWidget {
  final CookingFatAsk ask;

  /// The amount chip at what the added row holds now; null for none.
  final int? chosen;

  /// None (-1) or the amount chip of [cookingFatGrams] tapped.
  final ValueChanged<int> onChosen;

  const CookingFatView({
    super.key,
    required this.ask,
    required this.chosen,
    required this.onChosen,
  });

  static const _labels = [
    DishStrings.fatLittle,
    DishStrings.fatSome,
    DishStrings.fatLot,
  ];
  static const _spoken = [
    DishStrings.fatLittleSpoken,
    DishStrings.fatSomeSpoken,
    DishStrings.fatLotSpoken,
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      container: true,
      child: Column(
        key: const ValueKey('bulk-add-cooking-fat'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            ask == CookingFatAsk.cooked
                ? DishStrings.cookedWithFat
                : DishStrings.dressedWithFat,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: paletteOf(context).textStrong,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Semantics(
                identifier: 'bulk-add-cooking-fat-none',
                child: ChoiceChip(
                  key: const ValueKey('bulk-add-cooking-fat-none'),
                  label: const Text(DishStrings.fatNone),
                  materialTapTargetSize: MaterialTapTargetSize.padded,
                  selected: false,
                  onSelected: (_) => onChosen(-1),
                ),
              ),
              for (final (i, label) in _labels.indexed)
                Semantics(
                  identifier: 'bulk-add-cooking-fat-$i',
                  child: ChoiceChip(
                    key: ValueKey('bulk-add-cooking-fat-$i'),
                    label: Text(label, semanticsLabel: _spoken[i]),
                    materialTapTargetSize: MaterialTapTargetSize.padded,
                    selected: chosen == i,
                    onSelected: (_) => onChosen(i),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
