import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/tracked_day_entity.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_service.dart';
import 'package:opennutritracker/fork/trends/detail_stats.dart';
import 'package:opennutritracker/fork/trends/trend_stats.dart';

// The numbers behind the round-3 Expenditure and Calories pages.

final _today = DateTime(2026, 10, 26);

DateTime _d(int offset) =>
    DateTime(_today.year, _today.month, _today.day + offset);

ExpenditureDay _spent(int offset, double kcal, {double? ate}) => ExpenditureDay(
  date: _d(offset),
  expenditureKcal: kcal,
  intakeKcal: ate,
  settled: true,
);

TrackedDayEntity _tracked(
  int offset, {
  double kcal = 2000,
  double goal = 2000,
  double? carbs,
  double? fat,
  double? protein,
  double? carbsGoal,
  double? fatGoal,
  double? proteinGoal,
}) => TrackedDayEntity(
  day: _d(offset).add(const Duration(hours: 9)),
  calorieGoal: goal,
  caloriesTracked: kcal,
  carbsTracked: carbs,
  fatTracked: fat,
  proteinTracked: protein,
  carbsGoal: carbsGoal,
  fatGoal: fatGoal,
  proteinGoal: proteinGoal,
);

void main() {
  group('expenditureChanges', () {
    test('now against each span back, and what it was then', () {
      final history = [
        for (var i = -30; i <= 0; i++) _spent(i, 3000 + i * 2.0),
      ];
      final changes = expenditureChanges(history);
      expect([for (final c in changes) c.days], [3, 7, 14, 30, 90]);
      expect(changes[0].change, 6);
      expect(changes[0].then, 2994);
      expect(changes[3].change, 60);
      expect(changes[3].then, 2940);
      // The history starts 30 days back.
      expect(changes[4].change, isNull);
      expect(changes[4].then, isNull);
    });

    test('a fall reads negative', () {
      final changes = expenditureChanges([_spent(-7, 3100), _spent(0, 3050)]);
      expect(changes[1].change, -50);
      expect(changes[0].change, isNull);
    });

    test('nothing without a history', () {
      expect(
        expenditureChanges(const []).every((c) => c.change == null),
        isTrue,
      );
    });
  });

  group('expenditureBreakdown', () {
    test('eaten plus what the weight made up is burnt, over logged days', () {
      final b = expenditureBreakdown([
        _spent(-40, 9999, ate: 0),
        for (var i = -29; i <= 0; i++)
          _spent(i, 3000, ate: i.isEven ? 2500 : null),
      ])!;
      expect(b.of, 30);
      expect(b.logged, 15);
      expect(b.eaten, 2500);
      expect(b.burnt, 3000);
      expect(b.fromWeight, 500);
    });

    test('eating past it stores the rest as weight', () {
      final b = expenditureBreakdown([_spent(0, 2800, ate: 3000)])!;
      expect(b.fromWeight, -200);
      expect(b.of, 1);
    });

    test('null with no day logged', () {
      expect(expenditureBreakdown([_spent(0, 3000)]), isNull);
    });
  });

  group('dayOutcomes', () {
    test('within a tenth of the goal is on target', () {
      final week = windowDates(_today, 7);
      final o = dayOutcomes([
        _tracked(-6, kcal: 1900),
        _tracked(-5, kcal: 2200),
        _tracked(-4, kcal: 1700),
        _tracked(-3, kcal: 2300),
        _tracked(-2, kcal: 0),
        // Outside the window.
        _tracked(-9, kcal: 5000),
      ], week);
      expect(o.logged, 4);
      expect(o.onTarget, 2);
      expect(o.under, 1);
      expect(o.over, 1);
      expect(o.highest, (kcal: 2300.0, date: _d(-3)));
      expect(o.lowest, (kcal: 1700.0, date: _d(-4)));
    });

    test('no highest or lowest without a logged day', () {
      final o = dayOutcomes(const [], windowDates(_today, 7));
      expect(o.logged, 0);
      expect(o.highest, isNull);
    });
  });

  group('weekdays', () {
    test('the mean by weekday, and the one that stands out', () {
      // Oct 26 2026 is a Monday.
      final days = [
        for (var w = 0; w < 4; w++)
          for (var i = 0; i < 7; i++)
            _tracked(-w * 7 - i, kcal: i == 2 ? 2700 : 2000),
      ];
      final means = weekdayMeans(days)!;
      expect(means.byWeekday[DateTime.monday], 2000);
      expect(means.byWeekday[DateTime.saturday], 2700);
      expect(means.mean, 2100);
      final standout = standoutWeekday(means)!;
      expect(standout.weekday, DateTime.saturday);
      expect(standout.off, 600);
    });

    test('none stands out under the threshold', () {
      final means = weekdayMeans([
        _tracked(0, kcal: 2000),
        _tracked(-1, kcal: 2100),
      ])!;
      expect(standoutWeekday(means), isNull);
      expect(weekdayMeans(const []), isNull);
    });
  });

  group('macroShares', () {
    test('the energy each macro gave, and its goal\'s', () {
      final s = macroShares([
        _tracked(
          0,
          carbs: 100,
          fat: 20,
          protein: 50,
          carbsGoal: 250,
          fatGoal: 80,
          proteinGoal: 100,
        ),
      ], windowDates(_today, 7))!;
      expect(s.eaten.carbs, closeTo(400 / 780, 1e-9));
      expect(s.eaten.fat, closeTo(180 / 780, 1e-9));
      expect(s.eaten.protein, closeTo(200 / 780, 1e-9));
      expect(s.goal!.fat, closeTo(720 / 2120, 1e-9));
    });

    test('no goal share without goals; null without macros', () {
      final week = windowDates(_today, 7);
      expect(macroShares([_tracked(0, carbs: 10)], week)!.goal, isNull);
      expect(macroShares([_tracked(0)], week), isNull);
    });
  });
}
