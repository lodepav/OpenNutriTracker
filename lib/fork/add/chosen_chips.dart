import 'package:flutter/material.dart';

/// [child]'s chips with the chosen one in the accent and its on-colour, so
/// the choice shows without the check mark (WCAG 1.4.11). The theme's
/// selected fill, `secondaryContainer`, is the palette's `surfaceMuted`:
/// the same fill as the chips not chosen.
Widget chosenChips(BuildContext context, {required Widget child}) {
  final theme = Theme.of(context);
  final scheme = theme.colorScheme;
  return Theme(
    data: theme.copyWith(
      colorScheme: scheme.copyWith(
        secondaryContainer: scheme.primary,
        onSecondaryContainer: scheme.onPrimary,
      ),
    ),
    child: child,
  );
}
