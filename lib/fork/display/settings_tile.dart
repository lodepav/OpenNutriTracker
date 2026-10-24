import 'package:flutter/material.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/dimens.dart';

/// The fork's rows in Settings, dressed as upstream's private
/// `_SettingsTile`: the icon on a soft tinted chip, a bold title and a
/// muted subtitle. A [ListTile] still, so its semantics carry through.
class ForkSettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;

  /// A widget, not a string: several rows build theirs from a listenable.
  final Widget? subtitle;
  final VoidCallback? onTap;

  const ForkSettingsTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) => ListTile(
    leading: _IconChip(icon),
    title: _title(context, title),
    subtitle: _subtitle(context, subtitle),
    onTap: onTap,
  );
}

/// [ForkSettingsTile]'s switch, as upstream's `_SettingsSwitchTile`.
class ForkSettingsSwitchTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const ForkSettingsSwitchTile({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) => SwitchListTile(
    secondary: _IconChip(icon),
    title: _title(context, title),
    subtitle: _subtitle(context, subtitle),
    value: value,
    onChanged: onChanged,
  );
}

AppPalette _palette(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? AppPalette.dark
    : AppPalette.light;

Widget _title(BuildContext context, String title) => Text(
  title,
  style: Theme.of(
    context,
  ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
);

Widget? _subtitle(BuildContext context, Widget? subtitle) => subtitle == null
    ? null
    : DefaultTextStyle.merge(
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(color: _palette(context).textMuted),
        child: subtitle,
      );

class _IconChip extends StatelessWidget {
  final IconData icon;

  const _IconChip(this.icon);

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: Dimens.borderRadiusS,
      ),
      child: Icon(icon, color: color, size: 22),
    );
  }
}
