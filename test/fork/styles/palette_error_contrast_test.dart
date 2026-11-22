import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/fork/display/contrast.dart';

/// Error text sits on the canvas, on cards and in filled fields (seam S468).
void main() {
  for (final (name, palette) in [
    ('light', AppPalette.light),
    ('dark', AppPalette.dark),
  ]) {
    test(
      'the $name error colour reads at 4.5:1 on the canvas, a card and a field fill',
      () {
        final scheme = palette.colorScheme;
        expect(
          contrastRatio(scheme.error, palette.canvas),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          contrastRatio(scheme.error, palette.surface),
          greaterThanOrEqualTo(4.5),
        );
        // the filled input fill (app_theme inputDecorationTheme)
        expect(
          contrastRatio(scheme.error, palette.surfaceMuted),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          contrastRatio(scheme.onError, scheme.error),
          greaterThanOrEqualTo(4.5),
        );
      },
    );
  }
}
