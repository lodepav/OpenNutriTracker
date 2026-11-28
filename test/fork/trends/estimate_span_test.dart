import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/weight_log_entity.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_service.dart';
import 'package:opennutritracker/fork/adaptive/expenditure.dart';
import 'package:opennutritracker/fork/trends/estimate_span.dart';

final _today = DateTime(2026, 11, 28);

DateTime _d(int offset) =>
    DateTime(_today.year, _today.month, _today.day + offset);

/// [length] days of estimate ending today.
List<ExpenditureDay> _history(int length) => [
  for (var i = 0; i < length; i++)
    ExpenditureDay(
      date: _d(i - length + 1),
      expenditureKcal: 2500.0 + i,
      settled: true,
    ),
];

WeightLogEntity _weighIn(int offset) =>
    WeightLogEntity(date: _d(offset), weightKg: 80);

void main() {
  test('the settling days are gone by the end of calibration: '
      'two priors far apart meet within 1% of their gap', () {
    const settings = ExpenditureSettings();
    // Steady eating and weight, logged and weighed every day.
    final days = [
      for (var i = 0; i < 120; i++)
        const AdaptiveDay(intakeKcal: 2500, weightKg: 80),
    ];
    final low = estimateExpenditure(days, priorKcal: 2000, settings: settings);
    final high = estimateExpenditure(
      days,
      priorKcal: 3500,
      settings: settings,
    );
    final n = estimateSettlingDays(settings);
    expect((high[n] - low[n]).abs(), lessThan(1500 * 0.01));
    // Not long before, the prior still shows.
    expect((high[n - 10] - low[n - 10]).abs(), greaterThan(1500 * 0.03));
  });

  test('a run from the first weigh-in ever is shown whole', () {
    final history = _history(119);
    expect(
      estimateShown(history, weighIns: [_weighIn(-118), _weighIn(-3)]),
      same(history),
    );
  });

  test('a run cut at the look-back drops its settling days', () {
    final history = _history(120);
    final shown = estimateShown(history, weighIns: [_weighIn(-300)]);
    final n = estimateSettlingDays(const ExpenditureSettings());
    expect(shown.length, 120 - n);
    expect(shown.first.date, _d(-119 + n));
    expect(shown.last.date, _today);
  });

  test('a cut run too short to settle is shown whole', () {
    final history = _history(10);
    expect(estimateShown(history, weighIns: [_weighIn(-300)]), same(history));
  });

  test('no history, none shown', () {
    expect(estimateShown(const [], weighIns: [_weighIn(-3)]), isEmpty);
  });
}
