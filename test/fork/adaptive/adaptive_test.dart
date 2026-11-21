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
        // back on day 50; the anchor is the weigh-in a week on, day 57,
        // whose window is empty: held to day 57 (D68)
        for (var d = 50; d < 58; d++) {
          expect(run.estimates[d], before, reason: 'day $d');
        }
        expect(run.estimates[58], isNot(before));
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
        // back on day 50, the first update on day 58
        expect(held.resumesIn, 6);

        final unweighed = estimateExpenditureRun([
          ...trip(back: 0),
          const AdaptiveDay(intakeKcal: 2400),
        ], priorKcal: 2400).breakHold!;
        expect(unweighed.resumesIn, isNull);

        // the anchor, day 57, is the last day
        expect(
          estimateExpenditureRun(
            trip(back: 8),
            priorKcal: 2400,
          ).breakHold!.resumesIn,
          1,
        );
        expect(
          estimateExpenditureRun(trip(back: 9), priorKcal: 2400).breakHold,
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
        // the first weigh-in back is day 53, the anchor day 60: held to it
        expect(run.estimates[60], run.estimates[49]);
        expect(run.estimates[61], isNot(run.estimates[49]));
      });

      test('no weigh-in a week on: held, at the earliest tomorrow\'s', () {
        // weighed days 50 to 56, then logging without weighing
        List<AdaptiveDay> unweighed(int n) => [
          ...trip(back: 7),
          for (var d = 0; d < n; d++) const AdaptiveDay(intakeKcal: 2400),
        ];
        final run = estimateExpenditureRun(unweighed(3), priorKcal: 2400);
        expect(run.estimates.last, run.estimates[49]);
        // a weigh-in tomorrow anchors, the day after it updates
        expect(run.breakHold!.resumesIn, 2);
        // a week with no weigh-in: no hold, the week's data rule says why
        final week = estimateExpenditureRun(unweighed(8), priorKcal: 2400);
        expect(week.estimates.last, week.estimates[49]);
        expect(week.breakHold, isNull);
      });

      test('a second break before the anchor holds to its own', () {
        final run = estimateExpenditureRun([
          ...trip(back: 3),
          for (var d = 0; d < 6; d++) const AdaptiveDay(),
          for (var d = 0; d < 20; d++)
            const AdaptiveDay(intakeKcal: 2400, weightKg: 84),
        ], priorKcal: 2400);
        // back on day 50, away 53 to 58, back on 59: anchor day 66
        for (var d = 50; d < 67; d++) {
          expect(run.estimates[d], run.estimates[49], reason: 'day $d');
        }
        expect(run.estimates[67], isNot(run.estimates[49]));
        expect(run.estimates.last, closeTo(2400, 25));
      });

      test('first back, as before D68: held a week from it', () {
        final run = estimateExpenditureRun(
          trip(),
          priorKcal: 2400,
          settings: const ExpenditureSettings(
            breakAnchor: BreakAnchor.firstBack,
          ),
        );
        expect(run.estimates[56], run.estimates[49]);
        expect(run.estimates[57], isNot(run.estimates[49]));
      });

      test('the first updates after a break move little', () {
        // back 1 kg lighter each week, so every update moves the estimate
        final days = [
          for (final (i, d) in trip(back: 40).indexed)
            i < 50
                ? d
                : AdaptiveDay(intakeKcal: 2400, weightKg: 82 - (i - 50) / 7),
        ];
        final soft = estimateExpenditure(days, priorKcal: 2400);
        // anchor day 57, the first update day 58
        expect(soft[57], soft[49]);
        final step = (soft[58] - soft[57]).abs();
        expect(step, greaterThan(0));
        // a 1-day window at 1/20 of an update, against a full window's
        expect(step, lessThan((soft[78] - soft[77]).abs() / 5));
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
