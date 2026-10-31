import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/core/domain/entity/tracked_day_entity.dart';
import 'package:opennutritracker/core/domain/entity/weight_log_entity.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_service.dart';
import 'package:opennutritracker/fork/report/nutrient_explorer.dart';
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

IntakeEntity _ate(DateTime at, {String name = 'Oats', double? sodium}) =>
    IntakeEntity(
      id: '$name $at',
      unit: 'g',
      amount: 100,
      type: IntakeTypeEntity.breakfast,
      meal: MealEntity(
        code: name,
        name: name,
        url: null,
        mealQuantity: null,
        mealUnit: 'g',
        servingQuantity: null,
        servingUnit: 'g',
        servingSize: null,
        nutriments: MealNutrimentsEntity(
          energyKcal100: 380,
          carbohydrates100: 60,
          fat100: 7,
          proteins100: 13,
          sugars100: null,
          saturatedFat100: null,
          fiber100: null,
          sodium100: sodium,
        ),
        source: MealSourceEntity.custom,
      ),
      dateTime: at,
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
      expect(o.highest, (value: 2300.0, date: _d(-3)));
      expect(o.lowest, (value: 1700.0, date: _d(-4)));
    });

    test('a macro: its grams against its goal', () {
      final o = dayOutcomes(
        [
          _tracked(-2, carbs: 250, carbsGoal: 250),
          _tracked(-1, carbs: 150, carbsGoal: 250),
          // Calories but no carbs: not a day of them.
          _tracked(0),
        ],
        windowDates(_today, 7),
        eaten: (d) => d.carbsTracked,
        goal: (d) => d.carbsGoal,
      );
      expect((o.logged, o.onTarget, o.under, o.over), (2, 1, 1, 0));
      expect(o.lowest, (value: 150.0, date: _d(-1)));
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

  group('balanceSummary', () {
    test('eaten less burnt over the window\'s logged days', () {
      final week = windowDates(_today, 7);
      final s = balanceSummary([
        _spent(-9, 3000, ate: 9000),
        _spent(-3, 3000, ate: 2500),
        _spent(-2, 3000),
        _spent(-1, 2800, ate: 3100),
        _spent(0, 3000, ate: 3000),
      ], week)!;
      expect(s.logged, 3);
      expect(s.eaten, closeTo(8600 / 3, 1e-9));
      expect(s.burnt, closeTo(8800 / 3, 1e-9));
      expect(s.total, -200);
      expect(s.deficit, 1);
      expect(s.surplus, 1);
    });

    test('null with no day logged in the window', () {
      expect(
        balanceSummary([_spent(-9, 3000, ate: 2000)], windowDates(_today, 7)),
        isNull,
      );
    });
  });

  test('a week at 1100 kcal under a day is a kilo', () {
    expect(balanceWeightKg(-1100, 7), -1);
    expect(balanceWeightKg(500, 30, kcalPerKg: 7500), 2);
  });

  group('weekendSplit', () {
    // The 26th is a Monday: the 24th and 25th a weekend.
    final week = windowDates(_today, 7);

    test('each part its own means, the balance where known', () {
      final split = weekendSplit(
        [
          _tracked(0, kcal: 2000, carbs: 200, fat: 60, protein: 120),
          _tracked(-3, kcal: 1800, carbs: 180, fat: 50, protein: 100),
          _tracked(-1, kcal: 2600, carbs: 300, fat: 90, protein: 90),
          _tracked(-2, kcal: 3000, carbs: 340, fat: 100, protein: 80),
        ],
        week,
        balance: {_d(-1): 200, _d(0): -500},
      )!;
      expect(split.weekdays.days, 2);
      expect(split.weekdays.kcal, 1900);
      expect(split.weekdays.protein, 110);
      expect(split.weekdays.balance, -500);
      expect(split.weekend.days, 2);
      expect(split.weekend.kcal, 2800);
      expect(split.weekend.carbs, 320);
      expect(split.weekend.balance, 200);
    });

    test('none without a logged day in each part', () {
      expect(weekendSplit([_tracked(0)], week), isNull);
    });
  });

  group('proteinPerKg', () {
    final week = windowDates(_today, 7);

    test('each day against its trend, the goal against the latest', () {
      final p = proteinPerKg(
        [
          _tracked(-1, protein: 160, proteinGoal: 150),
          _tracked(0, protein: 120, proteinGoal: 160),
          // No trend that day.
          _tracked(-5, protein: 300),
        ],
        week,
        {_d(-1): 80, _d(0): 80},
      )!;
      expect(p.perKg, closeTo(1.75, 1e-9));
      expect(p.goalPerKg, closeTo(2.0, 1e-9));
      expect(p.days, 2);
    });

    test('none without a weigh-in', () {
      expect(proteinPerKg([_tracked(0, protein: 100)], week, const {}), isNull);
    });
  });

  group('loggingCompleteness', () {
    test('logged, counted, left out, and logged too lightly', () {
      final week = windowDates(_today, 7);
      final c = loggingCompleteness(
        [
          _tracked(-5),
          _tracked(-4),
          _tracked(-3, kcal: 120),
          _tracked(-2),
          _tracked(0),
          _tracked(-12),
        ],
        [
          // The history starts four days back, at the first weigh-in.
          _spent(-4, 3000, ate: 2000),
          _spent(-3, 3000),
          _spent(-2, 3000),
          _spent(-1, 3000),
          _spent(0, 3000, ate: 2000),
        ],
        week,
        {_d(-2), _d(-20)},
      );
      expect(c.of, 7);
      expect(c.logged, 5);
      expect(c.counted, 2);
      expect(c.skipped, 1);
      // Day -3, under the estimate's floor; -5 is before the history.
      expect(c.partial, 1);
    });
  });

  test('entries a logged day, by the Diary\'s day', () {
    expect(entriesPerDay(const []), isNull);
    expect(
      entriesPerDay([
        _ate(DateTime(2026, 10, 25, 8)),
        _ate(DateTime(2026, 10, 25, 13)),
        _ate(DateTime(2026, 10, 26, 1)),
        _ate(DateTime(2026, 10, 26, 8)),
      ]),
      2,
    );
    // A day starting at 4 am counts the 1 am entry on the day before.
    expect(
      entriesPerDay([
        _ate(DateTime(2026, 10, 25, 8)),
        _ate(DateTime(2026, 10, 26, 1)),
        _ate(DateTime(2026, 10, 26, 8)),
      ], dayStartMinutes: 240),
      1.5,
    );
  });

  group('scaleNoise', () {
    test('each weigh-in against the trend, the mean and the largest', () {
      final week = windowDates(_today, 7);
      final entries = [
        for (var i = -20; i <= 0; i++)
          WeightLogEntity(
            date: _d(i).add(const Duration(hours: 7)),
            weightKg: i == -3 ? 81.5 : 80,
          ),
      ];
      final n = scaleNoise(entries, week)!;
      expect(n.byDay.keys, week);
      expect(n.largest.on, _d(-3));
      expect(n.largest.kg, greaterThan(1));
      // The days after the jump read below the trend it lifted.
      expect(n.byDay[_d(-2)], lessThan(0));
      expect(
        n.meanKg,
        closeTo(
          n.byDay.values.map((v) => v.abs()).reduce((a, b) => a + b) / 7,
          1e-9,
        ),
      );
      expect(scaleNoise(entries, windowDates(_d(-30), 7)), isNull);
    });
  });

  group('swingAfterHigh', () {
    final week = windowDates(_today, 7);
    test('the mornings after high days against the rest', () {
      final s = swingAfterHigh(
        {for (final (i, d) in week.indexed) d: i == 2 || i == 5 ? 0.8 : 0.1},
        week,
        [100, 300, 100, 100, 300, 100, 100],
      )!;
      expect(s.days, 2);
      expect(s.after, closeTo(0.8, 1e-9));
      expect(s.other, closeTo(0.1, 1e-9));
    });

    test('null with a single high day', () {
      expect(
        swingAfterHigh(
          {for (final d in week) d: 0.1},
          week,
          [100, 300, 100, 100, 100, 100, 100],
        ),
        isNull,
      );
    });
  });

  test('a nutrient each day, by the Diary\'s day', () {
    final salt = explorerNutrients.firstWhere((n) => n.label == 'Salt');
    final days = [_d(-1), _d(0)];
    expect(
      nutrientByDay(
        [
          _ate(DateTime(2026, 10, 25, 8), sodium: 400),
          _ate(DateTime(2026, 10, 26, 2), sodium: 100),
          _ate(DateTime(2026, 10, 26, 9)),
          // Added from the Diary: the day's label, kept on its day.
          _ate(DateTime.utc(2026, 10, 26), sodium: 50),
        ],
        days,
        salt,
        dayStartMinutes: 240,
      ),
      // Salt in g: sodium (mg) times 2.5 / 1000.
      [1.25, 0.125],
    );
  });
}
