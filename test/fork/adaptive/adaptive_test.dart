import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/fork/adaptive/energy.dart';
import 'package:opennutritracker/fork/adaptive/expenditure.dart';
import 'package:opennutritracker/fork/adaptive/simulator.dart';
import 'package:opennutritracker/fork/adaptive/trend.dart';

void main() {
  group('trend', () {
    test('fills days between weigh-ins linearly and carries the last', () {
      expect(dailyWeights({1: 151, 3: 150}, 5), [null, 151, 150.5, 150, 150]);
    });

    test('smooths each new day by alpha', () {
      expect(smoothedTrend([null, 100, 110, 110], alpha: 0.1), [
        null,
        100,
        101,
        closeTo(101.9, 1e-9),
      ]);
    });
  });

  group('energy', () {
    test('the energy in a kilo follows fat mass (Hall 2008 table)', () {
      expect(energyDensity(10), closeTo(5550, 30));
      expect(energyDensity(20), closeTo(6830, 30));
      expect(energyDensity(50), closeTo(8130, 30));
    });

    test('Deurenberg body fat for a 30-year-old man at BMI 25', () {
      expect(
        deurenbergBodyFatPercent(bmi: 25, age: 30, sex: 1),
        closeTo(20.7, 1e-9),
      );
    });
  });

  group('expenditure', () {
    test('steady weight: expenditure is what was logged', () {
      final days = [
        for (var d = 0; d < 60; d++)
          AdaptiveDay(intakeKcal: 2400, weightKg: 80),
      ];
      final estimate = estimateExpenditure(days, priorKcal: 3000);

      expect(estimate.first, 3000);
      expect(estimate.last, closeTo(2400, 25));
    });

    test('losing 0.5 kg a week on 2000 kcal is about 2000 + 500', () {
      final days = [
        for (var d = 0; d < 120; d++)
          AdaptiveDay(intakeKcal: 2000, weightKg: 90 - 0.5 * d / 7),
      ];
      final estimate = estimateExpenditure(days, priorKcal: 2000);

      // 0.5 kg/week at the flat 6,000 kcal/kg is 429 kcal/day.
      expect(estimate.last, closeTo(2429, 25));
    });

    test('a week with under 4 logged days carries the estimate', () {
      final days = [
        for (var d = 0; d < 40; d++)
          AdaptiveDay(intakeKcal: d < 30 ? 2400 : null, weightKg: 80),
      ];
      final estimate = estimateExpenditure(days, priorKcal: 2400);

      expect(estimate[39], estimate[33]);
    });
  });

  test('the chosen settings stay within the simulated scores', () {
    // fork/research/phase3-simulation.md: 73 kcal, 4.7 kcal/day per day.
    final s = scoreAll(const ExpenditureSettings(), seeds: 2);

    expect(s.error, lessThan(90));
    expect(s.stability, lessThan(7));
  });
}
