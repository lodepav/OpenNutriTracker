part of 'recent_meal_bloc.dart';

abstract class RecentMealState extends Equatable {
  const RecentMealState();
}

class RecentMealInitial extends RecentMealState {
  @override
  List<Object> get props => [];
}

class RecentMealLoadingState extends RecentMealState {
  @override
  List<Object?> get props => [];
}

class RecentMealLoadedState extends RecentMealState {
  final List<MealEntity> recentMeals;
  final bool usesImperialUnits;
  // [fork] S116 search-dense: the latest entry of each of [recentMeals],
  // in the same order, so a row can show the amount last logged
  final List<IntakeEntity> forkIntakes;
  // [/fork]

  const RecentMealLoadedState({
    required this.recentMeals,
    this.usesImperialUnits = false,
    this.forkIntakes = const [], // [fork] S116
  });

  @override
  List<Object?> get props => [
    recentMeals,
    usesImperialUnits,
    forkIntakes, // [fork] S116
  ];
}

class RecentMealFailedState extends RecentMealState {
  @override
  List<Object?> get props => [];
}
