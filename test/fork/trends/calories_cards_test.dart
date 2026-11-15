import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/fork/trends/calories_detail.dart';
import 'package:opennutritracker/fork/trends/detail_stats.dart';

// The Calories page's cards of how the days went and of the weekend.

Future<void> _pump(WidgetTester tester, Widget card) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: card)),
    ),
  );
}

WeekPart _part(double? balance) => (
  days: 4,
  kcal: 2000,
  carbs: null,
  fat: null,
  protein: null,
  balance: balance,
);

void main() {
  group('DaysWentCard', () {
    testWidgets('the size of the misses, in the card\'s unit', (tester) async {
      await _pump(
        tester,
        DaysWentCard(
          outcomes: (
            onTarget: 3,
            under: 2,
            over: 5,
            logged: 10,
            highest: null,
            lowest: null,
            overBy: 412.4,
            underBy: 38.6,
            topThreeShare: 0.624,
          ),
          week: false,
          valueText: (_, g) => '${g.round()} g',
        ),
      );
      expect(find.text('Over by, on average'), findsOneWidget);
      expect(find.text('412 g'), findsOneWidget);
      expect(find.text('Under by, on average'), findsOneWidget);
      expect(find.text('39 g'), findsOneWidget);
      expect(find.text("Top 3 days' share of the excess"), findsOneWidget);
      expect(find.text('62%'), findsOneWidget);
    });

    testWidgets('no over days: no row of them', (tester) async {
      await _pump(
        tester,
        const DaysWentCard(
          outcomes: (
            onTarget: 3,
            under: 1,
            over: 0,
            logged: 4,
            highest: null,
            lowest: null,
            overBy: null,
            underBy: 300,
            topThreeShare: null,
          ),
          week: true,
        ),
      );
      expect(find.text('Over by, on average'), findsNothing);
      expect(find.text("Top 3 days' share of the excess"), findsNothing);
      expect(find.text('300 kcal'), findsOneWidget);
    });
  });

  group('WeekendCard', () {
    testWidgets('what the weekend gives back, over four weeks', (tester) async {
      await _pump(
        tester,
        WeekendCard(
          split: (weekdays: _part(-500), weekend: _part(500)),
          rangeDays: 28,
        ),
      );
      expect(
        find.text("Weekends give back about 40% of the weekdays' deficit."),
        findsOneWidget,
      );
    });

    testWidgets('more than the deficit says so', (tester) async {
      await _pump(
        tester,
        WeekendCard(
          split: (weekdays: _part(-200), weekend: _part(800)),
          rangeDays: 90,
        ),
      );
      expect(
        find.text("Weekends give back more than the weekdays' deficit."),
        findsOneWidget,
      );
    });

    testWidgets('a week is too short to say', (tester) async {
      await _pump(
        tester,
        WeekendCard(
          split: (weekdays: _part(-500), weekend: _part(500)),
          rangeDays: 7,
        ),
      );
      expect(find.textContaining('give back'), findsNothing);
    });
  });
}
