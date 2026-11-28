import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:opennutritracker/core/domain/entity/tracked_day_entity.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/fork/display/chart_semantics.dart';
import 'package:opennutritracker/fork/trends/calories_detail.dart';
import 'package:opennutritracker/fork/trends/trends_widgets.dart';
import 'package:provider/provider.dart';

import '../../helpers/ux_checks.dart';
import 'trends_harness.dart';

// U2/U3: bars from zero, a week's or a month's average a bar over a long
// range, dates under any range past a week, and each day's own goal.

List<DateTime> _from(DateTime first, int count) => [
  for (var i = 0; i < count; i++)
    DateTime(first.year, first.month, first.day + i),
];

Widget _app(Widget child) => ChangeNotifierProvider(
  create: (_) => EnergyUnitProvider(usesKilojoules: false),
  child: MaterialApp(
    localizationsDelegates: const [
      S.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: S.supportedLocales,
    home: Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: child,
      ),
    ),
  ),
);

BarChartData _chart(WidgetTester tester) =>
    tester.widget<BarChart>(find.byType(BarChart)).data;

String _tip(BarChartData chart, int bar) {
  final group = chart.barGroups[bar];
  return chart.barTouchData.touchTooltipData
      .getTooltipItem(group, group.x, group.barRods.first, 0)!
      .text;
}

