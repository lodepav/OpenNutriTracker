import 'package:collection/collection.dart';
import 'package:opennutritracker/core/data/repository/config_repository.dart';
import 'package:opennutritracker/core/data/repository/user_activity_repository.dart';
import 'package:opennutritracker/core/data/repository/user_repository.dart';
import 'package:opennutritracker/core/domain/entity/user_entity.dart';
import 'package:opennutritracker/core/utils/calc/calorie_goal_calc.dart';
import 'package:opennutritracker/core/utils/calc/day_boundary_calc.dart';
// [fork] S12 adaptive-target: the check-in's target replaces the formula (D13)
import 'package:opennutritracker/fork/adaptive/adaptive_service.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_store.dart';
// [/fork]

class GetKcalGoalUsecase {
  final UserRepository _userRepository;
  final ConfigRepository _configRepository;
  final UserActivityRepository _userActivityRepository;
  // [fork] S12 adaptive-target: another profile's store, for a meal copied
  // into it; null reads the active profile's
  final AdaptiveStore? _forkAdaptive;
  // [/fork]

  GetKcalGoalUsecase(
    this._userRepository,
    this._configRepository,
    this._userActivityRepository, [
    // [fork] S12 adaptive-target
    this._forkAdaptive,
    // [/fork]
  ]);

  Future<double> getKcalGoal({
    UserEntity? userEntity,
    double? totalKcalActivitiesParam,
    double? kcalUserAdjustment,
  }) async {
    // [fork] S12 adaptive-target
    final adaptive = await adaptiveTargetKcal(_forkAdaptive);
    if (adaptive != null) return adaptive;
    // [/fork]
    final user = userEntity ?? await _userRepository.getUserData();
    final config = await _configRepository.getConfig();
    final totalKcalActivities =
        totalKcalActivitiesParam ??
        (await _userActivityRepository.getAllUserActivityByDate(
          // #586: the query takes a day label, so "today" has to be
          // resolved through the boundary first. A raw DateTime.now()
          // here asks for the wall-clock date, which between midnight
          // and the boundary is a different day than the one Home's
          // activity list shows — the goal would silently drop those
          // burned calories.
          DayBoundaryCalc.currentLogicalDayLabel(
            config.dayStartOffsetHours,
            config.dayStartOffsetMinutes,
          ),
          dayStartOffsetHours: config.dayStartOffsetHours,
          dayStartOffsetMinutes: config.dayStartOffsetMinutes,
        )).map((activity) => activity.burnedKcal).toList().sum;
    return CalorieGoalCalc.getTotalKcalGoal(
      user,
      totalKcalActivities,
      kcalUserAdjustment: config.userKcalAdjustment,
      caloriesTaperEnabled: user.caloriesTaperEnabled,
    );
  }
}
