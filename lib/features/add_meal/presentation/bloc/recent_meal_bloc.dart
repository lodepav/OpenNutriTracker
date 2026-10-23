import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:logging/logging.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_intake_usecase.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
// [fork] S19 recents-by-meal
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/fork/recents/recents_by_meal.dart';
// [/fork]

part 'recent_meal_event.dart';

part 'recent_meal_state.dart';

class RecentMealBloc extends Bloc<RecentMealEvent, RecentMealState> {
  final log = Logger('RecentMealBloc');

  final GetIntakeUsecase _getIntakeUsecase;
  final GetConfigUsecase _getConfigUsecase;

  // [fork] S19 recents-by-meal: the meal being added to, set by the
  // add-meal screen; null leaves the recents in upstream's order
  IntakeTypeEntity? forkMeal;
  // [/fork]

  RecentMealBloc(this._getIntakeUsecase, this._getConfigUsecase)
      : super(RecentMealInitial()) {
    on<LoadRecentMealEvent>((event, emit) async {
      emit(RecentMealLoadingState());
      try {
        final config = await _getConfigUsecase.getConfig();
        // [fork] S19 recents-by-meal
        final recentIntake = await recentsForMeal(
          await _getIntakeUsecase.getRecentIntake(),
          forkMeal,
        );
        // [/fork]
        final searchString = (event.searchString).toLowerCase();

        if (searchString.isEmpty) {
          emit(
            RecentMealLoadedState(
              recentMeals: recentIntake.map((intake) => intake.meal).toList(),
              usesImperialUnits: config.usesImperialFoodUnits,
            ),
          );
        } else {
          emit(
            RecentMealLoadedState(
              recentMeals: recentIntake
                  .where(matchesSearchString(searchString))
                  .map((intake) => intake.meal)
                  .toList(),
              usesImperialUnits: config.usesImperialFoodUnits,
            ),
          );
        }
      } catch (error) {
        log.severe(error);
        emit(RecentMealFailedState());
      }
    });
  }

  bool Function(IntakeEntity) matchesSearchString(String searchString) {
    return (intake) =>
        (intake.meal.name?.toLowerCase().contains(searchString) ?? false) ||
        (intake.meal.brands?.toLowerCase().contains(searchString) ?? false);
  }
}
