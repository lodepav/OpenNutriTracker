import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/body_weight_unit_entity.dart';
import 'package:opennutritracker/core/domain/entity/weight_log_entity.dart';
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
    expect(_changes(tester), ['-0.2', '0.0', '-0.8', '-1.0']);
    expect(find.textContaining('+'), findsNothing);
  });

  testWidgets('the stats are the trend and its change over the range', (
    tester,
  ) async {
    await _pump(tester, entries);
    expect(_tile(tester, 'Trend'), matches(RegExp(r'^Trend 8\d\.\d kg$')));
    expect(_tile(tester, '30 days'), matches(RegExp(r'^30 days -\d\.\d$')));
    expect(_tile(tester, 'Per week'), matches(RegExp(r'^Per week -\d\.\d\d$')));

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
    expect(_changes(tester), ['-0.4']);
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
}
