import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/weight_log_entity.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_service.dart';
import 'package:opennutritracker/fork/trends/trend_stats.dart';
import 'package:opennutritracker/fork/trends/trends_overview.dart';
import 'package:opennutritracker/fork/trends/trends_widgets.dart';
import 'package:provider/provider.dart';

import '../../helpers/ux_checks.dart';
import 'trends_harness.dart';

const _bar = Color(0xFF000001);
const _below = Color(0xFF000002);

Future<RenderObject> _spark(WidgetTester tester, DaySeries values) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 300,
          child: Sparkline(values: values, color: _bar, negativeColor: _below),
        ),
      ),
    ),
  );
  return tester.renderObject(
    find.descendant(
      of: find.byType(Sparkline),
      matching: find.byType(CustomPaint),
    ),
  );
}

RRect _r(double x, double y, double h) => RRect.fromRectAndRadius(
  Rect.fromLTWH(x, y, 16, h),
  const Radius.circular(2),
);

void main() {
  // Three slots of 100 across 300, a bar 16 wide in the middle of each.
  testWidgets('bars stand on zero: the lowest day is a bar, not a stub', (
    tester,
  ) async {
    final box = await _spark(tester, [10, 20, null]);
    expect(
      box,
      paints
        ..rrect(rrect: _r(42, 13, 13), color: _bar)
        ..rrect(rrect: _r(142, 0, 26), color: _bar)
        // A day with nothing logged keeps the stub, in the track's grey.
        ..rrect(rrect: _r(242, 24, 2), color: AppPalette.light.surfaceMuted),
    );
  });

  testWidgets('a deficit hangs below zero in its own colour', (tester) async {
    final box = await _spark(tester, [10, -10, null]);
    expect(
      box,
      paints
        ..rrect(rrect: _r(42, 0, 13), color: _bar)
        ..rrect(rrect: _r(142, 13, 13), color: _below)
        ..rrect(rrect: _r(242, 11, 2)),
    );
  });

  testWidgets('a small deficit beside a big surplus stays inside the chart', (
    tester,
  ) async {
    // 500 and −10: zero sits 25.5 down a 26 high chart; the 2 dp bar
    // would end below it.
    final box = await _spark(tester, [500, -10, null]);
    expect(
      box,
      paints
        ..rrect()
        ..rrect(rrect: _r(142, 24, 2), color: _below),
    );
  });

  testWidgets('a week all in deficit hangs from the top', (tester) async {
    final box = await _spark(tester, [-5, -10, null]);
    expect(
      box,
      paints
        ..rrect(rrect: _r(42, 0, 13), color: _below)
        ..rrect(rrect: _r(142, 0, 26), color: _below)
        ..rrect(rrect: _r(242, 0, 2)),
    );
  });

  testWidgets('days of exactly zero sit as stubs on the floor', (tester) async {
    final box = await _spark(tester, [0, 0, null]);
    expect(
      box,
      paints
        ..rrect(rrect: _r(42, 24, 2), color: _bar)
        ..rrect(rrect: _r(142, 24, 2), color: _bar),
    );
  });

  testWidgets('at 1x on a 360 dp phone a tile leaves no word alone on a '
      'line and cuts nothing', (tester) async {
    final history = [
      for (var i = -6; i <= 0; i++)
        ExpenditureDay(
          date: day(i),
          expenditureKcal: 3000 + i * 10.0,
          intakeKcal: 2500,
          settled: true,
        ),
    ];
    final state = loaded(
      weight: [
        WeightLogEntity(date: day(-30), weightKg: 81),
        WeightLogEntity(date: day(-6), weightKg: 80),
        WeightLogEntity(date: day(0), weightKg: 79.4),
      ],
    );
    showAllTiles();
    await pumpOnPhone(
      tester,
      ChangeNotifierProvider(
        create: (_) => EnergyUnitProvider(usesKilojoules: false),
        child: SingleChildScrollView(
          child: Builder(
            builder: (context) {
              final dates = [for (var i = -6; i <= 0; i++) day(i)];
              final tiles = trendTiles(
                context,
                state,
                dates: dates,
                history: history,
                micros: null,
                measurements: null,
                open: (_) {},
              );
              // Two up, as the grid lays them at 360 dp.
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Column(
                  children: [
                    for (var i = 0; i + 1 < 4; i += 2)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: tiles[i]),
                          const SizedBox(width: 8),
                          Expanded(child: tiles[i + 1]),
                        ],
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
      textScale: 1,
    );
    tester.view.physicalSize = const Size(360 * 2.625, 2340);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(cutText(tester), isEmpty);
    for (final word in ['week', 'day']) {
      final paragraph = tester
          .renderObjectList<RenderParagraph>(find.byType(RichText))
          .firstWhere((p) => p.text.toPlainText().contains(word));
      final text = paragraph.text.toPlainText();
      final lines = TextPainter(
        text: paragraph.text,
        textDirection: TextDirection.ltr,
        textScaler: paragraph.textScaler,
      )..layout(maxWidth: paragraph.size.width);
      addTearDown(lines.dispose);
      var start = 0;
      while (start < text.length) {
        final line = lines.getLineBoundary(TextPosition(offset: start));
        final words = text
            .substring(line.start, line.end)
            .replaceAll(' ', ' ')
            .trim()
            .split(RegExp(r'\s+'));
        expect(words.length, greaterThan(1), reason: 'a lone word in "$text"');
        if (line.end <= start) break;
        start = line.end;
      }
    }
  });
}
