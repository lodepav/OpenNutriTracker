import 'package:flutter/material.dart';
import 'package:opennutritracker/core/presentation/widgets/app_card.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/dimens.dart';

AppPalette _palette(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? AppPalette.dark
    : AppPalette.light;

/// Seam S138: Health Connect as MacroFactor's (PickHealth B), the heading
/// over the cards.
class HealthSyncHeading extends StatelessWidget {
  const HealthSyncHeading({super.key});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Dimens.spacing4,
        Dimens.spacing4,
        Dimens.spacing4,
        Dimens.spacing12,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(
              'What should sync?',
              style: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          Text(
            'Pick what to share; Android asks once for each.',
            style: text.bodySmall?.copyWith(color: _palette(context).textMuted),
          ),
        ],
      ),
    );
  }
}

/// One thing that syncs, a card with a box to tick: what it is, and where
/// it goes.
class HealthSyncCard extends StatelessWidget {
  final String identifier;
  final IconData icon;
  final String title;
  final String detail;
  final bool value;

  /// Null while it can not be changed.
  final ValueChanged<bool>? onChanged;

  const HealthSyncCard({
    super.key,
    required this.identifier,
    required this.icon,
    required this.title,
    required this.detail,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final palette = _palette(context);
    final text = Theme.of(context).textTheme;
    final onChanged = this.onChanged;
    return Padding(
      padding: const EdgeInsets.only(bottom: Dimens.spacing8),
      child: AppCard(
        padding: EdgeInsets.zero,
        child: Semantics(
          identifier: identifier,
          child: CheckboxListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: Dimens.spacing12,
              vertical: Dimens.spacing4,
            ),
            secondary: ExcludeSemantics(
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: palette.surfaceMuted,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: palette.textStrong),
              ),
            ),
            title: Text(
              title,
              style: text.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              detail,
              style: text.bodySmall?.copyWith(color: palette.textMuted),
            ),
            value: value,
            onChanged: onChanged == null ? null : (v) => onChanged(v ?? false),
          ),
        ),
      ),
    );
  }
}

/// Under the cards: when the last import ran, and a button to run one.
class HealthSyncFooter extends StatelessWidget {
  final String lastImport;

  /// Null while there is nothing to import, or an import is running.
  final VoidCallback? onImport;

  /// Why [onImport] is off, under the last import, when it can be told.
  final String? why;

  const HealthSyncFooter({
    super.key,
    required this.lastImport,
    required this.onImport,
    this.why,
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Dimens.spacing4,
        Dimens.spacing4,
        Dimens.spacing4,
        Dimens.spacing12,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  lastImport,
                  style: text.bodySmall?.copyWith(
                    color: _palette(context).textMuted,
                  ),
                ),
                if (why case final why?) Text(why, style: text.bodySmall),
              ],
            ),
          ),
          const SizedBox(width: Dimens.spacing8),
          Semantics(
            identifier: 'health-sync-import-now',
            child: FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
              onPressed: onImport,
              child: const Text('Import now'),
            ),
          ),
        ],
      ),
    );
  }
}
