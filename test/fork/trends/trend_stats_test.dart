import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/body_weight_unit_entity.dart';
import 'package:opennutritracker/core/domain/entity/tracked_day_entity.dart';
import 'package:opennutritracker/core/domain/entity/weight_log_entity.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_service.dart';
import 'package:opennutritracker/fork/adaptive/expenditure.dart';
import 'package:opennutritracker/fork/adaptive/goal_plan.dart';
import 'package:opennutritracker/fork/adaptive/trend.dart';
import 'package:opennutritracker/fork/trends/trend_stats.dart';
import 'package:opennutritracker/fork/trends/trends_widgets.dart';

// Seam S120: the numbers behind Trends' tiles and pages.

final _today = DateTime(2026, 10, 25);

DateTime _d(int offset) =>
    DateTime(_today.year, _today.month, _today.day + offset);

TrackedDayEntity _tracked(
  int offset, {
  double kcal = 2000,
  double goal = 2500,
  double? carbs,
  double? carbsGoal,
  double? fat,
  double? protein,
}) => TrackedDayEntity(
  // Stamped with a time, as today's tracked day is.
  day: _d(offset).add(const Duration(hours: 9)),
  calorieGoal: goal,
  caloriesTracked: kcal,
  carbsTracked: carbs,
  carbsGoal: carbsGoal,
  fatTracked: fat,
  proteinTracked: protein,
);

void main() {
  final week = windowDates(_today, 7);

  test('the window ends today, oldest first', () {
    expect(week.first, _d(-6));
    expect(week.last, _today);
    expect(week, hasLength(7));
  });

  test('a mean is over the values present; none is null', () {
    expect(meanOf([null, 2, 4, null]), 3);
    expect(meanOf([null, null]), isNull);
  });

  test('the change is the fitted line\'s over the whole series', () {
    // A steady 10 a day over seven days: 60 from first to last.
    expect(fittedChange([0, 10, 20, 30, 40, 50, 60]), closeTo(60, 1e-9));
    // Days missing do not bend the line.
    expect(fittedChange([0, null, 20, null, 40, null, 60]), closeTo(60, 1e-9));
    expect(fittedChange([5, null]), isNull);
    expect(fittedChange([5, 5, 5]), 0);
  });

  test('only logged days count; a day of no energy is not a fast', () {
    final days = [
      _tracked(-6, kcal: 1800, carbs: 200),
      _tracked(-3, kcal: 0, carbs: 0),
      _tracked(0, kcal: 2200, carbs: 300),
    ];
    final energy = nutritionSeries(days, week, (d) => d.caloriesTracked);
    expect(energy, [1800, null, null, null, null, null, 2200]);
    expect(meanOf(energy), 2000);
    expect(meanOf(nutritionSeries(days, week, (d) => d.carbsTracked)), 250);
  });

  // S87: one logged day of seven shows that day's goal, not a seventh.
  test('a goal is the mean over the logged days that have one', () {
    final days = [
      _tracked(-1, goal: 2000, carbsGoal: 250),
      _tracked(0, goal: 3000),
      _tracked(-4, kcal: 0, goal: 9000, carbsGoal: 900),
      // A goal of nothing is no goal.
      _tracked(-2, goal: 0, carbsGoal: 0),
    ];
    expect(goalOf(days, week, (d) => d.calorieGoal), 2500);
    expect(goalOf(days, week, (d) => d.carbsGoal), 250);
    expect(goalOf(const [], week, (d) => d.calorieGoal), isNull);
  });

  test('macro energy stacks to the energy logged', () {
    // 100 g carbs, 20 g fat, 50 g protein: 400 + 180 + 200 = 780 kcal by
    // the factors, scaled to the 1560 logged.
    final split = macroEnergy(
      _tracked(0, kcal: 1560, carbs: 100, fat: 20, protein: 50),
    )!;
    expect(split.carbs, closeTo(800, 1e-9));
    expect(split.fat, closeTo(360, 1e-9));
    expect(split.protein, closeTo(400, 1e-9));
    expect(macroEnergy(_tracked(0, kcal: 500)), isNull);
    expect(macroEnergy(_tracked(0, kcal: 0, carbs: 10)), isNull);
  });

  test('water and balance are on the days logged', () {
    expect(waterSeries({_d(-1): 1500, _d(0): 0}, week).sublist(5), [
      1500,
      null,
    ]);
    final history = [
      ExpenditureDay(date: _d(-1), expenditureKcal: 2800, settled: true),
      ExpenditureDay(
        date: _d(0),
        expenditureKcal: 2900,
        intakeKcal: 2400,
        settled: true,
      ),
    ];
    expect(expenditureSeries(history, week).sublist(5), [2800, 2900]);
    expect(balanceSeries(history, week).sublist(5), [null, -500]);
  });

  test('a bar a bucket averages the days present', () {
    expect(Sparkline.bucketed([1, 2, 3], 14), [1, 2, 3]);
    expect(Sparkline.bucketed([1, 3, null, null, 5, 7], 3), [2, null, 6]);
  });

  test('a signed number is never -0', () {
    expect(signedText(-0.2), '0');
    expect(signedText(-0.04, 1), '0.0');
    expect(signedText(12.4), '+12');
    expect(signedText(-1.25, 1), '-1.3');
  });

  // As S93's outlook: the smoothed trend carried to today, its change
  // over the range and the Goal planner's rate for the week.
  test('the weight trend agrees with the Goal planner\'s week', () {
    final weighIns = {0: 84.0, 9: 83.1, 15: 83.6, 18: 82.4, 21: 82.9};
    const span = 25;
    final entries = [
      for (final MapEntry(key: d, value: kg) in weighIns.entries)
        WeightLogEntity(date: _d(d - (span - 1)), weightKg: kg),
    ];
    final stats = WeightTrendStats.of(entries, week);
    final planner = smoothedTrend(
      dailyWeights(weighIns, span),
      alpha: const ExpenditureSettings().alpha,
    ).whereType<double>().toList();
    expect(stats.perWeekKg, closeTo(trendChanges(planner)[7]!, 1e-9));
    expect(stats.nowKg, closeTo(planner.last, 1e-9));
    expect(stats.changeKg, closeTo(stats.perWeekKg!, 1e-9));
    expect(stats.trend, hasLength(7));
    expect(stats.trend.every((t) => t != null), isTrue);
  });

  test('no weigh-ins: no trend', () {
    final stats = WeightTrendStats.of(const [], week);
    expect(stats.nowKg, isNull);
    expect(stats.perWeekKg, isNull);
  });

  test('weights in the user\'s unit', () {
    expect(weightIn(BodyWeightUnit.kg, 80), 80);
    expect(weightIn(BodyWeightUnit.lb, 80), closeTo(176.4, 1e-9));
    expect(weightIn(BodyWeightUnit.st, 80), closeTo(12.6, 0.01));
  });

  test('the footer names the range', () {
    expect(rangeText(7, 7), 'Last 7 days');
    expect(rangeText(0, 412), 'All time');
  });
}
