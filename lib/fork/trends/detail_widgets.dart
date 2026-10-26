import 'package:flutter/material.dart';
import 'package:opennutritracker/core/presentation/widgets/app_card.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/dimens.dart';

/// A detail page's section heading, which TalkBack can jump to.
Widget trendSection(BuildContext context, String label) => Padding(
  padding: const EdgeInsets.only(
    top: Dimens.spacing16,
    bottom: Dimens.spacing4,
  ),
  child: Semantics(
    header: true,
    child: Text(
      label,
      style: Theme.of(
        context,
      ).textTheme.titleSmall?.copyWith(color: paletteOf(context).textMuted),
    ),
  ),
);

/// A label and its value on one line, as a row of a detail card.
class TrendRow extends StatelessWidget {
  final String label;
  final String value;
  final bool first;

  const TrendRow({
    super.key,
    required this.label,
    required this.value,
    this.first = false,
  });

  @override
  Widget build(BuildContext context) {
    final palette = paletteOf(context);
    return MergeSemantics(
      child: Container(
        constraints: const BoxConstraints(minHeight: 40),
        padding: const EdgeInsets.symmetric(vertical: Dimens.spacing8),
        decoration: first
            ? null
            : BoxDecoration(
                border: Border(top: BorderSide(color: palette.border)),
              ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(label, style: TextStyle(color: palette.textMuted)),
            ),
            const SizedBox(width: Dimens.spacing8),
            Flexible(
              child: Text(
                value,
                textAlign: TextAlign.end,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A small card of one figure: its label, the number and its unit, and a
/// line under it.
class FigureTile extends StatelessWidget {
  final String label;
  final String value;
  final String? unit;
  final String? note;

  const FigureTile({
    super.key,
    required this.label,
    required this.value,
    this.unit,
    this.note,
  });

  @override
  Widget build(BuildContext context) {
    final palette = paletteOf(context);
    final text = Theme.of(context).textTheme;
    final muted = text.bodySmall?.copyWith(color: palette.textMuted);
    return MergeSemantics(
      child: AppCard(
        padding: const EdgeInsets.all(Dimens.spacing12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: muted),
            Text.rich(
              TextSpan(
                text: value,
                style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                children: [
                  if (unit != null) TextSpan(text: ' $unit', style: muted),
                ],
              ),
            ),
            if (note != null) Text(note!, style: muted),
          ],
        ),
      ),
    );
  }
}
