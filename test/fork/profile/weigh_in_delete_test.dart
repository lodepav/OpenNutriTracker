import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/data/repository/user_repository.dart';
import 'package:opennutritracker/core/data/repository/weight_log_repository.dart';
import 'package:opennutritracker/core/domain/entity/user_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_gender_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_pal_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_weight_goal_entity.dart';
import 'package:opennutritracker/core/domain/entity/weight_log_entity.dart';
import 'package:opennutritracker/core/domain/usecase/delete_weight_log_usecase.dart';

class _Log extends Fake implements WeightLogRepository {
  final List<WeightLogEntity> rows;
  _Log(this.rows);

  @override
  Future<void> deleteEntry(DateTime date) async =>
      rows.removeWhere((row) => row.date == date);

  @override
  Future<List<WeightLogEntity>> getAllEntries() async => rows;
}

class _User extends Fake implements UserRepository {
  var entity = UserEntity(
    birthday: DateTime(1990, 1, 1),
    heightCM: 180,
    weightKG: 85,
    gender: UserGenderEntity.male,
    goal: UserWeightGoalEntity.loseWeight,
    pal: UserPALEntity.active,
  );

  @override
  Future<UserEntity> getUserData() async => entity;

  @override
  Future<void> updateUserData(UserEntity userEntity) async =>
      entity = userEntity;
}

void main() {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final yesterday = DateTime(now.year, now.month, now.day - 1);
  final before = DateTime(now.year, now.month, now.day - 2);

  test("deleting today's weigh-in puts the profile weight back to the "
      'newest one left', () async {
    final user = _User();
    final log = _Log([
      WeightLogEntity(date: before, weightKg: 88),
      WeightLogEntity(date: yesterday, weightKg: 87.1),
      WeightLogEntity(date: today, weightKg: 85),
    ]);
    await DeleteWeightLogUsecase(log, user).deleteEntry(log.rows.last);
    expect(user.entity.weightKG, 87.1);
  });

  test("an older weigh-in's delete leaves the profile weight", () async {
    final user = _User();
    final log = _Log([
      WeightLogEntity(date: yesterday, weightKg: 87.1),
      WeightLogEntity(date: today, weightKg: 85),
    ]);
    await DeleteWeightLogUsecase(log, user).deleteEntry(log.rows.first);
    expect(user.entity.weightKG, 85);
  });
}
