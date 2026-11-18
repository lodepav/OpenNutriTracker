import 'package:flutter/material.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';

/// WCAG 2.x contrast ratio between two opaque colours.
double contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return la > lb ? (la + 0.05) / (lb + 0.05) : (lb + 0.05) / (la + 0.05);
}

/// [color] as a chart mark on [surface]: unchanged when it already stands
/// out at 3:1 (WCAG 1.4.11), else moved in lightness, away from the
/// surface, until it does. The hue stays.
Color chartSafe(Color color, Color surface) {
  if (contrastRatio(color, surface) >= 3) return color;
  final darken = surface.computeLuminance() > 0.18;
  var hsl = HSLColor.fromColor(color);
  while (contrastRatio(hsl.toColor(), surface) < 3) {
    final l = hsl.lightness + (darken ? -0.01 : 0.01);
    // black or white always reaches 3:1 on the palette's surfaces
    if (l <= 0 || l >= 1) return darken ? Colors.black : Colors.white;
    hsl = hsl.withLightness(l);
  }
  return hsl.toColor();
}

/// The user's accent as a chart colour on a card: buttons keep the accent
/// as picked, while a line or bar drawn in it reaches 3:1 on the card.
Color chartAccent(BuildContext context) => chartSafe(
  Theme.of(context).colorScheme.primary,
  paletteOf(context).surface,
);
