import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/tracked_day_entity.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_service.dart';
import 'package:opennutritracker/fork/trends/balance_detail.dart';
import 'package:opennutritracker/fork/trends/calories_detail.dart';
import 'package:opennutritracker/fork/trends/value_axis.dart';

import '../../helpers/ux_checks.dart';
import 'trends_harness.dart';

// The value axis on the Calories and Energy balance charts, and the bar
// charts that share it.

/// [count] days to today.
List<DateTime> _dates(int count) => [
  for (var i = 1 - count; i <= 0; i++) day(i),
];

Finder _onChart(String text) =>
    find.descendant(of: find.byType(BarChart), matching: find.text(text));

/// The bars and the axis side by side at the chart's width.
void _expectBarsFit(WidgetTester tester) {
  final chart = tester.widget<BarChart>(find.byType(BarChart)).data;
  final width = tester.getSize(find.byType(BarChart)).width;
  final axis = chart.titlesData.rightTitles.sideTitles;
  expect(axis.showTitles, isTrue);
  final rods = [for (final g in chart.barGroups) ...g.barRods];
  final bars = rods.fold(0.0, (sum, r) => sum + r.width);
  expect(bars, lessThan(width - axis.reservedSize));
  // No two labels on top of each other.
  final labels = find.descendant(
    of: find.byType(BarChart),
    matching: find.byType(Text),
  );
  final rects = [
    for (final e in labels.evaluate()) tester.getRect(find.byWidget(e.widget)),
  ];
  for (final (i, a) in rects.indexed) {
    for (final b in rects.skip(i + 1)) {
      expect(a.overlaps(b), isFalse, reason: '$a and $b');
    }
  }
}

