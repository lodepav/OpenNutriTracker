import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/body_weight_unit_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_weight_goal_entity.dart';
import 'package:opennutritracker/fork/goal/goal_you_tile.dart';

// The You tab's Goal tile with no target weight names the plan's rate.
void main() {
  const kg = BodyWeightUnit.kg;
  const lose = UserWeightGoalEntity.loseWeight;
  const gain = UserWeightGoalEntity.gainWeight;
  const keep = UserWeightGoalEntity.maintainWeight;

  test('losing, gaining or keeping, at the weekly rate', () {
    expect(plannedRateText(lose, -0.4, kg), 'Losing 0.4 kg a week');
    expect(plannedRateText(gain, 0.25, kg), 'Gaining 0.25 kg a week');
    expect(plannedRateText(keep, null, kg), 'Keeping your weight');
    expect(
      plannedRateText(lose, -0.4, BodyWeightUnit.lb),
      'Losing 0.88 lb a week',
    );
  });

  test('the rate, which the budget follows, over the direction', () {
    expect(plannedRateText(keep, -0.4, kg), 'Losing 0.4 kg a week');
    expect(plannedRateText(lose, 0, kg), 'Keeping your weight');
    expect(plannedRateText(lose, -0.004, kg), 'Keeping your weight');
  });

  test('no rate: the direction alone', () {
    expect(plannedRateText(lose, null, kg), 'Losing weight');
    expect(plannedRateText(gain, null, kg), 'Gaining weight');
  });
}
