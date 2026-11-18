import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/fork/meal_detail/food_page.dart';
import 'package:provider/provider.dart';

import '../../helpers/ux_checks.dart';

// The Trends recritique: at 200% on a 360 dp phone "74%" fell to a line of
// its own, and the ring's figure touched its stroke.

Future<void> _pump(
  WidgetTester tester, {
  bool kj = false,
  FoodMacroRing ring = const FoodMacroRing(
    kcal: 1166,
    carbs: 216,
    fat: 9,
    protein: 48,
  ),
}) async {
  await pumpOnPhone(
    tester,
    ChangeNotifierProvider(
      create: (_) => EnergyUnitProvider(usesKilojoules: kj),
      child: Padding(padding: const EdgeInsets.all(16), child: ring),
    ),
  );
  tester.view
    ..physicalSize = const Size(360, 800)
    ..devicePixelRatio = 1;
  await tester.pump();
}

/// The text of each line [f] was laid out on.
List<String> _lines(WidgetTester tester, Finder f) {
  final p = tester.renderObject<RenderParagraph>(f);
  final text = p.text.toPlainText();
  final lines = <String>[];
  double? top;
  for (var i = 0; i < text.length; i++) {
    final boxes = p.getBoxesForSelection(
      TextSelection(baseOffset: i, extentOffset: i + 1),
    );
    final at = boxes.isEmpty ? top : boxes.first.top.roundToDouble();
    if (lines.isEmpty || at != top) {
      lines.add('');
      top = at;
    }
    lines[lines.length - 1] += text[i];
  }
  return lines;
}

void main() {
  testWidgets('at 200% each share has a line under its macro', (tester) async {
    await _pump(tester);
    expect(tester.takeException(), isNull);
    expect(cutText(tester), isEmpty);
    for (final name in ['Carbs', 'Fat', 'Protein']) {
      final lines = [
        for (final l in _lines(tester, find.textContaining(name))) l.trim(),
      ];
      expect(lines.last, matches(RegExp(r'^\d+%$')), reason: '$lines');
      expect(lines.where((l) => l.endsWith(name)), hasLength(1));
    }
  });

  testWidgets('at 200% the widest share keeps its words whole', (tester) async {
    await _pump(
      tester,
      ring: const FoodMacroRing(kcal: 480, carbs: 0, fat: 0, protein: 120),
    );
    final lines = [
      for (final l in _lines(tester, find.textContaining('Protein'))) l.trim(),
    ];
    expect(lines.last, '100%', reason: '$lines');
    expect(lines.where((l) => l.endsWith('Protein')), hasLength(1));
    expect(cutText(tester), isEmpty);
  });

  testWidgets('at 100% the share stays beside its macro', (tester) async {
    await pumpOnPhone(
      tester,
      const FoodMacroRing(kcal: 1166, carbs: 216, fat: 9, protein: 48),
      textScale: 1,
    );
    expect(find.text('216 g Carbs\u00A0·\u00A076%'), findsOneWidget);
  });

  for (final kj in [false, true]) {
    testWidgets(
      'at 200% the ring\'s figure sits inside it (${kj ? 'kJ' : 'kcal'})',
      (tester) async {
        await _pump(tester, kj: kj);
        final ring = tester.getRect(
          find.byWidgetPredicate(
            (w) =>
                w is CustomPaint &&
                '${w.painter.runtimeType}' == '_RingPainter',
          ),
        );
        // Inside the stroke: 12 of the 104 ring.
        final inner = ring.shortestSide / 2 - 12;
        for (final f in [
          find.textContaining(RegExp(r'^\d{4}$')),
          find.text(kj ? 'kJ' : 'kcal'),
        ]) {
          final r = tester.getRect(f);
          for (final corner in [
            r.topLeft,
            r.topRight,
            r.bottomLeft,
            r.bottomRight,
          ]) {
            expect(
              (corner - ring.center).distance,
              lessThanOrEqualTo(inner),
              reason: '$f $corner',
            );
          }
        }
      },
    );
  }
}
