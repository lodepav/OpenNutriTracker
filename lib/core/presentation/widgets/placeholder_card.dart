import 'package:flutter/material.dart';
import 'package:opennutritracker/core/presentation/widgets/app_card.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/dimens.dart';

/// The "add" affordance at the foot of a meal / activity list — a quiet
/// full-width row with a centred plus, matching the row layout of the entries
/// above it.
class PlaceholderCard extends StatelessWidget {
  final DateTime day;
  final VoidCallback onTap;
  final bool firstListElement;

  /// Stable handle for UI drivers. Differs per list (meals vs activity) so
  /// the right "add" card can be targeted unambiguously.
  final String semanticIdentifier;

  // [fork] S81 a11y-labels: what a screen reader says for the bare plus
  final String? label;
  // [/fork]

  const PlaceholderCard({
    super.key,
    required this.day,
    required this.onTap,
    required this.firstListElement,
    required this.semanticIdentifier,
    // [fork] S81 a11y-labels
    this.label,
    // [/fork]
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final palette = isDark ? AppPalette.dark : AppPalette.light;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Dimens.spacing16,
        vertical: Dimens.spacing4,
      ),
      child: Semantics(
        identifier: semanticIdentifier,
        button: true,
        // [fork] S81 a11y-labels
        label: label,
        // [/fork]
        child: AppCard(
          color: palette.surfaceMuted,
          bordered: false,
          borderRadius: Dimens.radiusM,
          onTap: onTap,
          padding: const EdgeInsets.symmetric(vertical: Dimens.spacing12),
          child: Center(
            child: Icon(Icons.add_rounded, size: 26, color: palette.textMuted),
          ),
        ),
      ),
    );
  }
}
