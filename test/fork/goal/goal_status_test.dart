import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/body_weight_unit_entity.dart';
import 'package:opennutritracker/fork/goal/goal_status.dart';
import 'package:opennutritracker/fork/phases/phases.dart';

void main() {
  final plan = DateTime(2027, 2, 5);
  GoalVerdict verdict({
    bool reached = false,
    int planDays = 30,
    double? recent = -0.5,
    DateTime? pace,
    DateTime? planArrival,
    double behindKg = 0,
  }) => goalVerdict(
    reached: reached,
    planDays: planDays,
    recentKgPerWeek: recent,
    paceArrival: pace,
    planArrival: planArrival ?? plan,
    behindKg: behindKg,
    planKgPerWeek: -0.5,
  );
  DateTime days(int n) => DateTime(plan.year, plan.month, plan.day + n);

  group('goalVerdict', () {
    test('reached comes first', () {
      expect(verdict(reached: true, planDays: 0), GoalVerdict.reached);
    });

    test('under two weeks into the plan, or no pace yet: too early', () {
      expect(verdict(planDays: 0, pace: days(100)), GoalVerdict.tooEarly);
      expect(verdict(planDays: 13, pace: days(100)), GoalVerdict.tooEarly);
      expect(verdict(recent: null, pace: null), GoalVerdict.tooEarly);
      expect(verdict(planDays: 14, pace: plan), GoalVerdict.onPlan);
    });

    test('the recent pace three months late is behind, not on plan', () {
      expect(verdict(pace: DateTime(2027, 5, 18)), GoalVerdict.behind);
    });

    test('within two weeks either way is on plan', () {
      expect(verdict(pace: days(14)), GoalVerdict.onPlan);
      expect(verdict(pace: days(-14)), GoalVerdict.onPlan);
      expect(verdict(pace: days(15)), GoalVerdict.behind);
      expect(verdict(pace: days(-15)), GoalVerdict.ahead);
    });

    test('a pace going the wrong way is behind', () {
      expect(verdict(recent: 0.2, pace: null), GoalVerdict.behind);
    });

    test('fast lately but behind in kg by over two weeks of plan: behind', () {
      // Two weeks at 0.5 kg a week is 1 kg.
      expect(verdict(pace: days(-30), behindKg: 1.1), GoalVerdict.behind);
      expect(verdict(pace: days(-30), behindKg: 0.9), GoalVerdict.ahead);
    });

    test('no plan date: only the kg behind decides', () {
      expect(
        goalVerdict(
          reached: false,
          planDays: 30,
          recentKgPerWeek: -0.5,
          paceArrival: plan,
          planArrival: null,
          behindKg: 0,
          planKgPerWeek: -0.5,
        ),
        GoalVerdict.onPlan,
      );
    });
  });

  test('signed weights take a true minus and never print −0.0', () {
    expect(signedWeightText(-1.6, BodyWeightUnit.kg), '−1.6 kg');
    expect(signedWeightText(-0.01, BodyWeightUnit.kg), '0.0 kg');
    expect(signedWeightText(0.3, BodyWeightUnit.kg), '+0.3 kg');
    expect(signedWeightText(-1, BodyWeightUnit.st), '−2.2 lb');
    expect(signedPaceText(-0.5, BodyWeightUnit.kg), '−0.50 kg a week');
    expect(signedPaceText(-0.001, BodyWeightUnit.kg), '0.00 kg a week');
  });

  test('a goal under a week counts in days, at least one', () {
    final d = DateTime(2026, 11, 18);
    expect(goalLengthText(d, d), '1 day');
    expect(goalLengthText(d, DateTime(2026, 11, 21)), '3 days');
    expect(goalLengthText(d, DateTime(2026, 11, 25)), '1 week');
    expect(goalLengthText(d, DateTime(2026, 12, 9)), '3 weeks');
  });

  test('the legend kinds are the bands the chart draws', () {
    final first = DateTime(2026, 10, 1);
    final bands = [
      // Ended before the trend begins: not drawn.
      (
        start: DateTime(2026, 8, 1),
        end: DateTime(2026, 9, 1),
        kind: PhaseKind.bulk,
      ),
      (
        start: DateTime(2026, 9, 20),
        end: DateTime(2026, 10, 10),
        kind: PhaseKind.cut,
      ),
      // Starts on the trend's last day: no width.
      (
        start: DateTime(2026, 10, 30),
        end: DateTime(2026, 12, 1),
        kind: PhaseKind.maintain,
      ),
    ];
    expect(drawnKinds(bands, first, 30), {PhaseKind.cut});
    expect(drawnKinds(bands, first, 1), isEmpty);
  });
}
