import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/app_theme.dart';
import 'package:opennutritracker/fork/display/contrast.dart';

/// A slider's inactive track reads at 3:1 on a card, a dialog and the canvas
/// (seam S605; G6 critique: dark tracks were close to invisible).
void main() {
  for (final (name, palette) in [
    ('light', AppPalette.light),
    ('dark', AppPalette.dark),
  ]) {
    test('the $name inactive slider track reaches 3:1', () {
      final track = buildAppTheme(palette).sliderTheme.inactiveTrackColor;
      expect(track, isNotNull);
      expect(contrastRatio(track!, palette.surface), greaterThanOrEqualTo(3));
      expect(contrastRatio(track, palette.canvas), greaterThanOrEqualTo(3));
    });
  }
}
