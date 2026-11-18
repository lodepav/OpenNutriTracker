import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_service.dart';
import 'package:opennutritracker/fork/trends/detail_widgets.dart';
import 'package:opennutritracker/fork/trends/expenditure_detail.dart';
import 'package:opennutritracker/fork/trends/trend_stats.dart';
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
    expect(finishedDays(1), '1 finished day');
    expect(finishedDays(6), '6 finished days');
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
}