void main() {
  group('axisTicks', () {
    test('an all-positive range from 0 gets round values from 0', () {
      final a = axisTicks(0, 2925 * 1.12);
      expect(a.step, 1000);
      expect(a.ticks, [0, 1000, 2000, 3000]);
      expect((a.min, a.max), (0, 2925 * 1.12));
    });

    test('a step of a power of ten goes down to half of it', () {
      // log10(1000) comes out a hair under 3
      expect(axisTicks(0, 1600 * 1.12).ticks, [0, 500, 1000, 1500]);
      expect(axisTicks(1135, 2865).ticks, [1500, 2000, 2500]);
    });

    test('a range off 0 is labelled inside it, not widened', () {
      final a = axisTicks(191, 269);
      expect(a.step, 20);
      expect(a.ticks, [200, 220, 240, 260]);
      expect((a.min, a.max), (191, 269));
    });

    test('a finer step that would crowd is not taken', () {
      // 50 labels 2; 20 would label 7.
      final a = axisTicks(2010, 2140);
      expect(a.step, 50);
      expect(a.ticks, [2050, 2100]);
    });

    test('a range across 0 gets values either side, 0 among them', () {
      final a = axisTicks(-375, 275, bothSides: true);
      expect(a.step, 200);
      expect(a.ticks, [-200, 0, 200]);
      expect((a.min, a.max), (-375, 275));
    });

    test('a lopsided range across 0 is widened to a step below it', () {
      final a = axisTicks(-150, 1000, bothSides: true);
      expect(a.step, 500);
      expect(a.min, -500);
      expect(a.max, 1000);
      expect(a.ticks, [-500, 0, 500, 1000]);
    });

    test('a week of deficits is not widened over the padding above 0', () {
      final a = axisTicks(-575, 75);
      expect((a.min, a.max), (-575, 75));
      expect(a.ticks, [-400, -200, 0]);
    });

    test('a fractional range steps in decimals', () {
      final a = axisTicks(0.4, 1.3);
      expect(a.step, 0.2);
      expect(a.ticks.map((t) => axisLabel(t, a.step)), [
        '0.4',
        '0.6',
        '0.8',
        '1.0',
        '1.2',
      ]);
    });

    test('an empty range does not loop', () {
      expect(axisTicks(5, 5).ticks, [5]);
    });
  });

  group('atLeastTwoTicks', () {
    test("a flat week's half-kilo step goes down to 0.2", () {
      // 86.75 to 87.35: 0.5 lands only on 87.0.
      expect(atLeastTwoTicks(86.75, 87.35, 0.5), 0.2);
    });

    test('a step that already labels two is kept', () {
      expect(atLeastTwoTicks(61.88, 62.92, 0.5), 0.5);
      expect(atLeastTwoTicks(77, 103, 5), 5);
    });

    test('a tiny range goes down past one step', () {
      // The weight chart pads by at least 0.1 a side, so 0.1 always does.
      expect(atLeastTwoTicks(86.92, 87.13, 0.5), 0.1);
    });

    test('an empty range does not loop', () {
      expect(atLeastTwoTicks(5, 5, 0.5), 0.5);
    });
  });

  group('dateInterval', () {
    /// The days a chart labels: each interval from 0, and [last].
    List<int> labelled(int last, int step) => {
      for (var d = 0; d <= last; d += step) d,
      last,
    }.toList();

    test('a week with room labels every other day', () {
      expect(labelled(6, dateInterval(6, 50, 58)), [0, 2, 4, 6]);
    });

    test('a month at 200% drops the label that ran into the last', () {
      // 300 px over 29 days, labels 108 px: 0, 11, 22 put 22 by 29.
      final step = dateInterval(29, 300 / 29, 108);
      expect(labelled(29, step), [0, 15, 29]);
    });

    test('no two labels are closer than a label', () {
      for (final last in [6, 29, 89, 179, 364]) {
        for (final room in [40.0, 70.0, 120.0]) {
          final dayWidth = 300 / last;
          final days = labelled(last, dateInterval(last, dayWidth, room));
          for (var i = 1; i < days.length; i++) {
            expect(
              (days[i] - days[i - 1]) * dayWidth,
              greaterThanOrEqualTo(room),
              reason: '$days over $last days, $room px',
            );
          }
        }
      }
    });

    test('too narrow for more: only the ends', () {
      expect(dateInterval(6, 10, 200), 6);
      expect(dateInterval(0, 10, 50), 1);
    });
  });

  test('labels have a minus sign and no -0', () {
    expect(axisLabel(-200, 100), '−200');
    expect(axisLabel(-1e-12, 0.5), '0');
    expect(axisLabel(2000, 1000), '2000');
  });

  for (final scale in [1.0, 2.0]) {
    for (final count in [7, 90]) {
      testWidgets('at ${scale}x the balance chart over $count days has an '
          'axis that fits a 360 dp phone', (tester) async {
        final dates = _dates(count);
        await pumpOnPhone(
          tester,
          Builder(
            builder: (context) => ListView(
              padding: const EdgeInsets.all(16),
              children: balanceBody(
                context,
                loaded(rangeDays: count),
                [
                  for (final (i, d) in dates.indexed)
                    ExpenditureDay(
                      date: d,
                      // Over a month bars are weeks to the last day, so
                      // the swing is by week.
                      expenditureKcal:
                          (count > 31 ? (count - 1 - i) ~/ 7 : i).isEven
                          ? 2800
                          : 2300,
                      intakeKcal: 2500,
                      settled: true,
                    ),
                ],
                dates: dates,
                pills: const SizedBox(),
              ),
            ),
          ),
          textScale: scale,
        );
        tester.view
          ..physicalSize = const Size(360, 800)
          ..devicePixelRatio = 1;
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        // -300 and +200 a day: round values either side of 0.
        expect(_onChart('−200'), findsOneWidget);
        expect(_onChart('0'), findsOneWidget);
        expect(_onChart('200'), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(BarChart),
            matching: find.textContaining('kcal'),
          ),
          findsNothing,
        );
        _expectBarsFit(tester);
      });

      testWidgets('at ${scale}x the calories chart over $count days has an '
          'axis that fits a 360 dp phone', (tester) async {
        final dates = _dates(count);
        await pumpOnPhone(
          tester,
          SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: MacroEnergyChart(
              state: loaded(
                rangeDays: count,
                days: [
                  for (final d in dates)
                    TrackedDayEntity(
                      day: d,
                      calorieGoal: 2925,
                      caloriesTracked: 2572.6,
                      carbsTracked: 69.5,
                      fatTracked: 81,
                      proteinTracked: 93,
                    ),
                ],
              ),
              dates: dates,
            ),
          ),
          textScale: scale,
        );
        tester.view
          ..physicalSize = const Size(360, 800)
          ..devicePixelRatio = 1;
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        for (final label in ['0', '1000', '2000', '3000']) {
          expect(_onChart(label), findsOneWidget);
        }
        _expectBarsFit(tester);
      });
    }
  }
}
