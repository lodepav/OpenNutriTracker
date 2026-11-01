import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/fork/adaptive/goal_plan.dart';

void main() {
  test('days to a target at a pace, none when it leads away or is reached', () {
    expect(daysToTarget(90, 80, -0.5 / 7), 140);
    expect(daysToTarget(90, 80, 0.5 / 7), isNull);
    expect(daysToTarget(90, 80, 0), isNull);
    expect(daysToTarget(90, null, -0.5 / 7), isNull);
    expect(daysToTarget(90, 90.05, -0.5 / 7), isNull);
  });

  test('the trend moved over 7, 14 and 30 days, as far as it reaches', () {
    final trend = [for (var i = 0; i < 20; i++) 90 - i * 0.1];
    final changes = trendChanges(trend);
    expect(changes.keys, [7, 14]);
    expect(changes[7], closeTo(-0.7, 1e-9));
    expect(changes[14], closeTo(-1.4, 1e-9));
    expect(trendChanges(const [90]), isEmpty);
  });

  group('milestones', () {
    test('round weights every step, nearest first, not the one reached', () {
      expect(milestonesKg(90.4, 80, 2), [90, 88, 86, 84, 82]);
      expect(milestonesKg(90.05, 84, 2), [88, 86]);
      expect(milestonesKg(90, 80, 5), [85]);
      expect(milestonesKg(60.2, 66, 2), [62, 64]);
    });

    test('in pounds, round pounds', () {
      final lb = milestonesKg(90, 80, 5, perKg: 2.20462);
      expect(
        [for (final kg in lb) (kg * 2.20462).round()],
        [195, 190, 185, 180],
      );
    });

    test('in pounds, one under 0.1 kg away counts as reached', () {
      // 200.15 lb: 200 is 0.07 kg off, where the planner says "reached".
      final lb = milestonesKg(
        200.15 / 2.20462,
        190 / 2.20462,
        2,
        perKg: 2.20462,
      );
      expect(
        [for (final kg in lb) (kg * 2.20462).round()],
        [198, 196, 194, 192],
      );
    });

    test('none at the target or past it', () {
      expect(milestonesKg(80.05, 80, 1), isEmpty);
      expect(milestonesKg(79, 80, 5), isEmpty);
    });
  });
}
