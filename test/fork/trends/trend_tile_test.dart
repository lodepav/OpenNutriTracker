import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/fork/trends/trends_widgets.dart';

Widget _app(Widget child, {Brightness brightness = Brightness.light}) =>
    MaterialApp(
      theme: ThemeData(brightness: brightness),
      home: Scaffold(body: SizedBox(width: 200, child: child)),
    );

TrendTile _tile({String? spokenLabel, String? note}) => TrendTile(
  id: 'trends-tile-calories',
  label: 'Calories · avg',
  value: '2573',
  suffix: '/ 2925 kcal',
  chart: const SizedBox(height: 20),
  onTap: () {},
  spokenLabel: spokenLabel,
  note: note,
);

double _contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  return la > lb ? (la + 0.05) / (lb + 0.05) : (lb + 0.05) / (la + 0.05);
}

void main() {
  testWidgets('a tile is read once, as a button, by its spoken label', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _app(_tile(spokenLabel: 'Calories, daily average 2573 of 2925 kcal')),
    );
    final node = tester.getSemantics(find.byType(TrendTile));
    expect(node.label, 'Calories, daily average 2573 of 2925 kcal');
    expect(node, isSemantics(isButton: true, hasTapAction: true));
    expect(find.bySemanticsLabel(RegExp('2573')), findsOneWidget);
    handle.dispose();
  });

  testWidgets('without one it reads its label, value and note', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_app(_tile(note: 'over limit')));
    expect(find.text('over limit'), findsOneWidget);
    final node = tester.getSemantics(find.byType(TrendTile));
    expect(node.label, 'Calories · avg, 2573 / 2925 kcal, over limit');
    expect(node, isSemantics(isButton: true, hasTapAction: true));
    handle.dispose();
  });

  for (final brightness in Brightness.values) {
    testWidgets('the note is amber at 4.5:1 on the ${brightness.name} tile', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(_tile(note: 'over limit'), brightness: brightness),
      );
      final color = tester.widget<Text>(find.text('over limit')).style!.color!;
      final surface = brightness == Brightness.dark
          ? AppPalette.dark.surface
          : AppPalette.light.surface;
      expect(_contrast(color, surface), greaterThanOrEqualTo(4.5));
    });
  }

  test('a unit is held whole, a phrase still wraps', () {
    expect(keepUnits('kcal/day'), 'kcal/\u2060day');
    expect(keepUnits('kg · -0.16/wk'), 'kg · -0.16/\u2060wk');
    expect(keepUnits('/ 2925 kcal'), '/ 2925\u00A0kcal');
    expect(keepUnits('measure your waist'), 'measure your waist');
    expect(keepUnits('/ 68 fl oz'), '/ 68\u00A0fl\u00A0oz');
  });

  testWidgets('the range pills say their span in words, the picked one '
      'selected', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_app(RangePills(rangeDays: 30, onChanged: (_) {})));
    for (final (label, words) in [
      ('1W', '1 week'),
      ('1M', '1 month'),
      ('3M', '3 months'),
      ('6M', '6 months'),
      ('1Y', '1 year'),
      ('All', 'All'),
    ]) {
      expect(find.text(label), findsOneWidget);
      expect(tester.getSemantics(find.text(label)).label, words);
    }
    expect(
      tester.getSemantics(find.text('1M')),
      isSemantics(isSelected: true, isButton: true),
    );
    expect(
      tester.getSemantics(find.text('1W')),
      isSemantics(isSelected: false, hasTapAction: true),
    );
    handle.dispose();
  });
}
