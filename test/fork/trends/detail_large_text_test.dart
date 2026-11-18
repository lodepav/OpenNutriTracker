import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/body_weight_unit_entity.dart';
import 'package:opennutritracker/core/domain/entity/weight_log_entity.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_service.dart';
import 'package:opennutritracker/fork/trends/calories_detail.dart';
import 'package:opennutritracker/fork/trends/detail_widgets.dart';
import 'package:opennutritracker/fork/trends/expenditure_detail.dart';
import 'package:opennutritracker/fork/trends/trend_detail.dart';
import 'package:opennutritracker/fork/trends/trend_stats.dart';
import 'package:opennutritracker/fork/trends/weight_detail.dart';
import 'package:opennutritracker/fork/trends/trends_widgets.dart';

import '../../helpers/ux_checks.dart';
import 'trends_harness.dart';

// The Trends recritique: day counts that say which days, one change for a
// week, and the Expenditure page and figure grid at 200% on a 360 dp phone.

Future<void> _pumpAt360(
  WidgetTester tester,
  Widget body, {
  double textScale = 2,
}) async {
  await pumpOnPhone(tester, body, textScale: textScale);
  tester.view
    ..physicalSize = const Size(360, 800)
    ..devicePixelRatio = 1;
  await tester.pump();
}

/// The Expenditure page's body as its page lays it out.
Widget _page(List<ExpenditureDay> history, List<DateTime> dates) => Builder(
  builder: (context) => ListView(
    padding: const EdgeInsets.all(16),
    children: expenditureBody(
      context,
      loaded(),
      history,
      dates: dates,
      pills: const SizedBox(),
      loadIntakes: (_, _) async => const [],
    ),
  ),
);

/// A month of estimates rising 2 kcal a day, logged at 2500 a day.
final _history = [
  for (var i = -30; i <= 0; i++)
    ExpenditureDay(
      date: day(i),
      expenditureKcal: 3000 + i * 2.0,
      intakeKcal: 2500,
      settled: true,
    ),
];

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

Finder _inHeader(String text) => find.descendant(
  of: find.byType(StatHeader),
  matching: find.textContaining(text, findRichText: true),
);

Finder _inTable(String text) => find.descendant(
  of: find.byKey(const ValueKey('expenditure-changes')),
  matching: find.textContaining(text),
);

