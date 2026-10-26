import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:logging/logging.dart';
import 'package:opennutritracker/core/data/data_source/custom_meal_data_source.dart';
import 'package:opennutritracker/core/data/repository/favourite_meal_repository.dart';
import 'package:opennutritracker/core/domain/usecase/add_tracked_day_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/delete_intake_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_intake_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/merge_custom_meals_usecase.dart';
import 'package:opennutritracker/core/utils/tracked_day_lock.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';

part 'custom_meals_event.dart';
part 'custom_meals_state.dart';

class CustomMealsBloc extends Bloc<CustomMealsEvent, CustomMealsState> {
  final log = Logger('CustomMealsBloc');

  final CustomMealDataSource _customMealDataSource;
  // [fork] S142 keep-history: unused since a delete keeps past entries;
  // kept so the constructor stays upstream's
  // ignore: unused_field
  final GetIntakeUsecase _getIntakeUsecase;
  // ignore: unused_field
  final DeleteIntakeUsecase _deleteIntakeUsecase;
  // ignore: unused_field
  final AddTrackedDayUsecase _addTrackedDayUsecase;
  // [/fork]
  final MergeCustomMealsUseCase _mergeCustomMealsUseCase;
  final FavouriteMealRepository _favouriteMealRepository; // #1307

  CustomMealsBloc(
    this._customMealDataSource,
    this._getIntakeUsecase,
    this._deleteIntakeUsecase,
    this._addTrackedDayUsecase,
    this._mergeCustomMealsUseCase,
    this._favouriteMealRepository,
  ) : super(CustomMealsInitial()) {
    on<LoadCustomMealsEvent>((event, emit) async {
      emit(CustomMealsLoadingState());
      try {
        final meals = _customMealDataSource
            .getAllCustomMeals()
            .map(MealEntity.fromMealDBO)
            .toList();
        emit(CustomMealsLoadedState(meals: meals));
      } catch (error) {
        log.severe(error);
        emit(CustomMealsFailedState());
      }
    });

    on<DeleteCustomMealEvent>((event, emit) async {
      emit(CustomMealsLoadingState());
      try {
        final deleted = await withTrackedDayLockOnProfile(() async {
          // A starred meal stays on Favourites as its snapshot; bring that
          // up to the version being deleted first.
          await _favouriteMealRepository.keepLatestCustomMealSnapshot(
            event.mealKey,
          );
          await _customMealDataSource.deleteCustomMeal(event.mealKey);

          // [fork] S142 keep-history: past entries stay, as a deleted
          // recipe's do; each holds its own copy of the food, and taking
          // them would rewrite past days and the expenditure (H3)
          // [/fork]
          return true;
        });
        if (deleted != true) return;
        add(LoadCustomMealsEvent());
      } catch (error) {
        log.severe(error);
        emit(CustomMealsFailedState());
      }
    });

    on<MergeCustomMealsEvent>((event, emit) async {
      emit(CustomMealsLoadingState());
      try {
        final result = await withTrackedDayLockOnProfile(
          () => _mergeCustomMealsUseCase
              .merge(loserKey: event.loserKey, winnerKey: event.winnerKey)
              .then((result) => result),
        );
        if (result == null) return;
        final meals = _customMealDataSource
            .getAllCustomMeals()
            .map(MealEntity.fromMealDBO)
            .toList();
        emit(
          CustomMealsMergedState(
            meals: meals,
            rewrittenIntakeCount: result.rewrittenIntakeCount,
            winnerDisplayName: result.winnerDisplayName,
          ),
        );
      } catch (error) {
        log.severe(error);
        emit(CustomMealsFailedState());
      }
    });
  }
}
