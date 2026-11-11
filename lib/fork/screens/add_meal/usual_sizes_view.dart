import 'package:flutter/material.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/fork/dish/dish_strings.dart';

/// On a photo's meal card, above its Size: the photo's amounts arrived
/// sized the way this user usually corrects them (D46), which foods and by
/// how much, and one tap back to the photo's own amounts; once there, one
/// tap returns to the usual sizes.
class UsualSizesView extends StatelessWidget {
  /// The foods sized, in the order shown.
  final List<({String name, double factor})> foods;

  /// Whether the usual sizes are in force, not the photo's amounts.
  final bool inForce;
  final VoidCallback onUsePhoto;
  final VoidCallback onUseUsual;

  const UsualSizesView({
    super.key,
    required this.foods,
    required this.inForce,
    required this.onUsePhoto,
    required this.onUseUsual,
  });

  /// At most three foods: a longer line stops being read.
  static const shownFoods = 3;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = paletteOf(context);
    final shown = foods.take(shownFoods).toList();
    final more = foods.length - shown.length;
    final text = inForce
        ? DishStrings.usualSized(shown, more: more)
        : DishStrings.usingPhotoAmounts;
    final spoken = inForce
        ? DishStrings.usualSizedSpoken(shown, more: more)
        : text;
    final button = inForce
        ? (
            key: 'bulk-add-usual-photo',
            label: DishStrings.usePhotoAmounts,
            onPressed: onUsePhoto,
          )
        : (
            key: 'bulk-add-usual-return',
            label: DishStrings.useUsualSizes,
            onPressed: onUseUsual,
          );
    return Semantics(
      container: true,
      child: Column(
        key: const ValueKey('bulk-add-usual-sizes'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            text,
            semanticsLabel: spoken,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: palette.textStrong,
            ),
          ),
          Semantics(
            identifier: button.key,
            child: TextButton(
              key: ValueKey(button.key),
              style: TextButton.styleFrom(
                minimumSize: const Size(48, 48),
                tapTargetSize: MaterialTapTargetSize.padded,
              ),
              onPressed: button.onPressed,
              child: Text(button.label),
            ),
          ),
        ],
      ),
    );
  }
}
