import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/styles/accent_colors.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/app_theme.dart';
import 'package:opennutritracker/fork/add/add_sheet.dart';
import 'package:opennutritracker/fork/display/contrast.dart';

// With a pale picked accent, Home's Left/Eaten switch drew its unselected
// label and the quick-action tiles their icons in the raw accent: yellow
// on white was about 1.4:1, on the beige tile about 1.16:1.

String _name(AppPalette base, Color accent, double r) =>
    '${base.brightness.name} '
    '${accent.toARGB32().toRadixString(16)}: ${r.toStringAsFixed(2)}';

Future<void> _pumpSegments(WidgetTester tester, AppPalette p) => _pump(
  tester,
  p,
  SegmentedButton<bool>(
    showSelectedIcon: false,
    segments: const [
      ButtonSegment(value: false, label: Text('Left')),
      ButtonSegment(value: true, label: Text('Eaten')),
    ],
    selected: const {false},
    onSelectionChanged: (_) {},
  ),
);

Future<void> _pumpTile(WidgetTester tester, AppPalette p) => _pump(
  tester,
  p,
  Builder(
    builder: (context) => Row(
      children: [
        actionTile(
          context,
          id: 'tile',
          icon: Icons.bolt_rounded,
          label: 'Quick add',
          onTap: () {},
        ),
      ],
    ),
  ),
);

Color _labelColor(WidgetTester tester) =>
    tester.renderObject<RenderParagraph>(find.text('Eaten')).text.style!.color!;

Color _iconColor(WidgetTester tester) => tester
    .renderObject<RenderParagraph>(
      find.descendant(of: find.byType(Icon), matching: find.byType(RichText)),
    )
    .text
    .style!
    .color!;

Future<void> _pump(WidgetTester tester, AppPalette p, Widget body) async {
  // a fresh app each time: one theme animates into the next
  await tester.pumpWidget(const SizedBox());
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(p),
      home: Scaffold(body: body),
    ),
  );
}

void main() {
  testWidgets('an unselected segment reads at 4.5:1 on every accent', (
    tester,
  ) async {
    final low = <String>[];
    for (final base in [AppPalette.light, AppPalette.dark]) {
      for (final accent in accentPresetColors) {
        await _pumpSegments(tester, base.withAccent(accent));
        final label = _labelColor(tester);
        for (final surface in [base.canvas, base.surface]) {
          final r = contrastRatio(label, surface);
          if (r < 4.5) low.add(_name(base, accent, r));
        }
      }
    }
    expect(low, isEmpty, reason: low.join('\n'));
  });

  testWidgets('a quick-action icon stands out at 3:1 on every accent', (
    tester,
  ) async {
    final low = <String>[];
    for (final base in [AppPalette.light, AppPalette.dark]) {
      for (final accent in accentPresetColors) {
        await _pumpTile(tester, base.withAccent(accent));
        final icon = _iconColor(tester);
        final r = contrastRatio(icon, base.surfaceMuted);
        if (r < 3) low.add(_name(base, accent, r));
      }
    }
    expect(low, isEmpty, reason: low.join('\n'));
  });

  testWidgets('the default green keeps its look in light and dark', (
    tester,
  ) async {
    for (final p in [AppPalette.light, AppPalette.dark]) {
      await _pumpSegments(tester, p);
      // the text accent: light's moves a shade, to 4.5:1 on muted panels,
      // and dark's is the accent (accent_floor_test)
      expect(_labelColor(tester), textAccentOf(p), reason: p.brightness.name);
      await _pumpTile(tester, p);
      expect(_iconColor(tester), p.accent, reason: p.brightness.name);
    }
  });
}
