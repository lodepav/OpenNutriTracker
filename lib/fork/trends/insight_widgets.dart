import 'package:flutter/material.dart';
import 'package:opennutritracker/core/presentation/widgets/app_card.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/dimens.dart';

/// The pieces the trend pages show under their charts (round 3 of the
/// redesign): a section's name, tiles two to a row, a row of change chips
/// and a card of label and value rows.

/// A section's name over its card.
class InsightSection extends StatelessWidget {
  final String title;

  const InsightSection(this.title, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      Dimens.spacing4,
      Dimens.spacing16,
      Dimens.spacing4,
      Dimens.spacing8,
    ),
    child: Semantics(
      header: true,
      child: Text(
        title,
        style: Theme.of(
          context,
        ).textTheme.titleSmall?.copyWith(color: paletteOf(context).textMuted),
      ),
    ),
  );
}

/// One figure with its name over it and a line under it; tapped, it opens
/// what [onTap] does.
class InsightTile extends StatelessWidget {
  final String label;
  final String value;
  final String? unit;
  final String? note;
  final VoidCallback? onTap;

  const InsightTile({
    super.key,
    required this.label,
    required this.value,
    this.unit,
    this.note,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final palette = paletteOf(context);
    final text = Theme.of(context).textTheme;
    final muted = text.bodySmall?.copyWith(color: palette.textMuted);
    final body = Padding(
      padding: const EdgeInsets.all(Dimens.spacing12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(label, style: muted)),
              if (onTap != null)
                Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: palette.textMuted,
                ),
            ],
          ),
          const SizedBox(height: 2),
          Text.rich(
            TextSpan(
              text: value,
              style: text.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              children: [
                if (unit != null) TextSpan(text: ' $unit', style: muted),
              ],
            ),
          ),
          if (note != null) Text(note!, style: muted),
        ],
      ),
    );
    return AppCard(
      padding: EdgeInsets.zero,
      child: onTap == null
          ? MergeSemantics(child: body)
          : Semantics(
              button: true,
              child: InkWell(
                borderRadius: Dimens.borderRadiusL,
                onTap: onTap,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: body,
                ),
              ),
            ),
    );
  }
}

/// [tiles] two to a row, each row as tall as its taller tile.
class InsightGrid extends StatelessWidget {
  final List<Widget> tiles;

  const InsightGrid({super.key, required this.tiles});

  @override
  Widget build(BuildContext context) => Column(
    spacing: Dimens.spacing8,
    children: [
      for (var i = 0; i < tiles.length; i += 2)
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: Dimens.spacing8,
            children: [
              Expanded(child: tiles[i]),
              Expanded(
                child: i + 1 < tiles.length ? tiles[i + 1] : const SizedBox(),
              ),
            ],
          ),
        ),
    ],
  );
}

/// A change over each span: "7 d" over "−0.2". Under large text they wrap.
class ChangeChips extends StatelessWidget {
  final List<({String span, String value, String spoken})> changes;

  const ChangeChips({super.key, required this.changes});

  @override
  Widget build(BuildContext context) {
    final palette = paletteOf(context);
    final text = Theme.of(context).textTheme;
    Widget chip(({String span, String value, String spoken}) c) => Semantics(
      label: c.spoken,
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: Dimens.spacing4,
          vertical: Dimens.spacing8,
        ),
        decoration: BoxDecoration(
          color: palette.surface,
          border: Border.all(color: palette.border),
          borderRadius: Dimens.borderRadiusM,
        ),
        child: Column(
          children: [
            Text(
              c.span,
              style: text.labelSmall?.copyWith(color: palette.textMuted),
            ),
            Text(
              c.value,
              style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
    if (MediaQuery.textScalerOf(context).scale(1) >= 1.5) {
      return Wrap(
        spacing: Dimens.spacing8,
        runSpacing: Dimens.spacing8,
        children: [
          for (final c in changes) SizedBox(width: 96, child: chip(c)),
        ],
      );
    }
    return Row(
      spacing: Dimens.spacing8,
      children: [for (final c in changes) Expanded(child: chip(c))],
    );
  }
}

/// A card of rows: a label on the left, its value on the right.
class InsightRows extends StatelessWidget {
  final List<({String label, String value})> rows;

  const InsightRows({super.key, required this.rows});

  @override
  Widget build(BuildContext context) {
    final palette = paletteOf(context);
    final text = Theme.of(context).textTheme;
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: Dimens.spacing16),
      child: Column(
        children: [
          for (final (i, r) in rows.indexed)
            MergeSemantics(
              child: Container(
                constraints: const BoxConstraints(minHeight: 48),
                decoration: BoxDecoration(
                  border: i == 0
                      ? null
                      : Border(top: BorderSide(color: palette.border)),
                ),
                padding: const EdgeInsets.symmetric(vertical: Dimens.spacing8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        r.label,
                        style: text.bodyMedium?.copyWith(
                          color: palette.textMuted,
                        ),
                      ),
                    ),
                    const SizedBox(width: Dimens.spacing12),
                    Flexible(
                      child: Text(
                        r.value,
                        textAlign: TextAlign.end,
                        style: text.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A row that opens an explainer: "What is the trend weight? ›".
class ExplainerLink extends StatelessWidget {
  final String title;
  final String body;

  const ExplainerLink({super.key, required this.title, required this.body});

  @override
  Widget build(BuildContext context) => AppCard(
    padding: EdgeInsets.zero,
    child: ListTile(
      title: Text(title),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: () => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (context) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              Dimens.spacing24,
              0,
              Dimens.spacing24,
              Dimens.spacing24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: Dimens.spacing12),
                Text(body, style: Theme.of(context).textTheme.bodyLarge),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
