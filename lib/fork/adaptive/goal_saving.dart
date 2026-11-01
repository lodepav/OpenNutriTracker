import 'package:flutter/material.dart';
import 'package:opennutritracker/core/domain/entity/body_weight_unit_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_weight_goal_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_kcal_goal_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_user_usecase.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/core/utils/tracked_day_lock.dart';
import 'package:opennutritracker/features/profile/presentation/bloc/profile_bloc.dart';
import 'package:opennutritracker/features/profile/presentation/widgets/set_target_weight_dialog.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_store.dart';
import 'package:opennutritracker/fork/phase/shared_phase.dart';

/// Bumped when [savePace] saved a pace (by hand or a diet phase), so the
/// goal planner reloads.
final paceChanges = ValueNotifier(0);

/// Saves [kgPerWeek] as the profile's pace, the goal following its phase,
/// through upstream's profile update (which rewrites today's goal). False
/// when a profile switch dropped the update: the user is read and written
/// for the profile current at [startedOn] (by default, as it begins).
Future<bool> savePace(double kgPerWeek, [ProfileStamp? startedOn]) async {
  // Read and updated under the tracked-day lock, which a switch takes too:
  // the update, under the same (reentrant) lock, writes to this profile.
  final saved = await withTrackedDayLockOnProfile(() async {
    final user = await locator<GetUserUsecase>().getUserData();
    _setPace(user, kgPerWeek);
    await locator<ProfileBloc>().updateUser(user);
    return true;
  }, startedOn: startedOn);
  if (saved == null) return false;
  paceChanges.value++;
  return true;
}

/// Saves [kgPerWeek] as [savePace] does, and [targetKg] as the target
/// weight, each unless it is null, in one profile update.
Future<bool> saveGoal(
  double? kgPerWeek,
  double? targetKg, [
  ProfileStamp? startedOn,
]) async {
  final saved = await withTrackedDayLockOnProfile(() async {
    final user = await locator<GetUserUsecase>().getUserData();
    if (kgPerWeek != null) _setPace(user, kgPerWeek);
    user.targetWeightKg = targetKg;
    await locator<ProfileBloc>().updateUser(user);
    return true;
  }, startedOn: startedOn);
  if (saved == null) return false;
  paceChanges.value++;
  return true;
}

/// The goal a pace of [kgPerWeek] is: a small pace either way is still
/// maintaining ([phaseOfRate]), though its calories still count.
UserWeightGoalEntity goalOfPace(double kgPerWeek) =>
    switch (phaseOfRate(kgPerWeek)) {
      'cutting' => UserWeightGoalEntity.loseWeight,
      'bulking' => UserWeightGoalEntity.gainWeight,
      _ => UserWeightGoalEntity.maintainWeight,
    };

/// [kgPerWeek] as [user]'s pace, the goal following it.
void _setPace(UserEntity user, double kgPerWeek) => user
  ..weeklyWeightGoalKg = kgPerWeek
  ..goal = goalOfPace(kgPerWeek);

/// Home's goal today, worked out as Home works it out; null when a fixed or
/// adaptive target sets it, which a pace does not move.
Future<double?> formulaGoal() async {
  final settings = AdaptiveStore.settings.value;
  if (settings.fixedTarget || settings.adaptiveTarget) return null;
  if (!locator.isRegistered<GetKcalGoalUsecase>()) return null;
  return locator<GetKcalGoalUsecase>().getKcalGoal();
}

/// Asks for a target weight with upstream's dialog, seeded from [targetKg]
/// or, with none yet, [nowKg], and saves it to the profile as the Profile
/// page does; with a target, Clear takes it off. False when cancelled, or
/// a profile switch dropped the update.
Future<bool> setTargetWeight(
  BuildContext context,
  BodyWeightUnit unit,
  double nowKg,
  double? targetKg,
) async {
  final startedOn = ProfileStamp.now();
  final result = await showDialog<TargetWeightDialogResult>(
    context: context,
    builder: (_) => SetTargetWeightDialog(
      initialKg: targetKg ?? nowKg,
      hasExistingTarget: targetKg != null,
      unit: unit,
    ),
  );
  if (result == null || (result.value == null && !result.clear)) return false;
  final saved = await withTrackedDayLockOnProfile(() async {
    final user = await locator<GetUserUsecase>().getUserData();
    user.targetWeightKg = result.value;
    await locator<ProfileBloc>().updateUser(user);
    return true;
  }, startedOn: startedOn);
  if (saved == null) return false;
  paceChanges.value++;
  return true;
}
