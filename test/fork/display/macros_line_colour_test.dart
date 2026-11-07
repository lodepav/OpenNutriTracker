import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/fork/display/meal_macros_line.dart';

void main() {
  testWidgets('each macro is a muted shade of its own colour (D38)', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: MacrosLine(carbs: 20, fat: 3, protein: 4)),
      ),
    );
    final text = tester.widget<RichText>(find.byType(RichText).first);
    final colours = <String, Color?>{};
    // by hand: visitChildren skips the spans that carry no text of their own
    void walk(InlineSpan span) {
      if (span is! TextSpan) return;
      final children = span.children ?? const <InlineSpan>[];
      if (children.firstOrNull case TextSpan(:final text?)) {
        colours.putIfAbsent(text, () => span.style?.color);
      }
      children.forEach(walk);
    }

    walk(text.text);
    const p = AppPalette.light;
    expect(colours['C'], mutedMacroColor(p.carbsColor, p));
    expect(colours['F'], mutedMacroColor(p.fatColor, p));
    expect(colours['P'], mutedMacroColor(p.proteinColor, p));
    // quiet: between the colour and the muted text
    expect(colours['C'], isNot(p.carbsColor));
  });

  test('the shades stay readable as small text on a white card', () {
    double contrast(Color a, Color b) {
      final (la, lb) = (a.computeLuminance(), b.computeLuminance());
      return (la > lb ? la + 0.05 : lb + 0.05) /
          (la > lb ? lb + 0.05 : la + 0.05);
    }

    const p = AppPalette.light;
    for (final c in [p.carbsColor, p.fatColor, p.proteinColor]) {
      expect(contrast(mutedMacroColor(c, p), p.surface), greaterThan(4.5));
    }
  });
}
