part of 'settings_screen.dart';

class _AccentTrailingSwatch extends StatelessWidget {
  final bool useMaterialYou;
  final int? accentColor;

  const _AccentTrailingSwatch({
    required this.useMaterialYou,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final isAndroid = Theme.of(context).platform == TargetPlatform.android;
    if (isAndroid && useMaterialYou) {
      return Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const SweepGradient(
            colors: <Color>[
              Color(0xFFFF5252),
              Color(0xFFFFD740),
              Color(0xFF69F0AE),
              Color(0xFF40C4FF),
              Color(0xFFB388FF),
              Color(0xFFFF5252),
            ],
          ),
        ),
      );
    }
    final color = accentColor != null
        ? Color(accentColor!)
        : const Color(0xFF43A047); // default green disc preview
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

/// Wraps a run of related settings rows inside one [AppCard], with a hairline
/// divider between rows. Gives the screen the same calm grouped rhythm as the
/// Profile tab rather than one long ungrouped list.
class _SettingsGroup extends StatelessWidget {
  final AppPalette palette;
  final List<Widget> tiles;

  const _SettingsGroup({required this.palette, required this.tiles});

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < tiles.length; i++) {
      if (i > 0) {
        rows.add(Divider(height: Dimens.hairline, color: palette.border));
      }
      // A row is its own node; else the
      // first row's tap took in the card's other rows
      rows.add(Semantics(container: true, child: tiles[i]));
    }
    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: Dimens.spacing4),
      child: Column(mainAxisSize: MainAxisSize.min, children: rows),
    );
  }
}

/// A single tappable settings row. Keeps the underlying [ListTile] (so its
/// role semantics carry through) and an optional [Semantics] identifier where
/// the original markup carried one, but dresses the leading icon as a soft
/// rounded chip in the friendly-flat style.
class _SettingsTile extends StatelessWidget {
  final String? identifier;
  final AppPalette palette;
  final IconData icon;
  final Color? iconColor;
  final Color? titleColor;
  final String title;
  final String? subtitle;

  /// A short status word shown beside the title, e.g. "Experimental".
  final String? badge;
  final Widget? trailing;
  final bool showChevron;
  final bool enabled;
  final VoidCallback onTap;

  const _SettingsTile({
    required this.palette,
    required this.icon,
    required this.title,
    required this.onTap,
    this.identifier,
    this.iconColor,
    this.titleColor,
    this.subtitle,
    this.badge,
    this.trailing,
    this.showChevron = false,
    this.enabled = true,
  });

  /// The title, with [badge] beside it when one is set.
  ///
  /// The overflow discipline moved into [BadgedTitle] for #728, when
  /// onboarding needed the same marker — it is a rule rather than a layout,
  /// and re-deriving it at a second site was the obvious way to get it subtly
  /// wrong. The typography stays here, so a settings row still looks like a
  /// settings row.
  Widget _titleWithBadge(
    BuildContext context,
    TextTheme text,
    AppPalette palette,
  ) => BadgedTitle(
    title: title,
    badge: badge,
    palette: palette,
    style: text.titleMedium?.copyWith(
      fontWeight: FontWeight.w700,
      color: titleColor,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final text = Theme.of(context).textTheme;
    final tint = iconColor ?? accent;
    final tile = ListTile(
      enabled: enabled,
      leading: _SettingsIconChip(palette: palette, icon: icon, color: tint),
      title: _titleWithBadge(context, text, palette),
      subtitle: subtitle != null
          ? Text(
              subtitle!,
              style: text.bodyMedium?.copyWith(color: palette.textMuted),
            )
          : null,
      trailing:
          trailing ??
          (showChevron
              ? Icon(Icons.chevron_right_rounded, color: accent)
              : null),
      onTap: onTap,
    );
    if (identifier == null) return tile;
    return Semantics(identifier: identifier!, child: tile);
  }
}

/// Switch variant of [_SettingsTile] for the boolean toggles.
class _SettingsSwitchTile extends StatelessWidget {
  final String? identifier;
  final AppPalette palette;
  final IconData icon;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SettingsSwitchTile({
    this.identifier,
    required this.palette,
    required this.icon,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final text = Theme.of(context).textTheme;
    final tile = SwitchListTile(
      secondary: _SettingsIconChip(palette: palette, icon: icon, color: accent),
      title: Text(
        title,
        style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
      ),
      subtitle: subtitle != null
          ? Text(
              subtitle!,
              style: text.bodyMedium?.copyWith(color: palette.textMuted),
            )
          : null,
      value: value,
      onChanged: onChanged,
    );
    if (identifier == null) return tile;
    return Semantics(identifier: identifier!, child: tile);
  }
}

/// The soft rounded leading chip shared by every settings row.
class _SettingsIconChip extends StatelessWidget {
  final AppPalette palette;
  final IconData icon;
  final Color color;

  const _SettingsIconChip({
    required this.palette,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
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
