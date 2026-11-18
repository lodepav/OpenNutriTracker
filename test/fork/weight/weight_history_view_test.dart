import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:opennutritracker/core/domain/entity/body_weight_unit_entity.dart';
import 'package:opennutritracker/core/domain/entity/weight_log_entity.dart';
import 'package:opennutritracker/core/presentation/widgets/app_card.dart';
import 'package:opennutritracker/fork/weight/weight_history_view.dart';
import 'package:opennutritracker/generated/l10n.dart';

import '../../helpers/ux_checks.dart';

// Seam S122: Weight history's chart, stats and rows.

final _today = DateTime(2026, 10, 25);
DateTime _ago(int days) =>
    DateTime(_today.year, _today.month, _today.day - days);

Future<List<WeightLogEntity>> _pump(
  WidgetTester tester,
  List<WeightLogEntity> entries, {
  BodyWeightUnit unit = BodyWeightUnit.kg,
  ValueChanged<WeightLogEntity>? onEdit,
}) async {
  final deleted = <WeightLogEntity>[];
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: const [
        S.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: S.supportedLocales,
      home: WeightHistoryView(
        entries: entries,
        unit: unit,
        targetWeightKg: null,
        onAdd: () {},
        onEdit: onEdit,
        onDelete: deleted.add,
        today: _today,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return deleted;
}

String _tile(WidgetTester tester, String label) {
  final tile = find.ancestor(
    of: find.text(label),
    matching: find.byType(Column),
  );
  return tester
      .widgetList<Text>(
        find.descendant(of: tile.first, matching: find.byType(Text)),
      )
      .map((t) => t.data)
      .join(' ');
}

/// The rows' changes, newest first.
List<String?> _changes(WidgetTester tester) => tester
    .widgetList<Text>(
      find.byWidgetPredicate(
        (w) =>
            w is Text &&
            (w.semanticsLabel?.endsWith('since the one before') ?? false),
      ),
    )
    .map((t) => t.data)
    .toList();

/// The text that breaks a line inside a word or a number, as "−0.20 k" over
/// "g": what [cutText] can't see, as such text wraps rather than cuts.
List<String> brokenInWords(WidgetTester tester, {Finder? within}) {
  final broken = <String>[];
  final inWord = RegExp(r'[\w.,−]');
  final texts = within == null
      ? find.byType(RichText)
      : find.descendant(of: within, matching: find.byType(RichText));
  for (final element in texts.evaluate()) {
    final paragraph = element.renderObject! as RenderParagraph;
    final text = paragraph.text.toPlainText();
    // a line starts where the caret drops to a lower line
    var y = paragraph
        .getOffsetForCaret(const TextPosition(offset: 0), Rect.zero)
        .dy;
    for (var i = 1; i < text.length; i++) {
      final next = paragraph
          .getOffsetForCaret(TextPosition(offset: i), Rect.zero)
          .dy;
      if (next > y + 0.5 &&
          inWord.hasMatch(text[i - 1]) &&
          inWord.hasMatch(text[i])) {
        broken.add(text);
        break;
      }
      y = next;
    }
  }
  return broken;
}

Future<void> _pumpLarge(
  WidgetTester tester,
  List<WeightLogEntity> entries, {
  double textScale = 2,
  BodyWeightUnit unit = BodyWeightUnit.kg,
}) async {
  await pumpOnPhone(
    tester,
    textScale: textScale,
    WeightHistoryView(
      entries: entries,
      unit: unit,
      targetWeightKg: null,
      onAdd: () {},
      onDelete: (_) {},
      today: _today,
    ),
  );
  // a 360 dp phone
  tester.view.physicalSize = const Size(945, 2340);
  await tester.pumpAndSettle();
}

void main() {
  // Newest first, as the screen hands them over.
  final entries = [
    WeightLogEntity(date: _ago(0), weightKg: 87.0),
    WeightLogEntity(date: _ago(1), weightKg: 87.2),
    WeightLogEntity(date: _ago(4), weightKg: 87.2, note: 'after a run'),
    WeightLogEntity(date: _ago(20), weightKg: 88.0),
    WeightLogEntity(date: _ago(60), weightKg: 89.0),
  ];

  testWidgets('each weigh-in: its day and its change from the one before', (
    tester,
  ) async {
    await _pump(tester, entries);
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Sun, Oct 25'), findsOneWidget);
    expect(find.text('Yesterday'), findsOneWidget);
    expect(find.text('Wednesday'), findsOneWidget);
    expect(find.text('Oct 21 · after a run'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Aug 26, 2026'), 200);
    // The oldest has nothing before it.
    expect(_changes(tester), [
      '\u22120.2\u00A0kg',
      '0.0\u00A0kg',
      '\u22120.8\u00A0kg',
      '\u22121.0\u00A0kg',
    ]);
    expect(find.textContaining('+'), findsNothing);
  });

  testWidgets('the stats are the trend and its change over the range', (
    tester,
  ) async {
    await _pump(tester, entries);
    expect(
      _tile(tester, 'Trend'),
      matches(RegExp('^Trend 8\\d\\.\\d\u00A0kg\$')),
    );
    expect(
      _tile(tester, '30 days'),
      matches(RegExp('^30 days \u2212\\d\\.\\d\u00A0kg\$')),
    );
    expect(
      _tile(tester, 'Per week'),
      matches(RegExp('^Per week \u2212\\d\\.\\d\\d\u00A0kg\$')),
    );

    await tester.tap(find.text('90 d'));
    await tester.pumpAndSettle();
    expect(find.text('90 days'), findsOneWidget);
    await tester.tap(find.text('All'));
    await tester.pumpAndSettle();
    expect(find.text('All time'), findsOneWidget);
  });

  testWidgets('the chart: the weigh-ins in the window under the trend', (
    tester,
  ) async {
    await _pump(tester, entries);
    final bars = tester.widget<LineChart>(find.byType(LineChart)).data;
    // Four weigh-ins in the last 30 days; the trend one a day from the
    // window's first day to today.
    expect(bars.lineBarsData[0].spots, hasLength(4));
    expect(bars.lineBarsData[1].spots, hasLength(30));
    expect(bars.lineBarsData[1].spots.last.x, 29);
    expect(
      bars.lineBarsData[1].barWidth,
      greaterThan(bars.lineBarsData[0].barWidth),
    );
  });

  testWidgets('in lb, the rows and the change are in lb', (tester) async {
    await _pump(tester, entries.take(2).toList(), unit: BodyWeightUnit.lb);
    expect(_changes(tester), ['\u22120.4\u00A0lbs']);
    expect(_tile(tester, 'Trend'), endsWith('lbs'));
  });

  testWidgets('a swipe left deletes the weigh-in, and it leaves at once', (
    tester,
  ) async {
    final deleted = await _pump(tester, entries);
    await tester.drag(find.text('Yesterday'), const Offset(-600, 0));
    await tester.pumpAndSettle();
    expect(deleted, [entries[1]]);
    expect(find.text('Yesterday'), findsNothing);
  });

  testWidgets('a tap offers Edit and Delete', (tester) async {
    final edited = <WeightLogEntity>[];
    final deleted = await _pump(tester, entries, onEdit: edited.add);
    await tester.tap(find.text('Yesterday'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsIdentifier('weigh-in-edit'));
    await tester.pumpAndSettle();
    expect(edited, [entries[1]]);
    expect(deleted, isEmpty);

    await tester.tap(find.text('Yesterday'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsIdentifier('weigh-in-delete'));
    await tester.pumpAndSettle();
    expect(deleted, [entries[1]]);
    expect(find.text('Yesterday'), findsNothing);
  });

  testWidgets('TalkBack deletes it from the row\'s actions', (tester) async {
    final deleted = await _pump(tester, entries);
    final row = find
        .ancestor(of: find.text('Yesterday'), matching: find.byType(Semantics))
        .evaluate()
        .map((e) => e.widget as Semantics)
        .firstWhere((s) => s.properties.customSemanticsActions != null);
    row.properties.customSemanticsActions![const CustomSemanticsAction(
      label: 'Delete',
    )]!();
    await tester.pumpAndSettle();
    expect(deleted, [entries[1]]);
  });

  test('All starts at the oldest weigh-in, and covers 30 days at least', () {
    expect(weightWindowDays(0, entries, _today), 61);
    expect(weightWindowDays(0, entries.take(2).toList(), _today), 30);
    expect(weightWindowDays(0, const [], _today), 30);
    expect(weightWindowDays(90, entries, _today), 90);
  });

  testWidgets('the view at 200% text: nothing cut, the targets and contrast', (
    tester,
  ) async {
    await checkScreen(
      tester,
      WeightHistoryView(
        entries: [
          for (var i = 0; i < 6; i++)
            WeightLogEntity(date: _ago(i * 3), weightKg: 80.0 + i),
        ],
        unit: BodyWeightUnit.kg,
        targetWeightKg: 75,
        onAdd: () {},
        onDelete: (_) {},
        today: _today,
      ),
    );
  });

  testWidgets('a change is spoken with its unit', (tester) async {
    await _pump(tester, entries.take(2).toList());
    final pill = tester.widget<Text>(find.text('−0.2 kg'));
    expect(pill.semanticsLabel, '−0.2 kg since the one before');
  });

  testWidgets('the range chips are spoken in words', (tester) async {
    await _pump(tester, entries);
    for (final (short, spoken) in [
      ('30 d', '30 days'),
      ('90 d', '90 days'),
      ('1 y', '1 year'),
      ('All', 'All time'),
    ]) {
      expect(tester.widget<Text>(find.text(short)).semanticsLabel, spoken);
    }
  });

  testWidgets('1,000 weigh-ins build only the rows on screen', (tester) async {
    await _pump(tester, [
      for (var i = 0; i < 1000; i++)
        WeightLogEntity(date: _ago(i), weightKg: 80.0 + (i % 7) / 10),
    ]);
    expect(find.byType(Dismissible).evaluate().length, lessThan(50));
  });

  testWidgets('Remove animations: the chart and a swipe do not animate', (
    tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await _pump(tester, entries);
    expect(
      tester.widget<LineChart>(find.byType(LineChart)).duration,
      Duration.zero,
    );
    final row = tester.widget<Dismissible>(find.byType(Dismissible).first);
    expect(row.movementDuration, Duration.zero);
    expect(row.resizeDuration, isNull);
  });

  testWidgets('on a tablet the content stays a phone column, centred', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(1600, 1200)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _pump(tester, entries);
    for (final finder in [
      find.byType(Dismissible).first,
      find
          .ancestor(
            of: find.byKey(const Key('weightHistoryChart')),
            matching: find.byType(AppCard),
          )
          .first,
      find.bySemanticsIdentifier('weight-history-add'),
    ]) {
      final rect = tester.getRect(finder);
      expect(rect.width, lessThanOrEqualTo(600), reason: '$finder');
      expect(rect.center.dx, closeTo(800, 1), reason: '$finder');
    }
  });

  testWidgets('at 2x text in stones the day keeps its line', (tester) async {
    await pumpOnPhone(
      tester,
      WeightHistoryView(
        entries: [
          WeightLogEntity(date: _ago(1), weightKg: 87.3),
          WeightLogEntity(date: _ago(2), weightKg: 87.9),
        ],
        unit: BodyWeightUnit.st,
        targetWeightKg: null,
        onAdd: () {},
        onDelete: (_) {},
        today: _today,
      ),
    );
    // a 360 dp phone
    tester.view.physicalSize = const Size(945, 2340);
    await tester.pumpAndSettle();
    final day = tester.getSize(find.text('Yesterday'));
    final size = Theme.of(
      tester.element(find.text('Yesterday')),
    ).textTheme.bodyLarge!.fontSize!;
    // One line at 2x: under two lines' height.
    expect(day.height, lessThan(size * 2 * 2));
    expect(cutText(tester), isEmpty);
  });

  for (final unit in [BodyWeightUnit.kg, BodyWeightUnit.lb]) {
    for (final scale in [1.0, 1.3, 1.5, 2.0]) {
      testWidgets('at ${scale}x text in ${unit.name} on a 360 dp phone no '
          'stat breaks inside a word', (tester) async {
        await _pumpLarge(tester, entries, textScale: scale, unit: unit);
        final stats = find.ancestor(
          of: find.text('Per week'),
          matching: find.byType(Flex),
        );
        expect(stats, findsOneWidget);
        expect(brokenInWords(tester, within: stats), isEmpty);
        expect(cutText(tester), isEmpty);
      });
    }
  }

  // The day and the weight side by side while they fit, one under the other
  // when they don't: no scale threshold, so no word broken in between.
  for (final unit in BodyWeightUnit.values) {
    for (final scale in [1.0, 1.3, 1.4, 1.5, 2.0]) {
      testWidgets('at ${scale}x text in ${unit.name} on a 360 dp phone no '
          'weigh-in row breaks inside a word', (tester) async {
        await _pumpLarge(tester, entries, textScale: scale, unit: unit);
        // 360 dp wide, tall enough to build every row
        tester.view.physicalSize = const Size(945, 7020);
        await tester.pumpAndSettle();
        final rows = find.byType(Dismissible);
        expect(rows, findsNWidgets(entries.length));
        expect(brokenInWords(tester, within: rows), isEmpty);
        expect(cutText(tester), isEmpty);
      });
    }
  }

  testWidgets('at 1x a day alone sits in the middle of its row', (
    tester,
  ) async {
    await _pumpLarge(tester, entries, textScale: 1);
    final title = find.text(DateFormat.yMMMd('en').format(_ago(60)));
    final row = find.ancestor(of: title, matching: find.byType(InkWell));
    expect(
      tester.getCenter(title).dy,
      moreOrLessEquals(tester.getCenter(row).dy, epsilon: 1),
    );
  });

  testWidgets('at 2x in stones a heavy weight and its change wrap, not '
      'overflow', (tester) async {
    await _pumpLarge(tester, [
      WeightLogEntity(date: _ago(4), weightKg: 160.4),
      WeightLogEntity(date: _ago(5), weightKg: 148.9),
    ], unit: BodyWeightUnit.st);
    tester.view.physicalSize = const Size(945, 7020);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(brokenInWords(tester, within: find.byType(Dismissible)), isEmpty);
    expect(cutText(tester), isEmpty);
  });

  testWidgets('at 1x a long note leaves the weight beside the day', (
    tester,
  ) async {
    await _pumpLarge(tester, [
      WeightLogEntity(
        date: _ago(4),
        weightKg: 87.2,
        note: 'after a long run along the river and a big breakfast',
      ),
    ], textScale: 1);
    final day = tester.getRect(find.text('Wednesday'));
    final weight = tester.getRect(
      find.descendant(
        of: find.byType(Dismissible),
        matching: find.textContaining('87.2'),
      ),
    );
    // the day's box fills the row up to the weight
    expect(weight.left, greaterThanOrEqualTo(day.right));
    expect(weight.top, lessThan(day.bottom));
  });

  // Seen at 2x: "88 kg" fit beside its date and "87.6 kg" didn't, so the
  // rows took turns.
  for (final (scale, beside) in [(1.0, true), (2.0, false)]) {
    testWidgets('at ${scale}x every weigh-in row takes the same layout', (
      tester,
    ) async {
      await _pumpLarge(tester, [
        WeightLogEntity(date: _ago(30), weightKg: 87.6),
        WeightLogEntity(date: _ago(32), weightKg: 88.0),
        WeightLogEntity(date: _ago(35), weightKg: 88.1),
        WeightLogEntity(date: _ago(38), weightKg: 88.0),
        WeightLogEntity(date: _ago(41), weightKg: 88.4),
      ], textScale: scale);
      tester.view.physicalSize = const Size(945, 7020);
      await tester.pumpAndSettle();
      final rows = find.byType(Dismissible).evaluate().toList();
      expect(rows, hasLength(5));
      final layouts = {
        for (final row in rows)
          () {
            final within = find.byElementPredicate((e) => e == row);
            final day = tester.getRect(
              find.descendant(of: within, matching: find.byType(Text)).first,
            );
            final weight = tester.getRect(
              find.descendant(
                of: within,
                matching: find.textContaining(RegExp(r'^\d+(\.\d)? kg$')),
              ),
            );
            return weight.top < day.bottom;
          }(),
      };
      expect(layouts, {beside});
    });
  }

  testWidgets('at 2x text the chart\'s last date stays inside the chart', (
    tester,
  ) async {
    await _pumpLarge(tester, entries);
    final chart = tester.getRect(find.byKey(const Key('weightHistoryChart')));
    final last = find.descendant(
      of: find.byKey(const Key('weightHistoryChart')),
      matching: find.text('Oct 25'),
    );
    expect(last, findsOneWidget);
    final rect = tester.getRect(last);
    expect(rect.right, lessThanOrEqualTo(chart.right + 0.5));
    expect(brokenInWords(tester), isEmpty);
    // "Oct" over "25": one line, under two lines' height
    final size = Theme.of(tester.element(last)).textTheme.labelSmall!.fontSize!;
    expect(rect.height, lessThan(size * 2 * 2));
    // the end dates pushed inward still clear the middle one
    final dates = [
      for (final e
          in find
              .descendant(
                of: find.byKey(const Key('weightHistoryChart')),
                matching: find.textContaining(RegExp(r'^(Sep|Oct) \d+$')),
              )
              .evaluate())
        tester.getRect(find.byElementPredicate((x) => x == e)),
    ]..sort((a, b) => a.left.compareTo(b.left));
    expect(dates, hasLength(3));
    for (var i = 1; i < dates.length; i++) {
      expect(dates[i].left, greaterThanOrEqualTo(dates[i - 1].right));
    }
  });

  testWidgets('the chosen range shows a check, not a text colour alone', (
    tester,
  ) async {
    await _pump(tester, [
      WeightLogEntity(date: DateTime(2026, 1, 1), weightKg: 80),
    ]);
    final chips = tester.widgetList<ChoiceChip>(find.byType(ChoiceChip));
    expect(chips.where((c) => c.selected), hasLength(1));
    expect(chips.every((c) => c.showCheckmark != false), isTrue);
  });
}
