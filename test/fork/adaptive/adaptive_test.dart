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

    group('after a break (D27)', () {
      // 40 days at a steady 80 kg on 2400, [gap] days with nothing, then
      // back 2 kg up and steady there, logging 2400 again.
      List<AdaptiveDay> trip({int gap = 10, int back = 30}) => [
        for (var d = 0; d < 40; d++)
          const AdaptiveDay(intakeKcal: 2400, weightKg: 80),
        for (var d = 0; d < gap; d++) const AdaptiveDay(),
        for (var d = 0; d < back; d++)
          const AdaptiveDay(intakeKcal: 2400, weightKg: 82),
      ];

      test('the estimate holds for a week after the first weigh-in back', () {
        final run = estimateExpenditureRun(trip(), priorKcal: 2400);
        final before = run.estimates[49];
        // back on day 50, its weigh-in the anchor: held to day 56
        for (var d = 50; d < 57; d++) {
          expect(run.estimates[d], before, reason: 'day $d');
        }
        expect(run.estimates[57], isNot(before));
      });

      test('the jump is not priced as eating more than was logged', () {
        final estimates = estimateExpenditure(trip(), priorKcal: 2400);
        expect(estimates.last, closeTo(2400, 25));

        // Without the break, the trend climbing to 82 read as a surplus.
        final weighed = [
          for (final d in trip())
            AdaptiveDay(intakeKcal: d.intakeKcal ?? 2400, weightKg: d.weightKg),
        ];
        expect(
          estimateExpenditure(weighed, priorKcal: 2400).last,
          lessThan(2300),
        );
      });

      test('says how long it holds, and nothing once it moves', () {
        final held = estimateExpenditureRun(
          trip(back: 3),
          priorKcal: 2400,
        ).breakHold!;
        expect(held.daysBack, 3);
        expect(held.resumesIn, 5);

        final unweighed = estimateExpenditureRun([
          ...trip(back: 0),
          const AdaptiveDay(intakeKcal: 2400),
        ], priorKcal: 2400).breakHold!;
        expect(unweighed.resumesIn, isNull);

        expect(
          estimateExpenditureRun(trip(back: 8), priorKcal: 2400).breakHold,
          isNull,
        );
      });

      test('logging days back before the first weigh-in back', () {
        final run = estimateExpenditureRun([
          ...trip(back: 0),
          for (var d = 0; d < 3; d++) const AdaptiveDay(intakeKcal: 2400),
          for (var d = 0; d < 10; d++)
            const AdaptiveDay(intakeKcal: 2400, weightKg: 82),
        ], priorKcal: 2400);
        // the anchor is day 53: held to day 59
        expect(run.estimates[59], run.estimates[49]);
        expect(run.estimates[60], isNot(run.estimates[49]));
      });

      test('four unlogged days are no break', () {
        expect(
          estimateExpenditureRun(
            trip(gap: 4, back: 3),
            priorKcal: 2400,
          ).breakHold,
          isNull,
        );
      });
    });
  });

  test('the chosen settings stay within the simulated scores', () {
    // fork/research/phase3-simulation.md: 73 kcal, 4.7 kcal/day per day.
    final s = scoreAll(const ExpenditureSettings(), seeds: 2);

    expect(s.error, lessThan(90));
    expect(s.stability, lessThan(7));
  });
}
