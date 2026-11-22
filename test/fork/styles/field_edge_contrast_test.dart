import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/app_theme.dart';
import 'package:opennutritracker/fork/display/contrast.dart';

// Seam S552 (G2-39): a text field's edge reads at 3:1 (WCAG 1.4.11) on the
// canvas, a card and its own fill; the fill alone was about 1.1:1.
void main() {
  for (final (name, palette) in [
    ('light', AppPalette.light),
    ('dark', AppPalette.dark),
  ]) {
    test('the $name theme draws a field edge at 3:1', () {
      final side = buildAppTheme(
        palette,
      ).inputDecorationTheme.enabledBorder!.borderSide;
      expect(side.style, BorderStyle.solid);
      for (final ground in [
        palette.canvas,
        palette.surface,
        palette.surfaceMuted,
      ]) {
        expect(contrastRatio(side.color, ground), greaterThanOrEqualTo(3));
      }
    });

    testWidgets('the $name field keeps an edge while it shows an error', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(palette),
          home: const Scaffold(
            body: TextField(decoration: InputDecoration(errorText: 'Too long')),
          ),
        ),
      );
      final decorator = tester.widget<InputDecorator>(
        find.byType(InputDecorator),
      );
      final theme = Theme.of(tester.element(find.byType(TextField)));
      final shown = decorator.decoration.applyDefaults(
        theme.inputDecorationTheme,
      );
      final side = (shown.errorBorder ?? shown.border)!.borderSide;
      expect(side.style, BorderStyle.solid);
    });
  }
}