void main() {
  group('barSpans', () {
    test('a bar a day to a month', () {
      final spans = barSpans(_from(DateTime(2026, 10, 30), 30));
      expect(spans, hasLength(30));
      expect(spans.first, (start: 0, end: 1));
      expect(barSpans(_from(DateTime(2026, 10, 1), 31)), hasLength(31));
    });

    test('a week a bar to six months, the newest the last seven days', () {
      final spans = barSpans(_from(DateTime(2026, 8, 31), 90));
      expect(spans, hasLength(13));
      // 90 is 12 weeks and 6 days: the oldest bar is the 6 left over.
      expect(spans.first, (start: 0, end: 6));
      expect(spans[1], (start: 6, end: 13));
      expect(spans.last, (start: 83, end: 90));
      expect(barSpans(_from(DateTime(2026, 6, 1), 180)), hasLength(26));
    });

    test('a calendar month a bar past six months', () {
      final dates = _from(DateTime(2025, 11, 29), 365);
      final spans = barSpans(dates);
      // Nov 29–30 2025, then Dec to Oct whole, then Nov 1–28 2026.
      expect(spans, hasLength(13));
      expect(spans.first, (start: 0, end: 2));
      expect(dates[spans[1].start], DateTime(2025, 12, 1));
      expect(dates[spans[1].end - 1], DateTime(2025, 12, 31));
      expect(dates[spans.last.start], DateTime(2026, 11, 1));
      expect(spans.last.end, 365);
      // Every day in exactly one bar, in order.
      for (final (i, s) in spans.indexed.skip(1)) {
        expect(s.start, spans[i - 1].end);
      }
    });
  });

  testWidgets('a range header gives the year where the dates need it', (
    tester,
  ) async {
    late BuildContext context;
    await tester.pumpWidget(
      _app(
        Builder(
          builder: (c) {
            context = c;
            return const SizedBox();
          },
        ),
      ),
    );
    expect(
      rangeDatesText(context, _from(DateTime(2026, 10, 30), 30)),
      'Oct 30 – Nov 28',
    );
    expect(
      rangeDatesText(context, _from(DateTime(2025, 12, 30), 7)),
      'Dec 30, 2025 – Jan 5, 2026',
    );
    expect(
      rangeDatesText(context, _from(DateTime(2025, 11, 29), 365)),
      'Nov 2025 – Nov 2026',
    );
    expect(rangeDatesText(context, [DateTime(2026, 11, 28)]), 'Nov 28');
    expect(rangeDatesText(context, const []), '');
  });

  test('spanMeans averages the days logged and leaves an empty bar null', () {
    expect(
      spanMeans(
        [100, null, 200, null, null],
        [(start: 0, end: 3), (start: 3, end: 5)],
      ),
      [150, null],
    );
  });

  test('goalRange reaches from the bar top to the goal, either way', () {
    final up = goalRange(80, 120)!;
    expect((up.lowerBy, up.upperBy), (0, 40));
    final down = goalRange(150, 120)!;
    expect((down.lowerBy, down.upperBy), (30, 0));
    expect(goalRange(80, null), isNull);
    expect(goalRange(80, 0), isNull);
  });

  testWidgets('a daily chart draws its bars from zero, with a Goal legend', (
    tester,
  ) async {
    final dates = _from(DateTime(2026, 10, 30), 30);
    await tester.pumpWidget(
      _app(
        DailyBarChart(
          values: [for (var i = 0; i < 30; i++) i.isEven ? 78.0 : 140.0],
          dates: dates,
          color: Colors.teal,
          goal: 117,
          unit: 'g',
          label: 'Protein chart',
        ),
      ),
    );
    final chart = _chart(tester);
    expect(chart.minY, 0);
    expect(chart.barGroups, hasLength(30));
    expect([
      for (final g in chart.barGroups) g.barRods.single.fromY,
    ], everyElement(0));
    expect(find.text('Goal'), findsOneWidget);
    // A month has its first, middle and last dates under it.
    expect(find.text('Oct 30'), findsOneWidget);
    expect(find.text('Nov 13'), findsOneWidget);
    expect(find.text('Nov 28'), findsOneWidget);
    expect(_tip(chart, 0), '78 g\nOct 30');
  });

  testWidgets('a limit is called that in the legend', (tester) async {
    await tester.pumpWidget(
      _app(
        DailyBarChart(
          values: const [3, 5],
          dates: _from(DateTime(2026, 11, 27), 2),
          color: Colors.teal,
          goal: 6,
          goalLabel: 'Limit',
          unit: 'g',
          label: 'Salt chart',
        ),
      ),
    );
    expect(find.text('Limit'), findsOneWidget);
  });

  testWidgets('3 months are a week a bar, the tooltip the week and its '
      'average; a week is no day to tap', (tester) async {
    final dates = _from(DateTime(2026, 8, 31), 90);
    await tester.pumpWidget(
      _app(
        DailyBarChart(
          values: [for (var i = 0; i < 90; i++) i == 85 ? null : 100.0 + i % 7],
          dates: dates,
          color: Colors.teal,
          unit: 'g',
          label: 'Protein chart',
          onTap: (_) {},
          selected: 87,
        ),
      ),
    );
    final chart = _chart(tester);
    expect(chart.barGroups, hasLength(13));
    // Nov 22–28, Nov 26 not logged: the mean of the six days logged.
    expect(_tip(chart, 12), 'Average 103 g\nNov 22 – Nov 28');
    expect(chart.barTouchData.touchCallback, isNull);
    // The week the picked day is in stays bright.
    expect(chart.barGroups.last.barRods.single.color!.a, 1);
    expect(chart.barGroups.first.barRods.single.color!.a, lessThan(1));
    expect(find.text('Aug 31'), findsOneWidget);
    expect(find.text('Nov 22'), findsOneWidget);
  });

  testWidgets('a range switch draws the new bars afresh', (tester) async {
    Widget chart(int count) => _app(
      DailyBarChart(
        values: List.filled(count, 50),
        dates: _from(DateTime(2026, 11, 29 - count), count),
        color: Colors.teal,
        unit: 'g',
        label: 'Fibre chart',
      ),
    );
    await tester.pumpWidget(chart(7));
    final before = tester.state(find.byType(BarChart));
    await tester.pumpWidget(chart(30));
    expect(tester.state(find.byType(BarChart)), isNot(same(before)));
  });

  testWidgets('a year of calories is a month a bar, dates under it, and a '
      'goal that changed ticked on each bar', (tester) async {
    final dates = _from(DateTime(2025, 11, 29), 365);
    await tester.pumpWidget(
      _app(
        MacroEnergyChart(
          state: loaded(
            rangeDays: dates.length,
            days: [
              for (final d in dates)
                TrackedDayEntity(
                  day: d,
                  calorieGoal: d.isBefore(DateTime(2026, 6)) ? 2500 : 2200,
                  caloriesTracked: 2000,
                  carbsTracked: 250,
                  fatTracked: 44.4,
                  proteinTracked: 100,
                ),
            ],
          ),
          dates: dates,
        ),
      ),
    );
    final chart = _chart(tester);
    expect(chart.barGroups, hasLength(13));
    expect(chart.extraLinesData.horizontalLines, isEmpty);
    final rods = [for (final g in chart.barGroups) g.barRods.single];
    expect(rods.first.toY, closeTo(2000, 1e-6));
    expect(rods.first.toYErrorRange!.upperBy, closeTo(500, 1e-6));
    expect(rods.last.toYErrorRange!.upperBy, closeTo(200, 1e-6));
    expect(rods.first.rodStackItems.last.toY, closeTo(2000, 1e-6));
    expect(_tip(chart, 1), 'Average 2000 kcal\nDec 2025');
    expect(find.text('Nov 2025'), findsOneWidget);
    expect(find.text('Nov 2026'), findsOneWidget);
    expect(find.text('Goal'), findsOneWidget);
  });

  testWidgets('a grouped chart speaks its bars, a daily one its days', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    Future<String> spoken(int count) async {
      final dates = _from(DateTime(2026, 11, 29 - count), count);
      await tester.pumpWidget(
        _app(
          MacroEnergyChart(
            state: loaded(
              rangeDays: count,
              days: [
                for (final (i, d) in dates.indexed)
                  TrackedDayEntity(
                    day: d,
                    calorieGoal: 2500,
                    // 1000 one day a week, 3000 the others.
                    caloriesTracked: i % 7 == 0 ? 1000 : 3000,
                  ),
              ],
            ),
            dates: dates,
          ),
        ),
      );
      return tester.getSemantics(find.byType(ChartSemantics)).label;
    }

    expect(
      await spoken(30),
      'Calories by macro chart, between 1000 and 3000 kcal a day',
    );
    // Whole weeks average 2714; the oldest, 6 days with one 1000, 2667.
    expect(
      await spoken(90),
      "Calories by macro chart, a week's average a bar, between 2667 and "
      '2714 kcal a day',
    );
    expect(
      await spoken(365),
      startsWith("Calories by macro chart, a month's average a bar, between"),
    );
    handle.dispose();
  });

  testWidgets('one goal over the range stays one dashed line', (tester) async {
    final dates = _from(DateTime(2026, 11, 22), 7);
    await tester.pumpWidget(
      _app(
        MacroEnergyChart(
          state: loaded(
            rangeDays: dates.length,
            days: [
              for (final d in dates)
                TrackedDayEntity(
                  day: d,
                  calorieGoal: 2500,
                  caloriesTracked: 2000,
                ),
            ],
          ),
          dates: dates,
        ),
      ),
    );
    final chart = _chart(tester);
    expect(chart.extraLinesData.horizontalLines.single.y, 2500);
    expect([
      for (final g in chart.barGroups) g.barRods.single.toYErrorRange,
    ], everyElement(isNull));
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('at ${scale}x a month of bars keeps its dates whole and apart '
        'on a 360 dp phone', (tester) async {
      await pumpOnPhone(
        tester,
        SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: DailyBarChart(
            values: List.filled(30, 50),
            dates: _from(DateTime(2026, 10, 30), 30),
            color: Colors.teal,
            unit: 'g',
            label: 'Fibre chart',
          ),
        ),
        textScale: scale,
      );
      tester.view
        ..physicalSize = const Size(360, 800)
        ..devicePixelRatio = 1;
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final labels = [
        for (final t in ['Oct 30', 'Nov 13', 'Nov 28'])
          if (find.text(t).evaluate().isNotEmpty) tester.getRect(find.text(t)),
      ];
      expect(labels.length, greaterThanOrEqualTo(2));
      final chart = tester.getRect(find.byType(BarChart));
      for (final (i, a) in labels.indexed) {
        expect(a.left, greaterThanOrEqualTo(chart.left - 0.5));
        expect(a.right, lessThanOrEqualTo(chart.right + 0.5));
        for (final b in labels.skip(i + 1)) {
          expect(a.overlaps(b), isFalse, reason: '$a and $b');
        }
      }
    });
  }
}
