import 'package:flutter/material.dart';
import 'package:opennutritracker/core/presentation/widgets/app_card.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/custom_text_input_formatter.dart';
import 'package:opennutritracker/fork/units/amount_text.dart' show spokenUnit;

/// Seam S132: the custom food form after the canvas's "New custom food ·
/// B". The nutrients sit in one card laid out like a label: what they are
/// per on top, then a row per nutrient with its field on the right, the
/// "of which" rows indented, and the rarer ones behind "Add a vitamin or
/// mineral". The label scan is a card above it (S29's button, as a card).

/// One nutrient as a label row: its name, then a narrow field in [unit].
class FactsRow extends StatelessWidget {
  final String label;
  final String unit;
  final TextEditingController controller;

  /// An "of which" row (saturates under fat, sugars under carbohydrate).
  final bool indent;

  const FactsRow({
    super.key,
    required this.label,
    required this.unit,
    required this.controller,
    this.indent = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = label.isEmpty
        ? label
        : label[0].toUpperCase() + label.substring(1);
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 52),
      child: Row(
        children: [
          SizedBox(width: indent ? Dimens.spacing16 : 0),
          Expanded(
            child: Text(
              name,
              style: indent
                  ? theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    )
                  : theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
            ),
          ),
          // The unit beside the field, shown before anything is typed
          // (H6), and the field grows with the text (A6).
          SizedBox(
            width: MediaQuery.textScalerOf(context).scale(80).clamp(80, 140),
            child: Semantics(
              label: '$name in ${spokenUnit(unit)}',
              child: TextField(
                controller: controller,
                textAlign: TextAlign.end,
                inputFormatters: CustomTextInputFormatter.doubleOnly(),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: Dimens.spacing8,
                    vertical: Dimens.spacing12,
                  ),
                  border: const OutlineInputBorder(
                    borderRadius: Dimens.borderRadiusM,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: Dimens.spacing4),
          SizedBox(
            width: MediaQuery.textScalerOf(context).scale(44).clamp(44, 110),
            child: ExcludeSemantics(
              // A unit never breaks ("kca / l" at 200%, A6)
              child: Text(
                unit,
                softWrap: false,
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The label card: "Nutrition facts", what the values are [per], the
/// [rows], and [more] behind "Add a vitamin or mineral" until opened (or
/// open from the start when [moreOpen], as when one has a value).
class NutritionFactsCard extends StatefulWidget {
  final Widget per;
  final List<Widget> rows;
  final List<Widget> more;
  final bool moreOpen;

  const NutritionFactsCard({
    super.key,
    required this.per,
    required this.rows,
    this.more = const [],
    this.moreOpen = false,
  });

  @override
  State<NutritionFactsCard> createState() => _NutritionFactsCardState();
}

class _NutritionFactsCardState extends State<NutritionFactsCard> {
  late bool _moreOpen = widget.moreOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final divider = Divider(height: 1, color: theme.colorScheme.outlineVariant);
    return AppCard(
      padding: const EdgeInsets.fromLTRB(
        Dimens.spacing16,
        Dimens.spacing12,
        Dimens.spacing16,
        Dimens.spacing8,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Nutrition facts',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          widget.per,
          Divider(thickness: 3, color: theme.colorScheme.onSurface),
          for (final (i, row) in widget.rows.indexed) ...[
            if (i > 0) divider,
            row,
          ],
          if (widget.more.isNotEmpty)
            if (_moreOpen)
              for (final row in widget.more) ...[divider, row]
            else
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  key: const Key('facts-more'),
                  onPressed: () => setState(() => _moreOpen = true),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Add a vitamin or mineral'),
                ),
              ),
        ],
      ),
    );
  }
}
