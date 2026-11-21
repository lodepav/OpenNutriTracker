import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/fork/adaptive/expenditure.dart';

const _expenditure = 2500.0;
const _kcalPerKg = 7000.0;
const _undamped = ExpenditureSettings(kcalPerKg: _kcalPerKg, shiftHold: null);
const _damped = ExpenditureSettings(kcalPerKg: _kcalPerKg);

/// Days weighed and logged in full, the weight following the intake at
/// [_kcalPerKg] against an expenditure of [expenditure] (by day), plus
/// [waterPer1000] kg of water per 1,000 kcal eaten, at once.
List<AdaptiveDay> _history(
  double Function(int day) intake, {
  int days = 200,
  double Function(int day)? expenditure,
  double waterPer1000 = 0,
}) {
  var kg = 90.0;
  return [
    for (var d = 0; d < days; d++)
      () {
        kg += (intake(d) - (expenditure?.call(d) ?? _expenditure)) / _kcalPerKg;
        return AdaptiveDay(
          intakeKcal: intake(d),
          weightKg: kg + waterPer1000 * (intake(d) - _expenditure) / 1000,
        );
      }(),
  ];
}

/// The furthest the estimate is from [_expenditure] from [from] on.
double _worst(List<double> estimates, int from) =>
    estimates.skip(from).map((e) => (e - _expenditure).abs()).reduce(max);

void main() {
  test('all of the weight to 5% of the intake, none from 15%', () {
    const s = ExpenditureSettings();
    expect(s.shiftDamping(0, 2000), 1);
    expect(s.shiftDamping(-100, 2000), 1);
    expect(s.shiftDamping(200, 2000), closeTo(0.5, 1e-9));
    expect(s.shiftDamping(-300, 2000), 0);
    expect(s.shiftDamping(900, 2000), 0);
    expect(_undamped.shiftDamping(900, 2000), 1);
  });

  // The cut a goal change makes, at maintenance until day 100.
  double cut(int day) => day < 100 ? 2500 : 1800;

  test('a cut is not read as a fall in expenditure', () {
    final days = _history(cut);
    final undamped = estimateExpenditure(
      days,
      priorKcal: _expenditure,
      settings: _undamped,
    );
    final damped = estimateExpenditure(
      days,
      priorKcal: _expenditure,
      settings: _damped,
    );
    // The trend lags the cut, so the weeks after it read low.
    expect(_worst(undamped, 100), greaterThan(100));
    expect(_worst(damped, 100), lessThan(30));
  });

  test("nor is the cut's water read as a rise", () {
    final days = _history(cut, waterPer1000: 2.5);
    final undamped = estimateExpenditure(
      days,
      priorKcal: _expenditure,
      settings: _undamped,
    );
    final damped = estimateExpenditure(
      days,
      priorKcal: _expenditure,
      settings: _damped,
    );
    expect(_worst(undamped, 100), greaterThan(100));
    expect(_worst(damped, 100), lessThan(40));
  });

  test('a change in expenditure at a steady intake is followed as before', () {
    final days = _history(
      (_) => 2500,
      expenditure: (day) => day < 100 ? 2500 : 2200,
    );
    expect(
      estimateExpenditure(days, priorKcal: _expenditure, settings: _damped),
      estimateExpenditure(days, priorKcal: _expenditure, settings: _undamped),
    );
  });

  test('calibration is not damped: a new user leaves the prior as before', () {
    // The first target is followed from day 14: a cut inside calibration.
    final days = _history((day) => day < 14 ? 3000 : 2000, days: 28);
    expect(
      estimateExpenditure(days, priorKcal: 3200, settings: _damped),
      estimateExpenditure(days, priorKcal: 3200, settings: _undamped),
    );
  });

  test('a held day is no update', () {
    final days = _history(cut, days: 112);
    final damped = estimateExpenditureRun(
      days,
      priorKcal: _expenditure,
      settings: _damped,
    );
    final undamped = estimateExpenditureRun(
      days,
      priorKcal: _expenditure,
      settings: _undamped,
    );
    expect(damped.updates, lessThan(undamped.updates));
    // Held on the last day: it carries the day before's.
    expect(damped.estimates.last, damped.estimates[110]);
  });

  test('day-to-day variation is under the deadband', () {
    final random = Random(1);
    final days = _history((_) => 2500 * (0.9 + 0.2 * random.nextDouble()));
    final damped = estimateExpenditureRun(
      days,
      priorKcal: _expenditure,
      settings: _damped,
    );
    final undamped = estimateExpenditureRun(
      days,
      priorKcal: _expenditure,
      settings: _undamped,
    );
    expect(damped.updates, undamped.updates);
    expect(
      (damped.estimates.last - undamped.estimates.last).abs(),
      lessThan(5),
    );
  });
  test('an intake changed across a break is not held once back', () {
    // 60 days at 2,000 kcal, a week not logged nor weighed, then a steady
    // 1,500: the weigh-in a week after the first one back (day 67), day 74,
    // anchors the restart (D68).
    var kg = 90.0;
    final days = [
      for (var d = 0; d < 120; d++)
        () {
          final intake = d < 60 ? 2000.0 : (d < 67 ? null : 1500.0);
          kg += ((intake ?? _expenditure) - _expenditure) / _kcalPerKg;
          return AdaptiveDay(
            intakeKcal: intake,
            weightKg: intake == null ? null : kg,
          );
        }(),
    ];
    int updates(int length) => estimateExpenditureRun(
      days.sublist(0, length),
      priorKcal: _expenditure,
      settings: _damped,
    ).updates;
    const resumes = 67 + ExpenditureSettings.defaultWarmupDays + 1;
    expect(
      estimateExpenditureRun(
        days.sublist(0, resumes),
        priorKcal: _expenditure,
        settings: _damped,
      ).breakHold,
      isNotNull,
    );
    // Every day from then on is weighed and logged at the same intake.
    expect(updates(resumes + 14) - updates(resumes), 14);
  });
}
