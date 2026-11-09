import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/fork/display/home_tiles.dart';
import 'package:opennutritracker/generated/l10n.dart';

// #1306: Home's water tile follows the food units, ml or fl oz.

Future<String> _shown(WidgetTester tester, {required bool imperial}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: const [S.delegate],
      supportedLocales: S.supportedLocales,
      home: Scaffold(
        body: WaterTile(ml: 500, goalMl: 2000, usesImperialUnits: imperial),
      ),
    ),
  );
  return [
    for (final t in tester.widgetList<RichText>(find.byType(RichText)))
      t.text.toPlainText(),
  ].join(' | ');
}

void main() {
  testWidgets('imperial: the amount and goal in fl oz', (tester) async {
    // 500 ml = 16.9 fl oz, 2000 ml = 67.6 fl oz.
    final shown = await _shown(tester, imperial: true);
    expect(shown, contains('17'));
    expect(shown, contains('/ 68 fl oz'));
    expect(shown, isNot(contains('500')));
  });

  testWidgets('metric: in ml', (tester) async {
    final shown = await _shown(tester, imperial: false);
    expect(shown, contains('500'));
    expect(shown, contains('/ 2000 ml'));
  });
}
