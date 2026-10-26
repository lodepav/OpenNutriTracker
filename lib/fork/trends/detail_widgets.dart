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
              // Against the card's right edge, not the half's start.
              child: Align(
                alignment: AlignmentDirectional.topEnd,
                child: Text(
                  value,
                  textAlign: TextAlign.end,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A chart's key: a swatch before each label, or a short bar for a line.
class ChartLegend extends StatelessWidget {
  final List<({String label, Color color, bool line})> entries;

  const ChartLegend({super.key, required this.entries});

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall;
    return Wrap(
      spacing: Dimens.spacing12,
      runSpacing: Dimens.spacing4,
      children: [
        for (final e in entries)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: e.line ? 14 : 8,
                height: e.line ? 3 : 8,
                decoration: BoxDecoration(
                  color: e.color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 6),
              Text(e.label, style: style),
            ],
          ),
      ],
    );
  }
}

/// A small card of one figure: its label, the number and its unit, and a
/// line under it; tapped, it does what [onTap] does.
class FigureTile extends StatelessWidget {
  final String label;
  final String value;
  final String? unit;
  final String? note;
  final VoidCallback? onTap;

  const FigureTile({
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
class FigureGrid extends StatelessWidget {
  final List<Widget> tiles;

  const FigureGrid({super.key, required this.tiles});

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

/// A card of [TrendRow]s: a label on the left, its value on the right.
class TrendRows extends StatelessWidget {
  final List<({String label, String value})> rows;

  const TrendRows({super.key, required this.rows});

  @override
  Widget build(BuildContext context) => AppCard(
    padding: const EdgeInsets.symmetric(horizontal: Dimens.spacing16),
    child: Column(
      children: [
        for (final (i, r) in rows.indexed)
          TrendRow(label: r.label, value: r.value, first: i == 0),
      ],
    ),
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

/// A row that explains [title]: "What is expenditure? ›" opens [body].
class ExplainerLink extends StatelessWidget {
  final String title;
  final String body;

  const ExplainerLink({super.key, required this.title, required this.body});

  @override
  Widget build(BuildContext context) => AppCard(
    child: ListTile(
      title: Text(title),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: () => showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    ),
  );
}

/// [n] days, in words: "1 day", "3 days".
String days(int n) => n == 1 ? '1 day' : '$n days';
