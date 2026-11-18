import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/styles/accent_colors.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/app_theme.dart';
import 'package:opennutritracker/fork/display/contrast.dart';

// An outlined button's label reads at 4.5:1 on the canvas and the card with
// every accent preset, as a text button's does: You's "Switch" was raw yellow.

void main() {
  testWidgets('an outlined button reads at 4.5:1 on every accent', (
    tester,
  ) async {
    final low = <String>[];
    for (final base in [AppPalette.light, AppPalette.dark]) {
      for (final accent in accentPresetColors) {
        // a fresh app each time: one theme animates into the next
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(
          MaterialApp(
            theme: buildAppTheme(base.withAccent(accent)),
            home: Scaffold(
              body: OutlinedButton(onPressed: () {}, child: const Text('Go')),
            ),
          ),
        );
        final label = tester
            .renderObject<RenderParagraph>(find.text('Go'))
            .text
            .style!
            .color!;
        for (final surface in [base.canvas, base.surface]) {
          final r = contrastRatio(label, surface);
          if (r < 4.5) {
            low.add(
              '${base.brightness.name} '
              '${accent.toARGB32().toRadixString(16)}: ${r.toStringAsFixed(2)}',
            );
          }
        }
      }
    }
    expect(low, isEmpty);
  });
}