void main() {
  test('a count of finished days says so', () {
    expect(finishedDays(1), '1 finished\u00A0day');
    expect(finishedDays(6), '6 finished\u00A0days');
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('at ${scale}x a row of finished days fits a 360 phone', (
      tester,
    ) async {
      await _pumpAt360(
        tester,
        Padding(
          padding: const EdgeInsets.all(16),
          child: TrendRows(
            rows: [
              (
                label: 'On target (within 10%)',
                value: '2 of ${finishedDays(6)}',
              ),
              (label: 'In deficit', value: '6 of ${finishedDays(6)}'),
            ],
          ),
        ),
        textScale: scale,
      );
      expect(tester.takeException(), isNull);
      expect(cutText(tester), isEmpty);
    });
  }

  // 1.5 is the largest scale whose rows stay side by side.
  for (final (width, scale) in [(360.0, 2.0), (411.0, 2.0), (360.0, 1.5)]) {
    testWidgets('at ${scale}x on a ${width.round()} dp phone no row value '
        'leaves a word alone on a line or breaks one', (tester) async {
      await pumpOnPhone(
        tester,
        textScale: scale,
        SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // The Calories page's, and Protein's in grams.
              for (final unit in ['kcal', 'g'])
                DaysWentCard(
                  outcomes: (
                    onTarget: 6,
                    under: 0,
                    over: 0,
                    logged: 6,
                    highest: (value: 2898, date: DateTime(2026, 11, 18)),
                    lowest: (value: 2292, date: DateTime(2026, 11, 17)),
                    overBy: null,
                    underBy: null,
                    topThreeShare: null,
                  ),
                  // Both by date, the longer way a day is written.
                  today: DateTime(2026, 11, 19),
                  valueText: (_, v) => '${v.round()} $unit',
                ),
              // The Energy balance page's.
              TrendRows(
                rows: [(label: 'In deficit', value: '6 of ${finishedDays(6)}')],
              ),
            ],
          ),
        ),
      );
      tester.view
        ..physicalSize = Size(width, 1600)
        ..devicePixelRatio = 1;
      await tester.pumpAndSettle();
      final texts = find.descendant(
        of: find.byType(TrendRow),
        matching: find.byType(RichText),
      );
      var checked = 0;
      final lone = <List<String>>[], broken = <List<String>>[];
      for (var i = 0; i < texts.evaluate().length; i++) {
        final lines = _lines(tester, texts.at(i));
        if (!RegExp(r'finished|·').hasMatch(lines.join())) continue;
        checked++;
        for (final (j, line) in lines.indexed) {
          final words = line
              .replaceAll('\u00A0', ' ')
              .trim()
              .split(RegExp(r'\s+'));
          if (words.length < 2) lone.add(lines);
          if (j < lines.length - 1 && !line.endsWith(' ')) broken.add(lines);
        }
      }
      // On target, Highest and Lowest twice, and In deficit.
      expect(checked, 7);
      expect(broken, isEmpty, reason: 'a word broken across lines');
      // Side by side at 1.5x a lone word was there before the joins.
      if (scale == 2) expect(lone, isEmpty, reason: 'a lone word on a line');
      expect(cutText(tester), isEmpty);
    });
  }

  testWidgets('at 200% stacked rows fill the card, labels on one edge', (
    tester,
  ) async {
    await _pumpAt360(
      tester,
      SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            DaysWentCard(
              outcomes: (
                onTarget: 6,
                under: 0,
                over: 0,
                logged: 6,
                highest: (value: 2898, date: DateTime(2026, 11, 18)),
                lowest: (value: 2292, date: DateTime(2026, 11, 17)),
                overBy: null,
                underBy: null,
                topThreeShare: null,
              ),
              today: DateTime(2026, 11, 19),
            ),
            TrendRows(
              rows: [
                (label: 'In deficit', value: '6 of ${finishedDays(6)}'),
                (label: 'In surplus', value: '0 days'),
                (label: 'Eaten a day', value: '2500 kcal'),
              ],
            ),
          ],
        ),
      ),
    );
    for (final card in [find.byType(DaysWentCard), find.byType(TrendRows)]) {
      final rows = find.descendant(of: card, matching: find.byType(TrendRow));
      expect(rows, findsAtLeastNWidgets(3));
      final widths = {
        for (final r in rows.evaluate())
          tester.getSize(find.byWidget(r.widget)).width,
      };
      final lefts = {
        for (final r in rows.evaluate())
          tester
              .getTopLeft(
                find.descendant(
                  of: find.byWidget(r.widget),
                  matching: find.text((r.widget as TrendRow).label),
                ),
              )
              .dx,
      };
      // As wide as the card's content, the column the rows are in.
      final column = find
          .ancestor(of: rows.first, matching: find.byType(Column))
          .first;
      expect(widths, {tester.getSize(column).width}, reason: '$card');
      expect(lefts, hasLength(1), reason: '$card');
    }
  });

  testWidgets('the header\'s change at 1W is the table\'s 7 days', (
    tester,
  ) async {
    await _pumpAt360(
      tester,
      _page(_history, windowDates(day(0), 7)),
      textScale: 1,
    );
    // Now against 7 days before: 2 kcal a day for 7 days, as the table.
    expect(_inHeader('+14'), findsOneWidget);
    expect(_inTable('+14'), findsOneWidget);
    expect(_inHeader('+12'), findsNothing);
  });

  testWidgets('a range older than the estimate changes from its first day', (
    tester,
  ) async {
    await _pumpAt360(
      tester,
      _page(_history, windowDates(day(0), 90)),
      textScale: 1,
    );
    expect(_inHeader('+60'), findsOneWidget);
  });

  testWidgets('at 200% the last 30 days and the changes stack, words whole', (
    tester,
  ) async {
    await _pumpAt360(tester, _page(_history, windowDates(day(0), 7)));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // Each change: its figure and unit on one line.
    for (final f in [_inTable('+14'), _inTable('was 2986')]) {
      await tester.scrollUntilVisible(f, 100);
      expect(_lines(tester, f), hasLength(1), reason: '$f');
    }
    expect(cutText(tester), isEmpty);

    // The sum: one figure under another, its label on one line.
    await tester.scrollUntilVisible(find.text('expenditure a day'), 100);
    await tester.pumpAndSettle();
    final eaten = find.text('eaten a day');
    final burnt = find.text('expenditure a day');
    expect(_lines(tester, burnt), hasLength(1));
    expect(
      tester.getTopLeft(burnt).dy,
      greaterThan(tester.getTopLeft(eaten).dy),
    );
    expect(cutText(tester), isEmpty);
  });

  testWidgets('at 200% the figure grid is one column', (tester) async {
    await _pumpAt360(
      tester,
      const FigureGrid(
        tiles: [
          FigureTile(label: 'Days logged', value: '21', unit: 'of 30'),
          FigureTile(label: 'Formula estimate', value: '2630', unit: 'kcal'),
        ],
      ),
    );
    final first = tester.getRect(find.text('Days logged'));
    final second = tester.getRect(find.text('Formula estimate'));
    expect(second.top, greaterThan(first.bottom));
    expect(second.left, first.left);
  });

  testWidgets('at 100% the figure grid stays two across', (tester) async {
    await _pumpAt360(
      tester,
      const FigureGrid(
        tiles: [
          FigureTile(label: 'Days logged', value: '21', unit: 'of 30'),
          FigureTile(label: 'Formula estimate', value: '2630', unit: 'kcal'),
        ],
      ),
      textScale: 1,
    );
    expect(
      tester.getTopLeft(find.text('Formula estimate')).dx,
      greaterThan(tester.getTopLeft(find.text('Days logged')).dx),
    );
  });

  /// The Weight page's body over 100 days losing 0.2 kg a day, so the
  /// 90-day chip holds a wide figure, "−18.0 kg".
  Widget weightPage(BodyWeightUnit unit) => Builder(
    builder: (context) => ListView(
      padding: const EdgeInsets.all(16),
      children: weightDetailBody(
        context,
        loaded(
          unit: unit,
          weight: [
            for (var i = -99; i <= 0; i++)
              WeightLogEntity(date: day(i), weightKg: 80 - i * 0.2),
          ],
        ),
        windowDates(day(0), 7),
        TrendsDeps(
          expenditure: ValueNotifier(Future.value(const <ExpenditureDay>[])),
          weightCard: (_) => const SizedBox(),
          waterCard: (_) => const SizedBox(),
          loadIntakes: (_, _) async => const [],
        ),
        const SizedBox(),
      ),
    ),
  );

  for (final (unit, label) in [
    (BodyWeightUnit.kg, 'kg'),
    (BodyWeightUnit.lb, 'lbs'),
    (BodyWeightUnit.st, 'st'),
  ]) {
    for (final scale in [1.0, 1.5, 2.0]) {
      testWidgets('at ${scale}x the ${unit.name} change chips say $label, '
          'each on one line', (tester) async {
        final semantics = tester.ensureSemantics();
        await _pumpAt360(tester, weightPage(unit), textScale: scale);
        await tester.pumpAndSettle();
        final values = find.descendant(
          of: find.byType(ChangeChips),
          matching: find.textContaining(' $label'),
        );
        await tester.scrollUntilVisible(values.last, 100);
        expect(values, findsNWidgets(weightChangeSpans.length));
        for (final (i, f)
            in values.evaluate().map((e) => find.byWidget(e.widget)).indexed) {
          final text = tester.widget<Text>(f).data!;
          expect(text, matches(RegExp('^[−+]?\\d+\\.\\d $label\$')));
          expect(_lines(tester, f), hasLength(1), reason: text);
          // How far the chip shrinks it: a one-line text can still be
          // squeezed. At large text the chips grow instead; at 1x a kg or
          // st change of a few tenths shows full size.
          final shrink = tester.getRect(f).width / tester.getSize(f).width;
          if (scale > 1 || (i == 0 && unit != BodyWeightUnit.lb)) {
            expect(shrink, closeTo(1, 0.001), reason: text);
          } else {
            expect(shrink, greaterThan(0.8), reason: text);
          }
        }
        // The unit is spoken once. The chips read as one node here, a line
        // each.
        expect(
          find.bySemanticsLabel(
            RegExp('^Over 90 days: −\\d+\\.\\d $label\$', multiLine: true),
          ),
          findsOneWidget,
        );
        expect(cutText(tester), isEmpty);
        semantics.dispose();
      });
    }
  }
}
