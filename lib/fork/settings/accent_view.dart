import 'package:flutter/material.dart';
import 'package:opennutritracker/core/presentation/widgets/app_card.dart';
import 'package:opennutritracker/core/styles/accent_colors.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/dimens.dart';

/// What a screen reader calls each of [accentPresetColors], in its order.
const accentPresetNames = [
  'Red',
  'Coral',
  'Orange',
  'Amber',
  'Yellow',
  'Chartreuse',
  'Lime',
  'Green',
  'Teal',
  'Cyan',
  'Sky',
  'Blue',
  'Indigo',
  'Violet',
  'Magenta',
  'Pink',
];

/// Seam S136: the accent colour as MacroFactor's (AccentA). A preview of
/// the colour on a ring and a button, the wallpaper switch on Android, the
/// presets as round swatches, and a custom colour.
class AccentColourView extends StatelessWidget {
  /// Whether the wallpaper switch is offered (Android).
  final bool offersWallpaper;
  final bool matchesWallpaper;

  /// The chosen preset or custom colour; null with none.
  final int? currentArgb;
  final ValueChanged<bool> onWallpaper;
  final ValueChanged<Color> onColor;
  final VoidCallback onCustom;

  const AccentColourView({
    super.key,
    required this.offersWallpaper,
    required this.matchesWallpaper,
    required this.currentArgb,
    required this.onWallpaper,
    required this.onColor,
    required this.onCustom,
  });

  @override
  Widget build(BuildContext context) {
    final palette = paletteOf(context);
    final text = Theme.of(context).textTheme;
    final accent = Theme.of(context).colorScheme.primary;
    return ListView(
      padding: EdgeInsets.fromLTRB(
        Dimens.spacing12,
        Dimens.spacing8,
        Dimens.spacing12,
        Dimens.spacing32 + MediaQuery.paddingOf(context).bottom,
      ),
      children: [
        AppCard(
          padding: const EdgeInsets.all(Dimens.spacing12),
          child: ExcludeSemantics(
            child: Row(
              children: [
                Container(
                  width: 72,
                  height: 72,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: accent, width: 9),
                  ),
                  child: Text(
                    '199',
                    style: text.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: Dimens.spacing16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Preview',
                        style: text.bodySmall?.copyWith(
                          color: palette.textMuted,
                        ),
                      ),
                      const SizedBox(height: Dimens.spacing4),
                      // A button's look only: nothing to tap in a preview.
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: Dimens.spacing16,
                          vertical: Dimens.spacing8,
                        ),
                        decoration: ShapeDecoration(
                          color: accent,
                          shape: const StadiumBorder(),
                        ),
                        child: Text(
                          'Add 640 g',
                          style: text.labelLarge?.copyWith(
                            color: Theme.of(context).colorScheme.onPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (offersWallpaper) ...[
          const SizedBox(height: Dimens.spacing8),
          AppCard(
            padding: EdgeInsets.zero,
            child: Semantics(
              identifier: 'accent-option-material-you',
              child: SwitchListTile(
                title: const Text('Match my wallpaper'),
                subtitle: Text(
                  'Android 12 and newer',
                  style: text.bodySmall?.copyWith(color: palette.textMuted),
                ),
                value: matchesWallpaper,
                onChanged: onWallpaper,
              ),
            ),
          ),
        ],
        const SizedBox(height: Dimens.spacing8),
        AppCard(
          padding: const EdgeInsets.all(Dimens.spacing12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  const perRow = 6;
                  const gap = Dimens.spacing8;
                  final size =
                      (constraints.maxWidth - gap * (perRow - 1)) / perRow;
                  return Wrap(
                    spacing: gap,
                    runSpacing: gap,
                    children: [
                      for (final (i, color) in accentPresetColors.indexed)
                        _Swatch(
                          index: i,
                          name: accentPresetNames[i],
                          color: color,
                          size: size,
                          selected:
                              !matchesWallpaper &&
                              currentArgb == color.toARGB32(),
                          onTap: () => onColor(color),
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(height: Dimens.spacing4),
              Semantics(
                identifier: 'accent-custom-colour',
                child: TextButton(
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(48, 48),
                  ),
                  onPressed: onCustom,
                  child: const Text('Custom colour…'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Swatch extends StatelessWidget {
  final int index;
  final Color color;
  final double size;
  final bool selected;
  final VoidCallback onTap;

  final String name;
  const _Swatch({
    required this.index,
    required this.name,
    required this.color,
    required this.size,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final palette = paletteOf(context);
    // The tap target is the cell, at least 48 dp, whatever the swatch is.
    return Semantics(
      identifier: 'accent-preset-${index.toString().padLeft(2, '0')}',
      button: true,
      selected: selected,
      label: name,
      // Its own tap, since the swatch's below is left out.
      onTap: onTap,
      excludeSemantics: true,
      child: InkResponse(
        onTap: onTap,
        radius: size / 2,
        child: SizedBox(
          width: size,
          height: size < 48 ? 48 : size,
          child: Center(
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: selected
                    ? Border.all(color: palette.textStrong, width: 3)
                    : null,
              ),
              child: selected
                  ? const Icon(Icons.check_rounded, color: Colors.white)
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}
