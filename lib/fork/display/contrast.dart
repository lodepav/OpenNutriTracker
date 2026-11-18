import 'package:flutter/material.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';

/// WCAG 2.x contrast ratio between two opaque colours.
double contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return la > lb ? (la + 0.05) / (lb + 0.05) : (lb + 0.05) / (la + 0.05);
}

/// [color] moved in lightness, darker when [darken], until it reaches
/// [min]:1 against [other]. The hue stays.
Color shiftUntil(Color color, Color other, double min, {required bool darken}) {
  var hsl = HSLColor.fromColor(color);
  while (contrastRatio(hsl.toColor(), other) < min) {
    final l = hsl.lightness + (darken ? -0.01 : 0.01);
    // black or white always reaches 4.5:1 on the palette's surfaces
    if (l <= 0 || l >= 1) return darken ? Colors.black : Colors.white;
    hsl = hsl.withLightness(l);
  }
  return hsl.toColor();
}

/// [color] on [surface] at [min]:1 or more: unchanged when it already is,
/// else moved in lightness, away from the surface, until it is.
Color _floor(Color color, Color surface, double min) =>
    contrastRatio(color, surface) >= min
    ? color
    : shiftUntil(
        color,
        surface,
        min,
        darken: surface.computeLuminance() > 0.18,
      );

/// [color] as a chart mark on [surface]: unchanged when it already stands
/// out at 3:1 (WCAG 1.4.11), else moved in lightness, away from the
/// surface, until it does. The hue stays.
Color chartSafe(Color color, Color surface) => _floor(color, surface, 3);

/// [color] as text on [surface]: as [chartSafe], to 4.5:1 (WCAG 1.4.3).
Color textSafe(Color color, Color surface) => _floor(color, surface, 4.5);

/// [p]'s accent as text, at 4.5:1 on both its canvas and its card: a text
/// button sits on either.
Color textAccentOf(AppPalette p) =>
    textSafe(textSafe(p.accent, p.canvas), p.surface);

/// The user's accent as a chart colour on a card: filled buttons keep the
/// accent as picked, while a line or bar drawn in it reaches 3:1 on the card.
Color chartAccent(BuildContext context) => chartSafe(
  Theme.of(context).colorScheme.primary,
  paletteOf(context).surface,
);

/// The user's accent as text, at 4.5:1 on the canvas and the card.
Color textAccent(BuildContext context) => textAccentOf(
  paletteOf(context).withAccent(Theme.of(context).colorScheme.primary),
);
