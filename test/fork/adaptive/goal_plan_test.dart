import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/fork/adaptive/goal_plan.dart';

GoalPlanInputs _inputs({double? target = 80, double expenditure = 2500}) =>
    GoalPlanInputs(
      pastTrendKg: const [91, 90.5, 90],
      trendKgPerDay: -0.05,
      expenditureKcal: expenditure,
      bodyFatPercent: 25,
      targetWeightKg: target,
      paceKgPerWeek: -0.5,
    );

void main() {
  test('10 kg at 0.5 kg a week is 140 days, then the curve holds', () {
    final plan = planAt(_inputs(), -0.5);

    expect(plan.daysToTarget, 140);
    expect(plan.projectedKg.first, 90);
    expect(plan.projectedKg[70], closeTo(85, 1e-9));
    expect(plan.projectedKg[140], 80);
    expect(plan.projectedKg.last, 80);
    expect(plan.projectedKg.length, 155);
  });

  test('losing costs energy below expenditure, gaining above', () {
    expect(planAt(_inputs(), -0.5).dailyTargetKcal, lessThan(2500));
    expect(planAt(_inputs(), 0.25).dailyTargetKcal, greaterThan(2500));
    expect(planAt(_inputs(), 0).dailyTargetKcal, 2500);
  });

  test('no date when the pace leads away or there is no target', () {
    expect(planAt(_inputs(), 0.5).daysToTarget, isNull);
    expect(planAt(_inputs(), 0).daysToTarget, isNull);
    expect(planAt(_inputs(target: null), -0.5).daysToTarget, isNull);
    expect(planAt(_inputs(target: 90.05), -0.5).daysToTarget, isNull);
  });

  test('a far target is dated but the curve stops at a year', () {
    final plan = planAt(_inputs(target: 40), -0.5);
    expect(plan.daysToTarget, 700);
    expect(plan.projectedKg.length, maxPlanDays + 1);
  });
}
