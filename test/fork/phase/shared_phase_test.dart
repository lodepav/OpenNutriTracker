import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/user_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_gender_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_pal_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_weight_goal_entity.dart';
import 'package:opennutritracker/fork/phase/shared_phase.dart';

void main() {
  SharedPhase phase(UserWeightGoalEntity goal, {double? rate}) =>
      SharedPhase.of(
        UserEntity(
          birthday: DateTime(1990),
          heightCM: 180,
          weightKG: 80,
          gender: UserGenderEntity.male,
          goal: goal,
          pal: UserPALEntity.active,
          weeklyWeightGoalKg: rate,
        ),
        targetKcal: 2345.6,
        now: DateTime.fromMillisecondsSinceEpoch(1000),
      );

  test('the goal names the phase while no pace is set', () {
    expect(phase(UserWeightGoalEntity.loseWeight).phase, 'cutting');
    expect(phase(UserWeightGoalEntity.maintainWeight).phase, 'maintaining');
    expect(phase(UserWeightGoalEntity.gainWeight).phase, 'bulking');
  });

  // The calories follow the pace over the goal (CalorieGoalCalc), so a goal
  // left at maintain with a pace set is a cut.
  test('a chosen pace outranks the goal, as it does for the calories', () {
    final cut = phase(UserWeightGoalEntity.maintainWeight, rate: -0.4);
    expect(cut.phase, 'cutting');
    expect(cut.rateKgPerWeek, -0.4);
    expect(
      phase(UserWeightGoalEntity.loseWeight, rate: 0).phase,
      'maintaining',
    );
    expect(phase(UserWeightGoalEntity.loseWeight, rate: 0.2).phase, 'bulking');
  });

  test('a pace under 0.1 kg/week either way is maintaining', () {
    expect(phaseOfRate(-0.1), 'cutting');
    expect(phaseOfRate(-0.05), 'maintaining');
    expect(phaseOfRate(0.05), 'maintaining');
    expect(phaseOfRate(0.1), 'bulking');
  });

  test('saves what PhaseProvider reads, the target whole', () {
    expect(jsonDecode(phase(UserWeightGoalEntity.gainWeight).encode()), {
      'phase': 'bulking',
      'rateKgPerWeek': 0.5,
      'targetKcal': 2346,
      'updatedAt': 1000,
    });
  });
}
