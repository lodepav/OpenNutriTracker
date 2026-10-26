import 'package:flutter/material.dart';
import 'package:opennutritracker/core/presentation/widgets/app_card.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/off_const.dart';
import 'package:opennutritracker/features/add_meal/data/dto/sp/sp_const.dart';

/// A database as the list names it: a short tag, a name, what it holds.
typedef FoodDatabase = ({String tag, String name, String holds});

/// The databases Settings offers, by their source code.
const foodDatabases = <String, FoodDatabase>{
  'fdc_foundation': (
    tag: 'FDC',
    name: 'USDA Foundation',
    holds: 'Raw foods, lab-measured',
  ),
  'fdc_sr_legacy': (
    tag: 'SR',
    name: 'USDA SR Legacy',
    holds: 'Classic reference foods',
  ),
  'fdc_survey': (
    tag: 'FN',
    name: 'USDA FNDDS',
    holds: 'Dishes as eaten in the US',
  ),
  'fdc_branded': (
    tag: 'BR',
    name: 'USDA Branded',
    holds: 'US packaged products',
  ),
  'bls': (
    tag: 'BLS',
    name: 'Bundeslebensmittelschlüssel',
    holds: 'German reference foods',
  ),
};

/// Seam S137: Food databases as MacroFactor's (PickDb A). Open Food Facts
/// always on, then a switch for each database, with a tag for each; the
/// databases' sites under the list.
class FoodDatabasesView extends StatelessWidget {
  /// Off for a database switched off; a database missing is on.
  final Map<String, bool> toggles;
  final void Function(String code, bool on) onToggle;
  final ValueChanged<String> onOpenSite;

  const FoodDatabasesView({
    super.key,
    required this.toggles,
    required this.onToggle,
    required this.onOpenSite,
  });

  @override
  Widget build(BuildContext context) {
    final palette = paletteOf(context);
    final text = Theme.of(context).textTheme;
    final rows = <Widget>[
      _DatabaseRow(
        identifier: 'food-source-off',
        tag: 'OFF',
        name: OFFConst.offSourceName,
        holds: 'Packaged products, barcodes · worldwide',
        trailing: Text(
          'always',
          style: text.bodySmall?.copyWith(color: palette.textMuted),
        ),
      ),
      for (final code in SPConst.settingsSelectableFoodSources)
        if (foodDatabases[code] case final db?)
          _DatabaseRow(
            identifier: 'food-source-$code',
            tag: db.tag,
            name: db.name,
            holds: db.holds,
            on: toggles[code] ?? true,
            onChanged: (on) => onToggle(code, on),
          ),
    ];
    final sites = <String, String>{
      OFFConst.offSourceName: OFFConst.offWebsiteUrl,
      'USDA FoodData Central': SPConst.foodSourceWebsites['fdc_foundation']!,
      'BLS': SPConst.foodSourceWebsites['bls']!,
    };
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        Dimens.spacing12,
        0,
        Dimens.spacing12,
        Dimens.spacing32,
      ),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            Dimens.spacing4,
            0,
            Dimens.spacing4,
            Dimens.spacing8,
          ),
          child: Text(
            'Where search results come from.',
            style: text.bodySmall?.copyWith(color: palette.textMuted),
          ),
        ),
        AppCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (final (i, row) in rows.indexed) ...[
                if (i > 0) Divider(height: 1, color: palette.surfaceMuted),
                row,
              ],
            ],
          ),
        ),
        const SizedBox(height: Dimens.spacing8),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: Dimens.spacing4),
              child: Text(
                'About them:',
                style: text.bodySmall?.copyWith(color: palette.textMuted),
              ),
            ),
            for (final MapEntry(key: name, value: url) in sites.entries)
              TextButton(onPressed: () => onOpenSite(url), child: Text(name)),
          ],
        ),
      ],
    );
  }
}

class _DatabaseRow extends StatelessWidget {
  final String identifier;
  final String tag;
  final String name;
  final String holds;

  /// Without [onChanged], [trailing] stands in for the switch.
  final bool on;
  final ValueChanged<bool>? onChanged;
  final Widget? trailing;

  const _DatabaseRow({
    required this.identifier,
    required this.tag,
    required this.name,
    required this.holds,
    this.on = true,
    this.onChanged,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final palette = paletteOf(context);
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final label = Row(
      children: [
        ExcludeSemantics(
          child: Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: palette.surfaceMuted,
              borderRadius: BorderRadius.circular(10),
            ),
            padding: const EdgeInsets.all(4),
            // The box keeps its size at any font; the tag shrinks to it.
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                tag,
                style: text.labelMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: scheme.primary,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: Dimens.spacing12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: text.bodyLarge),
              Text(
                holds,
                style: text.bodySmall?.copyWith(color: palette.textMuted),
              ),
            ],
          ),
        ),
      ],
    );
    final onChanged = this.onChanged;
    if (onChanged == null) {
      return Semantics(
        identifier: identifier,
        container: true,
        child: MergeSemantics(
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Dimens.spacing12,
                vertical: Dimens.spacing8,
              ),
              child: Row(
                children: [
                  Expanded(child: label),
                  ?trailing,
                ],
              ),
            ),
          ),
        ),
      );
    }
    return Semantics(
      identifier: identifier,
      container: true,
      child: SwitchListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: Dimens.spacing12,
          vertical: Dimens.spacing4,
        ),
        title: label,
        value: on,
        onChanged: onChanged,
      ),
    );
  }
}
