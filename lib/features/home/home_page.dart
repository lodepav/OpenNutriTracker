import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:logging/logging.dart';
import 'package:opennutritracker/core/domain/entity/calories_profile_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_gender_entity.dart';
import 'package:opennutritracker/core/presentation/widgets/empty_hint.dart';
import 'package:opennutritracker/core/presentation/widgets/low_kcal_warning_card.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/calc/calorie_goal_calc.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/domain/entity/tracked_day_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_activity_entity.dart';
// [fork] S151 own-screens: the fork's activity list (D23)
// import 'package:opennutritracker/core/presentation/widgets/activity_vertial_list.dart';
import 'package:opennutritracker/fork/screens/activity/activity_vertial_list.dart';
// [/fork]
import 'package:opennutritracker/core/presentation/widgets/edit_activity_dialog.dart';
import 'package:opennutritracker/core/presentation/widgets/edit_dialog.dart';
import 'package:opennutritracker/core/presentation/widgets/delete_dialog.dart';
import 'package:opennutritracker/core/presentation/widgets/disclaimer_dialog.dart';
import 'package:opennutritracker/core/domain/usecase/import_workouts_usecase.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/add_meal/presentation/add_meal_type.dart';
import 'package:opennutritracker/features/diary/presentation/bloc/calendar_day_bloc.dart';
import 'package:opennutritracker/features/diary/presentation/bloc/diary_bloc.dart';
import 'package:opennutritracker/features/home/presentation/bloc/home_bloc.dart';
// [fork] S154 own-home: the fork's copies (D23)
import 'package:opennutritracker/fork/screens/home/dashboard_widget.dart';
import 'package:opennutritracker/fork/screens/home/intake_vertical_list.dart';
// [/fork]
// [fork] S119 home-tiles: fasting_home_chip, quick_water_widget and
// quick_weight_widget are tiles now (lib/fork/display/home_tiles.dart)
import 'package:opennutritracker/fork/display/home_tiles.dart';
import 'package:opennutritracker/core/domain/entity/body_weight_unit_entity.dart';
import 'package:opennutritracker/generated/l10n.dart';
// [fork] S10 meal-groups: leftovers of a whole meal (D14)
import 'package:opennutritracker/fork/leftovers/group_leftovers.dart';
// [/fork]
// [fork] S13 adaptive-check-in: the weekly check-in card (D13)
import 'package:opennutritracker/fork/adaptive/adaptive_ui.dart';
// [/fork]
// [fork] S43 meal-plan
import 'package:opennutritracker/fork/plan/plan_ui.dart';
// [/fork]
// [fork] S162 arrange-home
import 'package:opennutritracker/fork/layout/home_layout.dart';
// [/fork]
// [fork] S52 undo-delete
import 'package:opennutritracker/fork/copy/copy_ui.dart';
import 'package:opennutritracker/core/utils/tracked_day_lock.dart';
import 'package:opennutritracker/fork/undo/undo_delete.dart';
// [/fork]

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  final log = Logger('HomePage');

  late HomeBloc _homeBloc;
  bool _isIntakeDragging = false;
  bool _isActivityDragging = false;
  bool get _isDragging => _isIntakeDragging || _isActivityDragging;

  @override
  void initState() {
    WidgetsBinding.instance.addObserver(this);
    _homeBloc = locator<HomeBloc>();
    // Workouts that landed in the health store while the app was closed. Run
    // from here rather than from bootstrap so a launch import reaches the
    // same diary refresh a resume import does.
    unawaited(_importHealthWorkouts());
    super.initState();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<HomeBloc, HomeState>(
      bloc: _homeBloc,
      builder: (context, state) {
        if (state is HomeInitial) {
          _homeBloc.add(const LoadItemsEvent());
          return _getLoadingContent();
        } else if (state is HomeLoadingState) {
          return _getLoadingContent();
        } else if (state is HomeLoadedState) {
          return _getLoadedContent(
            context,
            state.showDisclaimerDialog,
            state.totalKcalDaily,
            state.userGender,
            state.userCaloriesProfile,
            state.totalKcalLeft,
            state.totalKcalSupplied,
            state.totalKcalBurned,
            state.totalCarbsIntake,
            state.totalFatsIntake,
            state.totalProteinsIntake,
            state.totalCarbsGoal,
            state.totalFatsGoal,
            state.totalProteinsGoal,
            state.breakfastIntakeList,
            state.lunchIntakeList,
            state.dinnerIntakeList,
            state.snackIntakeList,
            state.userActivityList,
            state.usesImperialUnits,
            state.bodyWeightUnit,
            state.showActivityTracking,
            state.showMealMacros,
            state.userWeightKg,
            state.breakfastKcalTarget,
            state.lunchKcalTarget,
            state.dinnerKcalTarget,
            state.snackKcalTarget,
            state.breakfastSharePct,
            state.lunchSharePct,
            state.dinnerSharePct,
            state.snackSharePct,
            state.waterMlToday,
            state.waterGoalMl,
          );
        } else {
          return _getLoadingContent();
        }
      },
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      log.info('App resumed');
      _refreshPageOnDayChange();
      unawaited(_importHealthWorkouts());
    }
    super.didChangeAppLifecycleState(state);
  }

  Widget _getLoadingContent() {
    return const Center(child: CircularProgressIndicator());
  }

  Widget _getLoadedContent(
    BuildContext context,
    bool showDisclaimerDialog,
    double totalKcalDaily,
    UserGenderEntity userGender,
    CaloriesProfileEntity? userCaloriesProfile,
    double totalKcalLeft,
    double totalKcalSupplied,
    double totalKcalBurned,
    double totalCarbsIntake,
    double totalFatsIntake,
    double totalProteinsIntake,
    double totalCarbsGoal,
    double totalFatsGoal,
    double totalProteinsGoal,
    List<IntakeEntity> breakfastIntakeList,
    List<IntakeEntity> lunchIntakeList,
    List<IntakeEntity> dinnerIntakeList,
    List<IntakeEntity> snackIntakeList,
    List<UserActivityEntity> userActivities,
    bool usesImperialUnits,
    BodyWeightUnit bodyWeightUnit,
    bool showActivityTracking,
    bool showMealMacros,
    double userWeightKg,
    double breakfastKcalTarget,
    double lunchKcalTarget,
    double dinnerKcalTarget,
    double snackKcalTarget,
    int breakfastSharePct,
    int lunchSharePct,
    int dinnerSharePct,
    int snackSharePct,
    int waterMlToday,
    int waterGoalMl,
  ) {
    if (showDisclaimerDialog) {
      _showDisclaimerDialog(context);
    }
    return Stack(
      children: [
        // [fork] S162 arrange-home: the sections as arranged, by id; one
        // not shown today is null
        HomeSectionsList(
          sections: {
            'dashboard': Padding(
              // S119: the chips are tiles under the card now.
              padding: const EdgeInsets.only(top: Dimens.spacing8),
              child: DashboardWidget(
                totalKcalDaily: totalKcalDaily,
                totalKcalLeft: totalKcalLeft,
                totalKcalSupplied: totalKcalSupplied,
                totalKcalBurned: totalKcalBurned,
                totalCarbsIntake: totalCarbsIntake,
                totalFatsIntake: totalFatsIntake,
                totalProteinsIntake: totalProteinsIntake,
                totalCarbsGoal: totalCarbsGoal,
                totalFatsGoal: totalFatsGoal,
                totalProteinsGoal: totalProteinsGoal,
                intakes: [
                  ...breakfastIntakeList,
                  ...lunchIntakeList,
                  ...dinnerIntakeList,
                  ...snackIntakeList,
                ],
                usesImperialUnits: usesImperialUnits,
                forkDay: _homeBloc.currentDay, // [fork] S119
              ),
            ),
            'tiles': HomeTiles(
              weightKg: userWeightKg,
              bodyWeightUnit: bodyWeightUnit,
              waterMl: waterMlToday,
              waterGoalMl: waterGoalMl,
            ),
            // S13 adaptive-check-in
            'checkIn': AdaptiveCheckInCard(
              onAccepted: () => _homeBloc.add(const LoadItemsEvent()),
            ),
            // S43 meal-plan: today's planned foods, to tick off
            'plan': PlannedFoodsCard(day: _homeBloc.currentDay),
            'notices': Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Day-one / empty-day guidance: when nothing is logged yet, point
                // the way to the centre + rather than leaving a silent dashboard.
                if (breakfastIntakeList.isEmpty &&
                    lunchIntakeList.isEmpty &&
                    dinnerIntakeList.isEmpty &&
                    snackIntakeList.isEmpty &&
                    userActivities.isEmpty)
                  EmptyHint(
                    icon: Icons.add_circle_outline_rounded,
                    title: S.of(context).homeFirstMealHint,
                  ),
                if (CalorieGoalCalc.isBelowRecommendedDailyKcalFloor(
                  goalKcal: totalKcalDaily,
                  gender: userGender,
                  caloriesProfile: userCaloriesProfile,
                ))
                  LowKcalWarningCard(
                    thresholdKcal: CalorieGoalCalc.recommendedDailyKcalFloor(
                      gender: userGender,
                      caloriesProfile: userCaloriesProfile,
                    ),
                  ),
              ],
            ),
            'activity': showActivityTracking
                ? ActivityVerticalList(
                    day: DateTime.now(),
                    title: S.of(context).activityLabel,
                    userActivityList: userActivities,
                    onItemLongPressedCallback: onActivityItemLongPressed,
                    onItemTappedCallback: onActivityItemTapped,
                    onItemDragCallback: onActivityItemDrag,
                  )
                : null,
            // #150 follow-up: a 0% share (e.g. OMAD sets snack to 0) hides an
            // empty section so the home view doesn't carry a header the user
            // explicitly opted out of. A section that holds intakes always
            // shows, so they stay editable and deletable (#1305).
            'breakfast':
                IntakeVerticalList.isShown(
                  sharePct: breakfastSharePct,
                  intakes: breakfastIntakeList,
                )
                ? IntakeVerticalList(
                    day: DateTime.now(),
                    title: S.of(context).breakfastLabel,
                    listIcon: IntakeTypeEntity.breakfast.getIconData(),
                    addMealType: AddMealType.breakfastType,
                    intakeList: breakfastIntakeList,
                    onDeleteIntakeCallback: onDeleteIntake,
                    onItemDragCallback: onIntakeItemDrag,
                    onItemTappedCallback: onIntakeItemTapped,
                    usesImperialUnits: usesImperialUnits,
                    showMealMacros: showMealMacros,
                    mealKcalTarget: breakfastKcalTarget,
                  )
                : null,
            'lunch':
                IntakeVerticalList.isShown(
                  sharePct: lunchSharePct,
                  intakes: lunchIntakeList,
                )
                ? IntakeVerticalList(
                    day: DateTime.now(),
                    title: S.of(context).lunchLabel,
                    listIcon: IntakeTypeEntity.lunch.getIconData(),
                    addMealType: AddMealType.lunchType,
                    intakeList: lunchIntakeList,
                    onDeleteIntakeCallback: onDeleteIntake,
                    onItemDragCallback: onIntakeItemDrag,
                    onItemTappedCallback: onIntakeItemTapped,
                    usesImperialUnits: usesImperialUnits,
                    showMealMacros: showMealMacros,
                    mealKcalTarget: lunchKcalTarget,
                  )
                : null,
            'dinner':
                IntakeVerticalList.isShown(
                  sharePct: dinnerSharePct,
                  intakes: dinnerIntakeList,
                )
                ? IntakeVerticalList(
                    day: DateTime.now(),
                    title: S.of(context).dinnerLabel,
                    addMealType: AddMealType.dinnerType,
                    listIcon: IntakeTypeEntity.dinner.getIconData(),
                    intakeList: dinnerIntakeList,
                    onDeleteIntakeCallback: onDeleteIntake,
                    onItemDragCallback: onIntakeItemDrag,
                    onItemTappedCallback: onIntakeItemTapped,
                    usesImperialUnits: usesImperialUnits,
                    showMealMacros: showMealMacros,
                    mealKcalTarget: dinnerKcalTarget,
                  )
                : null,
            'snack':
                IntakeVerticalList.isShown(
                  sharePct: snackSharePct,
                  intakes: snackIntakeList,
                )
                ? IntakeVerticalList(
                    day: DateTime.now(),
                    title: S.of(context).snackLabel,
                    listIcon: IntakeTypeEntity.snack.getIconData(),
                    addMealType: AddMealType.snackType,
                    intakeList: snackIntakeList,
                    onDeleteIntakeCallback: onDeleteIntake,
                    onItemDragCallback: onIntakeItemDrag,
                    onItemTappedCallback: onIntakeItemTapped,
                    usesImperialUnits: usesImperialUnits,
                    showMealMacros: showMealMacros,
                    mealKcalTarget: snackKcalTarget,
                  )
                : null,
          },
        ),
        // [/fork]
        Align(
          alignment: Alignment.bottomCenter,
          child: Visibility(
            visible: _isDragging,
            child: SizedBox(
              height: 70,
              child: Stack(
                children: [
                  DragTarget<IntakeEntity>(
                    onAcceptWithDetails: (data) {
                      _confirmDelete(context, data.data);
                    },
                    onLeave: (data) {
                      setState(() {
                        _isIntakeDragging = false;
                      });
                    },
                    builder: (context, candidateData, rejectedData) {
                      return Container(
                        margin: const EdgeInsets.fromLTRB(
                          Dimens.spacing16,
                          0,
                          Dimens.spacing16,
                          Dimens.spacing12,
                        ),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.error,
                          borderRadius: Dimens.borderRadiusL,
                        ),
                        child: Center(
                          child: Icon(
                            Icons.delete_rounded,
                            size: 32,
                            color: Theme.of(context).colorScheme.onError,
                          ),
                        ),
                      );
                    },
                  ),
                  DragTarget<UserActivityEntity>(
                    onAcceptWithDetails: (data) {
                      _confirmDeleteActivity(context, data.data);
                    },
                    onLeave: (data) {
                      setState(() {
                        _isActivityDragging = false;
                      });
                    },
                    builder: (context, candidateData, rejectedData) {
                      return const SizedBox.expand();
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  void onActivityItemLongPressed(
    BuildContext context,
    UserActivityEntity activityEntity,
  ) async {
    final deleteIntake = await showDialog<bool>(
      context: context,
      builder: (context) => const DeleteDialog(),
    );

    if (deleteIntake != null) {
      await _homeBloc.deleteUserActivityItem(activityEntity);
      _homeBloc.add(const LoadItemsEvent());
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.of(context).itemDeletedSnackbar)),
        );
      }
    }
  }

  void onIntakeItemLongPressed(
    BuildContext context,
    IntakeEntity intakeEntity,
  ) async {
    // [fork] S52 undo-delete: deleted at once, with Undo on the snackbar,
    // in place of upstream's confirmation dialog. The write can wait for the
    // tracked-day lock (#1317), and Home reloads only once it is stored.
    await onDeleteIntake(intakeEntity, null);
    // [/fork]
  }

  void onIntakeItemDrag(bool isDragging) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      setState(() {
        _isIntakeDragging = isDragging;
      });
    });
  }

  void onActivityItemDrag(bool isDragging) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      setState(() {
        _isActivityDragging = isDragging;
      });
    });
  }

  void onActivityItemTapped(
    BuildContext context,
    UserActivityEntity activityEntity,
  ) async {
    final newDuration = await showDialog<double>(
      context: context,
      builder: (context) => EditActivityDialog(activityEntity: activityEntity),
    );
    if (newDuration != null) {
      await _homeBloc.updateUserActivityItem(activityEntity, newDuration);
      _homeBloc.add(const LoadItemsEvent());
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.of(context).itemUpdatedSnackbar)),
        );
      }
    }
  }

  void onIntakeItemTapped(
    BuildContext context,
    IntakeEntity intakeEntity,
    bool usesImperialUnits,
  ) async {
    // [fork] S10 meal-groups
    var mealEdited = false;
    final handled = await editMealGroupLeftovers(
      context,
      intakeEntity,
      update: (id, amount) {
        mealEdited = true;
        return _homeBloc.updateIntakeItem(id, {'amount': amount});
      },
      usesImperialUnits: usesImperialUnits, // [fork] S90
    );
    if (handled) {
      if (!mealEdited) return;
      _homeBloc.add(const LoadItemsEvent());
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.of(context).itemUpdatedSnackbar)),
        );
      }
      return;
    }
    if (!context.mounted) return;
    // [/fork]
    final changeIntakeAmount = await showDialog<double>(
      context: context,
      builder: (context) => EditDialog(
        intakeEntity: intakeEntity,
        usesImperialUnits: usesImperialUnits,
      ),
    );
    // [fork] S83 tap-delete
    if (changeIntakeAmount == EditDialog.deleteResult) {
      await onDeleteIntake(intakeEntity, null);
      return;
    }
    // [/fork]
    if (changeIntakeAmount != null) {
      await _homeBloc.updateIntakeItem(intakeEntity.id, {
        'amount': changeIntakeAmount,
      });
      _homeBloc.add(const LoadItemsEvent());
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.of(context).itemUpdatedSnackbar)),
        );
      }
    }
  }

  Future<void> onDeleteIntake(
    IntakeEntity intake,
    TrackedDayEntity? trackedDayEntity,
  ) async {
    // [fork] S52 undo-delete: the profile and day it is taken from, for the
    // undo
    final stamp = ProfileStamp.now();
    final day = await logicalToday();
    // [/fork]
    await _homeBloc.deleteIntakeItem(intake);
    _homeBloc.add(const LoadItemsEvent());
    // [fork] S52 undo-delete
    if (mounted) DeletedEntries.show(context, intake, day, startedOn: stamp);
    // [/fork]
  }

  void _confirmDelete(BuildContext context, IntakeEntity intake) async {
    // [fork] S52 undo-delete: deleted at once, with Undo on the snackbar,
    // in place of upstream's confirmation dialog
    onDeleteIntake(intake, null);
    // [/fork]
    setState(() {
      _isIntakeDragging = false;
    });
  }

  void _confirmDeleteActivity(
    BuildContext context,
    UserActivityEntity activity,
  ) async {
    final delete = await showDialog<bool>(
      context: context,
      builder: (context) => const DeleteDialog(),
    );
    if (delete == true) {
      await _homeBloc.deleteUserActivityItem(activity);
      _homeBloc.add(const LoadItemsEvent());
    }
    setState(() {
      _isActivityDragging = false;
    });
  }

  /// Show disclaimer dialog after build method
  void _showDisclaimerDialog(BuildContext context) async {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final dialogConfirmed = await showDialog<bool>(
        context: context,
        builder: (context) {
          return const DisclaimerDialog();
        },
      );
      if (dialogConfirmed != null) {
        _homeBloc.saveConfigData(dialogConfirmed);
        _homeBloc.add(const LoadItemsEvent());
      }
    });
  }

  /// Refresh page when day changes
  ///
  /// #139: HomeBloc.currentDay is the logical "today" (midnight of the
  /// configured day boundary). Comparing against a fresh logical "today"
  /// from the same wall clock requires knowing the offset, which we'd
  /// have to fetch from config asynchronously. Letting LoadItemsEvent
  /// re-resolve the offset and reload unconditionally on resume is the
  /// honest cheap path: it costs one config read plus a few Hive scans,
  /// and it is correct under any boundary setting.
  void _refreshPageOnDayChange() {
    _homeBloc.add(const LoadItemsEvent());
  }

  /// Picks up workouts that landed in the platform health store while the app
  /// was away — at launch and on every resume. Debounced, serialized and
  /// opt-in inside the use case, so this costs nothing on an ordinary resume;
  /// the diary only reloads when something actually came in. Failures are
  /// swallowed by [ImportWorkoutsUsecase.importIfDue]: there is no user
  /// waiting on this and nowhere to show an error.
  Future<void> _importHealthWorkouts() async {
    final imported = await locator<ImportWorkoutsUsecase>().importIfDue();
    if (imported == 0 || !mounted) return;
    _homeBloc.add(const LoadItemsEvent());
    locator<DiaryBloc>().add(const LoadDiaryYearEvent());
    locator<CalendarDayBloc>().add(RefreshCalendarDayEvent());
  }
}
