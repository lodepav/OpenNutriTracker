import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/styles/accent_colors.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/app_theme.dart';

// An Undo on its snackbar reads at 4.5:1 with every accent preset, light and
// dark: Material takes the action's colour from inversePrimary, which the
// palette leaves to fall back to the accent's on-colour.

double _ratio(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  return la > lb ? (la + 0.05) / (lb + 0.05) : (lb + 0.05) / (la + 0.05);
}

void main() {
  testWidgets('the snackbar action reads at 4.5:1 on every accent', (
    tester,
  ) async {
    final low = <String>[];
    for (final base in [AppPalette.light, AppPalette.dark]) {
      for (final accent in accentPresetColors) {
        final key = GlobalKey<ScaffoldMessengerState>();
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(
          MaterialApp(
            theme: buildAppTheme(base.withAccent(accent)),
            scaffoldMessengerKey: key,
            home: const Scaffold(),
          ),
        );
        key.currentState!.showSnackBar(
          SnackBar(
            content: const Text('Deleted'),
            action: SnackBarAction(label: 'Undo', onPressed: () {}),
          ),
        );
        await tester.pumpAndSettle();
        final bar = tester
            .widget<Material>(
              find
                  .ancestor(
                    of: find.text('Deleted'),
                    matching: find.byType(Material),
                  )
                  .first,
            )
            .color!;
        final label = tester
            .renderObject<RenderParagraph>(find.text('Undo'))
            .text
            .style!
            .color!;
        final r = _ratio(label, bar);
        if (r < 4.5) {
          low.add(
            '${base.brightness.name} ${accent.toARGB32().toRadixString(16)}: ${r.toStringAsFixed(2)}',
          );
        }
      }
    }
    expect(low, isEmpty);
  });
}
