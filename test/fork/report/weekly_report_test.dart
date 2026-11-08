import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/tracked_day_entity.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/fork/report/weekly_report.dart';

TrackedDayEntity _day(
  int month,
  int day,
  double kcal, {
  double goal = 2000,
  double? protein = 150,
}) => TrackedDayEntity(
  day: DateTime(2026, month, day, 8),
  calorieGoal: goal,
  caloriesTracked: kcal,
  proteinGoal: 140,
  proteinTracked: protein,
  carbsGoal: 200,
  carbsTracked: 180,
  fatGoal: 70,
  fatTracked: 60,
);

// Friday 23 October 2026; the clocks change on Sunday the 25th.
final _today = DateTime(2026, 10, 23, 18);

void main() {
  test('weeks run Monday to Sunday, newest first, means over logged days '
      'only', () {
    final weeks = weeklyReports(
      [
        _day(10, 12, 1800),
        _day(10, 18, 2200, goal: 2200),
        _day(10, 19, 1900),
        _day(10, 20, 0), // opened, nothing logged
        _day(10, 23, 2300, protein: null),
      ],
      DateTime(2026, 10, 10),
      _today,
    );

    // The week of 5 October, in range but with nothing logged, is left out.
    expect(weeks.map((w) => (w.monday, w.daysLogged, w.daysShown)), [
      (DateTime(2026, 10, 19), 2, 5),
      (DateTime(2026, 10, 12), 2, 7),
    ]);
    expect(weeks.first.kcal, (eaten: 2100.0, goal: 2000.0));
    expect(weeks.first.protein, isNull);
    expect(weeks.first.fat, (eaten: 60.0, goal: 70.0));
    expect(weeks[1].kcal, (eaten: 2000.0, goal: 2100.0));
    expect(weeks[1].protein, (eaten: 150.0, goal: 140.0));
  });

  test('a week across the change of the clocks is one week', () {
    final weeks = weeklyReports(
      [_day(10, 25, 2000), _day(10, 26, 2000)],
      DateTime(2026, 10, 1),
      DateTime(2026, 10, 31),
    );
    expect(weeks.map((w) => (w.monday, w.daysShown)), [
      (DateTime(2026, 10, 26), 6),
      (DateTime(2026, 10, 19), 7),
    ]);
  });

  testWidgets('the card shows each week, and nothing with no logs', (
    tester,
  ) async {
    Future<void> pump(List<TrackedDayEntity> days) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WeeklyReportCard(
            days: days,
            rangeDays: 7,
            palette: AppPalette.light,
            clock: () => _today,
          ),
        ),
      ),
    );

    await pump([_day(10, 23, 0)]);
    expect(find.text('Weekly report'), findsNothing);

    await pump([_day(10, 17, 1800), _day(10, 19, 1900), _day(10, 22, 2300)]);
    expect(find.byKey(const ValueKey('week-2026-10-19')), findsOneWidget);
    expect(find.text('Oct 19 – Oct 25'), findsOneWidget);
    expect(find.text('This week'), findsOneWidget);
    expect(find.text('2 of 5 days logged'), findsOneWidget);
    expect(find.text('2100 / 2000 kcal'), findsOneWidget);
    expect(find.text('+100 kcal · On target'), findsOneWidget);
    // Carbs, fat, protein, each against its goal, in both weeks.
    expect(find.text('Carbs'), findsNWidgets(2));
    expect(find.text('180 / 200 g'), findsNWidgets(2));
    expect(find.text('60 / 70 g'), findsNWidgets(2));
    expect(find.text('150 / 140 g'), findsNWidgets(2));
    // The range starts on Saturday the 17th.
    expect(find.text('1 of 2 days logged'), findsOneWidget);
    expect(find.text('-200 kcal · On target'), findsOneWidget);
    // One card read aloud per week.
    expect(
      tester.getSemantics(find.byKey(const ValueKey('week-2026-10-19'))).label,
      startsWith('Oct 19 – Oct 25, this week, 2 of 5 days logged, '),
    );
  });

  test('each day of the week is marked logged, missed or outside the '
      'range', () {
    final weeks = weeklyReports(
      [_day(10, 17, 1800), _day(10, 19, 1900), _day(10, 22, 2300)],
      DateTime(2026, 10, 17),
      _today,
    );
    const l = WeekDayMark.logged,
        m = WeekDayMark.missed,
        o = WeekDayMark.outside;
    expect(weeks[0].marks, [l, m, m, l, m, o, o]);
    expect(weeks[1].marks, [o, o, o, o, o, l, m]);
  });

  test('energy within 10% of the goal is on target', () {
    expect(energyStanding((eaten: 2200, goal: 2000)), EnergyStanding.onTarget);
    expect(energyStanding((eaten: 1800, goal: 2000)), EnergyStanding.onTarget);
    expect(energyStanding((eaten: 2201, goal: 2000)), EnergyStanding.over);
    expect(energyStanding((eaten: 1799, goal: 2000)), EnergyStanding.under);
  });
}
