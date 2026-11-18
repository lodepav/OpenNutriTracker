import 'package:opennutritracker/core/domain/entity/user_weight_goal_entity.dart';
import 'package:opennutritracker/fork/adaptive/goal_saving.dart';

/// [kgPerWeek] turned to a newly picked [goal]: the calorie formula follows
/// the rate over the direction, so a rate that disagrees is turned. Kept
/// when it already means [goal], its sign flipped when it points the other
/// way, 0 for maintaining; no rate stays none, and a rate too small to mean
/// [goal] becomes none, so the formula's own step for [goal] applies.
double? rateForDirection(double? kgPerWeek, UserWeightGoalEntity goal) {
  if (kgPerWeek == null || goalOfPace(kgPerWeek) == goal) return kgPerWeek;
  final turned = switch (goal) {
    UserWeightGoalEntity.maintainWeight => 0.0,
    UserWeightGoalEntity.loseWeight => -kgPerWeek.abs(),
    UserWeightGoalEntity.gainWeight => kgPerWeek.abs(),
  };
  return goalOfPace(turned) == goal ? turned : null;
}
