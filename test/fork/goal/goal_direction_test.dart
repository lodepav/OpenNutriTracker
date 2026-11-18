import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/user_weight_goal_entity.dart';
import 'package:opennutritracker/fork/goal/goal_direction.dart';

void main() {
  test('a direction keeps an agreeing rate and turns a contradicting one', () {
    expect(rateForDirection(-0.4, UserWeightGoalEntity.loseWeight), -0.4);
    expect(rateForDirection(-0.4, UserWeightGoalEntity.gainWeight), 0.4);
    expect(rateForDirection(0.3, UserWeightGoalEntity.loseWeight), -0.3);
    expect(rateForDirection(-0.4, UserWeightGoalEntity.maintainWeight), 0);
    expect(rateForDirection(null, UserWeightGoalEntity.gainWeight), isNull);
  });

  test('a pace small enough to be maintaining is kept for maintaining', () {
    expect(rateForDirection(-0.05, UserWeightGoalEntity.maintainWeight), -0.05);
  });

  test('a rate too small to mean the new direction is dropped, so the '
      "formula's own step for it applies", () {
    expect(rateForDirection(0, UserWeightGoalEntity.loseWeight), isNull);
    expect(rateForDirection(0.05, UserWeightGoalEntity.gainWeight), isNull);
    expect(rateForDirection(-0.05, UserWeightGoalEntity.gainWeight), isNull);
  });
}
