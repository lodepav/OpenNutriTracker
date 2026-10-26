// Fork-owned copy of lib/features/diary/presentation/widgets/day_info_widget.dart (D23); upstream's later changes to it
// are ported by hand: fork/tools/upstream-copies.sh.
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/domain/entity/tracked_day_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_activity_entity.dart';
import 'package:opennutritracker/core/presentation/widgets/activity_vertial_list.dart';
import 'package:opennutritracker/core/presentation/widgets/copy_or_delete_dialog.dart';
// core/presentation/widgets/macro_nutriments_widget.dart, unused since the day card
// upstream's CopyDialog import, unused since
// import 'package:opennutritracker/core/presentation/widgets/copy_dialog.dart';
// core/presentation/widgets/app_card.dart, unused since the day card
import 'package:opennutritracker/core/presentation/widgets/empty_hint.dart';
import 'package:opennutritracker/core/presentation/widgets/delete_dialog.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
// core/utils/calc/unit_calc.dart, unused since the day card
import 'package:opennutritracker/core/utils/custom_icons.dart';
// core/utils/energy_unit_provider.dart, unused since the day card
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/add_meal/presentation/add_meal_type.dart';
import 'package:opennutritracker/features/diary/presentation/bloc/calendar_day_bloc.dart';
import 'package:opennutritracker/features/diary/presentation/widgets/daily_nutrient_panel.dart';
import 'package:opennutritracker/features/diary/presentation/widgets/diary_sort_type.dart';
import 'package:opennutritracker/features/home/presentation/widgets/intake_vertical_list.dart';
import 'package:opennutritracker/fork/plan/plan_ui.dart';
import 'package:opennutritracker/fork/copy/copy_ui.dart';
import 'package:opennutritracker/fork/copy/select_entries_screen.dart';
import 'package:opennutritracker/fork/timeline/timeline.dart';
// leave a part-logged day out of expenditure (D17)
import 'package:opennutritracker/fork/adaptive/skip_day.dart';
import 'package:opennutritracker/fork/display/diary_timeline.dart';
import 'package:opennutritracker/fork/display/day_totals_card.dart';
import 'package:opennutritracker/fork/display/diary_by_hour.dart';
import 'package:opennutritracker/fork/display/display_prefs.dart';
import 'package:opennutritracker/generated/l10n.dart';
// provider, unused since the day card

class DayInfoWidget extends StatefulWidget {
  final DateTime selectedDay;

  /// The Diary's "today": the logical day under the "Day starts at"
  /// boundary, which is yesterday's date while the boundary is still
  /// ahead (#1360). Copying an entry goes to this day, so it is offered
  /// only on the other days; on this one a copy would land on the same
  /// day as a duplicate.
  final DateTime currentDay;
  final TrackedDayEntity? trackedDayEntity;
  final List<UserActivityEntity> userActivities;
  final List<IntakeEntity> breakfastIntake;
  final List<IntakeEntity> lunchIntake;
  final List<IntakeEntity> dinnerIntake;
  final List<IntakeEntity> snackIntake;
  // #150: per-meal recommended kcal targets for the selected calendar day.
  // 0 means no target should be shown for that section (e.g. days with no
  // tracked daily goal).
  final double breakfastKcalTarget;
  final double lunchKcalTarget;
  final double dinnerKcalTarget;
  final double snackKcalTarget;
  // #150 follow-up: per-meal share percentages. A 0% share hides the section
  // while it is empty — useful for OMAD / two-meal users who don't want an
  // empty meal slot they've explicitly opted out of staring back at them.
  final int breakfastSharePct;
  final int lunchSharePct;
  final int dinnerSharePct;
  final int snackSharePct;

  final bool usesImperialUnits;
  final bool showMealMacros;
  // When the user disables Show Activity Tracking in Settings, the diary's
  // per-day Activity section is hidden alongside the home one.
  final bool showActivityTracking;
  // Persisted per-meal sort preference loaded by [CalendarDayBloc]. Keys are
  // meal-type strings (breakfast / lunch / dinner / snack) and values are
  // [DiarySortType] enum indices. Null when the user has never picked a
  // sort, in which case every section starts on [DiarySortType.timeAdded].
  final Map<String, int>? diarySortPreferences;
  // The delete callbacks get the day the entry was listed under when the
  // user long-pressed it. [selectedDay] can move while the dialogs are
  // open (the Diary follows "today" across a day boundary, #1360), and the
  // row to debit is the entry's day, not the one shown afterwards.
  final Function(IntakeEntity intake, DateTime day) onDeleteIntake;
  final Function(UserActivityEntity userActivityEntity, DateTime day)
  onDeleteActivity;
  final Function(
    IntakeEntity intake,
    TrackedDayEntity? trackedDayEntity,
    AddMealType? type,
  )
  onCopyIntake;
  final Function(
    UserActivityEntity userActivityEntity,
    TrackedDayEntity? trackedDayEntity,
  )
  onCopyActivity;
  final Function(
    BuildContext context,
    IntakeEntity intake,
    bool usesImperialUnits,
  )?
  onEditIntake;
  final Function(BuildContext context, UserActivityEntity activity)?
  onEditActivity;

  const DayInfoWidget({
    super.key,
    required this.selectedDay,
    required this.currentDay,
    required this.trackedDayEntity,
    required this.userActivities,
    required this.breakfastIntake,
    required this.lunchIntake,
    required this.dinnerIntake,
    required this.snackIntake,
    required this.usesImperialUnits,
    this.showMealMacros = true,
    this.showActivityTracking = true,
    this.diarySortPreferences,
    required this.onDeleteIntake,
    required this.onDeleteActivity,
    required this.onCopyIntake,
    required this.onCopyActivity,
    this.onEditIntake,
    this.onEditActivity,
    this.breakfastKcalTarget = 0,
    this.lunchKcalTarget = 0,
    this.dinnerKcalTarget = 0,
    this.snackKcalTarget = 0,
    this.breakfastSharePct = 30,
    this.lunchSharePct = 40,
    this.dinnerSharePct = 20,
    this.snackSharePct = 10,
  });

  @override
  State<DayInfoWidget> createState() => _DayInfoWidgetState();
}

class _DayInfoWidgetState extends State<DayInfoWidget> {
  // Per-meal sort selection. Seeded from the persisted preferences on
  // [ConfigDBO] (via [CalendarDayBloc]) so the choice survives navigation
  // and app restart, and falls back to [DiarySortType.timeAdded] for any
  // meal type the user has not yet customised. We keep a local widget-state
  // copy so the picker updates optimistically without waiting for the next
  // calendar-day reload.
  late Map<IntakeTypeEntity, DiarySortType> _sortByMeal;

  @override
  void initState() {
    super.initState();
    _sortByMeal = _seedFromPreferences(widget.diarySortPreferences);
  }

  @override
  void didUpdateWidget(covariant DayInfoWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If the bloc emits an updated preference map (for example because the
    // user switched days and the freshly loaded config has a different
    // breakfast sort), reseed so the picker reflects what's persisted.
    if (oldWidget.diarySortPreferences != widget.diarySortPreferences) {
      _sortByMeal = _seedFromPreferences(widget.diarySortPreferences);
    }
  }

  Map<IntakeTypeEntity, DiarySortType> _seedFromPreferences(
    Map<String, int>? persisted,
  ) {
    Map<IntakeTypeEntity, DiarySortType> defaults() => {
      IntakeTypeEntity.breakfast: DiarySortType.timeAdded,
      IntakeTypeEntity.lunch: DiarySortType.timeAdded,
      IntakeTypeEntity.dinner: DiarySortType.timeAdded,
      IntakeTypeEntity.snack: DiarySortType.timeAdded,
    };

    if (persisted == null) return defaults();

    final seeded = defaults();
    for (final mealType in IntakeTypeEntity.values) {
      final storedIndex = persisted[mealType.name];
      if (storedIndex == null) continue;
      // Defensive bound check — if a future build ever removes a sort
      // option, an older index might land here. Falling back to the default
      // keeps the diary from crashing on stale data.
      if (storedIndex < 0 || storedIndex >= DiarySortType.values.length) {
        continue;
      }
      seeded[mealType] = DiarySortType.values[storedIndex];
    }
    return seeded;
  }

  void _setSortFor(IntakeTypeEntity mealType, DiarySortType sortType) {
    setState(() {
      _sortByMeal[mealType] = sortType;
    });
    // Persist asynchronously — we don't block the UI on the write. The
    // optimistic widget-state update above means the picker reflects the
    // user's choice immediately even if the disk write is still in flight.
    locator<CalendarDayBloc>().setDiarySortPreference(
      mealType.name,
      sortType.index,
    );
  }

  @override
  Widget build(BuildContext context) {
    final trackedDay = widget.trackedDayEntity;
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            Dimens.spacing20,
            Dimens.spacing8,
            Dimens.spacing20,
            Dimens.spacing4,
          ),
          // "Timeline", "Select entries", "Copy day"
          // by the date
          child: Row(
            children: [
              Expanded(
                child: Text(
                  DateFormat.yMMMMEEEEd().format(widget.selectedDay),
                  style: textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              TimelineButton(day: widget.selectedDay),
              if (trackedDay != null) ...[
                SelectEntriesButton(day: widget.selectedDay),
                CopyDayButton(day: widget.selectedDay),
              ],
            ],
          ),
        ),
        const SizedBox(height: Dimens.spacing8),
        // the day's planned foods, to tick off
        PlannedFoodsCard(day: widget.selectedDay),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            trackedDay == null
                ? EmptyHint(
                    icon: Icons.restaurant_rounded,
                    title: S.of(context).nothingAddedLabel,
                  )
                : const SizedBox(),
            // the counts, the energy and the
            // macros against their goals, side by side (upstream's rating
            // and MacroNutrientsView)
            if (trackedDay != null)
              DayTotalsCard(intakes: _allIntakes, trackedDay: trackedDay),
            // under the day's totals
            if (trackedDay != null) SkipDayTile(day: widget.selectedDay),
            // #160 + #173 + #404: Daily micronutrient panel — aggregates
            // ten nutrients (fibre, sodium, saturated fat, sugar, calcium,
            // iron, potassium, vitamin D, vitamin B12, magnesium) across
            // the day's intake list, with a Day/Week toggle that pulls the
            // previous six days' intakes itself via the locator. The
            // tracked-day entity is forwarded so the panel can prefer the
            // user's per-nutrient targets from Settings → Nutrient goals
            // when they've configured any (#173). No-op when there's
            // nothing logged for the current day yet.
            if (_allIntakes.isNotEmpty)
              DailyNutrientPanel(
                intakes: _allIntakes,
                selectedDay: widget.selectedDay,
                trackedDay: widget.trackedDayEntity,
              ),
            if (widget.showActivityTracking) ...[
              const SizedBox(height: Dimens.spacing8),
              ActivityVerticalList(
                day: widget.selectedDay,
                title: S.of(context).activityLabel,
                userActivityList: widget.userActivities,
                onItemLongPressedCallback: onActivityItemLongPressed,
                onItemTappedCallback: widget.onEditActivity,
                onCopyActivityCallback: _showsCurrentDay
                    ? null
                    : (activity) => widget.onCopyActivity(
                        activity,
                        widget.trackedDayEntity,
                      ),
              ),
            ],
            // the day's foods by the hour eaten, in
            // place of the four meals
            if (DisplayPrefs.diaryByHour.value)
              for (final section in hourSections(_allIntakes))
                IntakeVerticalList(
                  key: ValueKey('diary-hour-${section.title}'),
                  day: widget.selectedDay,
                  title: section.title,
                  listIcon: Icons.schedule_rounded,
                  addMealType: section.addMealType,
                  intakeList: section.intakes,
                  onDeleteIntakeCallback: _deleteIntakeOnShownDay,
                  onItemLongPressedCallback: onIntakeItemLongPressed,
                  onItemTappedCallback: widget.onEditIntake,
                  onCopyIntakeCallback: widget.onCopyIntake,
                  usesImperialUnits: widget.usesImperialUnits,
                  showMealMacros: widget.showMealMacros,
                  trackedDayEntity: trackedDay,
                  hourSection: true,
                ),
            if (DisplayPrefs.diaryByHour.value)
              HourAddCard(day: widget.selectedDay),
            // #150 follow-up: a 0% share hides an empty section so OMAD users
            // (and anyone else who's set a meal slot to 0%) don't see a meal
            // type they explicitly opted out of. A section that holds intakes
            // always shows, so they stay editable and deletable (#1305).
            // the meals in the order eaten
            if (!DisplayPrefs.diaryByHour.value)
              ...diaryTimeline(widget.selectedDay, [
                if (IntakeVerticalList.isShown(
                  sharePct: widget.breakfastSharePct,
                  intakes: widget.breakfastIntake,
                ))
                  (
                    type: IntakeTypeEntity.breakfast,
                    intakes: widget.breakfastIntake,
                    section: IntakeVerticalList(
                      forkTime: mealTime(
                        widget.selectedDay,
                        IntakeTypeEntity.breakfast,
                        widget.breakfastIntake,
                      ),
                      day: widget.selectedDay,
                      title: S.of(context).breakfastLabel,
                      listIcon: Icons.bakery_dining_outlined,
                      addMealType: AddMealType.breakfastType,
                      intakeList: _sortByMeal[IntakeTypeEntity.breakfast]!
                          .apply(widget.breakfastIntake),
                      onDeleteIntakeCallback: _deleteIntakeOnShownDay,
                      onItemLongPressedCallback: onIntakeItemLongPressed,
                      onItemTappedCallback: widget.onEditIntake,
                      // today's entries copy too
                      onCopyIntakeCallback: widget.onCopyIntake,
                      usesImperialUnits: widget.usesImperialUnits,
                      showMealMacros: widget.showMealMacros,
                      trackedDayEntity: trackedDay,
                      mealKcalTarget: widget.breakfastKcalTarget,
                      sortType: _sortByMeal[IntakeTypeEntity.breakfast],
                      onSortTypeChanged: (sort) =>
                          _setSortFor(IntakeTypeEntity.breakfast, sort),
                    ),
                  ),
                if (IntakeVerticalList.isShown(
                  sharePct: widget.lunchSharePct,
                  intakes: widget.lunchIntake,
                ))
                  (
                    type: IntakeTypeEntity.lunch,
                    intakes: widget.lunchIntake,
                    section: IntakeVerticalList(
                      forkTime: mealTime(
                        widget.selectedDay,
                        IntakeTypeEntity.lunch,
                        widget.lunchIntake,
                      ),
                      day: widget.selectedDay,
                      title: S.of(context).lunchLabel,
                      listIcon: Icons.lunch_dining_outlined,
                      addMealType: AddMealType.lunchType,
                      intakeList: _sortByMeal[IntakeTypeEntity.lunch]!.apply(
                        widget.lunchIntake,
                      ),
                      onDeleteIntakeCallback: _deleteIntakeOnShownDay,
                      onItemLongPressedCallback: onIntakeItemLongPressed,
                      onItemTappedCallback: widget.onEditIntake,
                      usesImperialUnits: widget.usesImperialUnits,
                      showMealMacros: widget.showMealMacros,
                      // today's entries copy too
                      onCopyIntakeCallback: widget.onCopyIntake,
                      trackedDayEntity: trackedDay,
                      mealKcalTarget: widget.lunchKcalTarget,
                      sortType: _sortByMeal[IntakeTypeEntity.lunch],
                      onSortTypeChanged: (sort) =>
                          _setSortFor(IntakeTypeEntity.lunch, sort),
                    ),
                  ),
                if (IntakeVerticalList.isShown(
                  sharePct: widget.dinnerSharePct,
                  intakes: widget.dinnerIntake,
                ))
                  (
                    type: IntakeTypeEntity.dinner,
                    intakes: widget.dinnerIntake,
                    section: IntakeVerticalList(
                      forkTime: mealTime(
                        widget.selectedDay,
                        IntakeTypeEntity.dinner,
                        widget.dinnerIntake,
                      ),
                      day: widget.selectedDay,
                      title: S.of(context).dinnerLabel,
                      listIcon: Icons.dinner_dining_outlined,
                      addMealType: AddMealType.dinnerType,
                      intakeList: _sortByMeal[IntakeTypeEntity.dinner]!.apply(
                        widget.dinnerIntake,
                      ),
                      onDeleteIntakeCallback: _deleteIntakeOnShownDay,
                      onItemLongPressedCallback: onIntakeItemLongPressed,
                      onItemTappedCallback: widget.onEditIntake,
                      // today's entries copy too
                      onCopyIntakeCallback: widget.onCopyIntake,
                      usesImperialUnits: widget.usesImperialUnits,
                      showMealMacros: widget.showMealMacros,
                      mealKcalTarget: widget.dinnerKcalTarget,
                      sortType: _sortByMeal[IntakeTypeEntity.dinner],
                      onSortTypeChanged: (sort) =>
                          _setSortFor(IntakeTypeEntity.dinner, sort),
                    ),
                  ),
                if (IntakeVerticalList.isShown(
                  sharePct: widget.snackSharePct,
                  intakes: widget.snackIntake,
                ))
                  (
                    type: IntakeTypeEntity.snack,
                    intakes: widget.snackIntake,
                    section: IntakeVerticalList(
                      forkTime: mealTime(
                        widget.selectedDay,
                        IntakeTypeEntity.snack,
                        widget.snackIntake,
                      ),
                      day: widget.selectedDay,
                      title: S.of(context).snackLabel,
                      listIcon: CustomIcons.food_apple_outline,
                      addMealType: AddMealType.snackType,
                      intakeList: _sortByMeal[IntakeTypeEntity.snack]!.apply(
                        widget.snackIntake,
                      ),
                      onDeleteIntakeCallback: _deleteIntakeOnShownDay,
                      onItemLongPressedCallback: onIntakeItemLongPressed,
                      onItemTappedCallback: widget.onEditIntake,
                      usesImperialUnits: widget.usesImperialUnits,
                      showMealMacros: widget.showMealMacros,
                      // today's entries copy too
                      onCopyIntakeCallback: widget.onCopyIntake,
                      trackedDayEntity: trackedDay,
                      mealKcalTarget: widget.snackKcalTarget,
                      sortType: _sortByMeal[IntakeTypeEntity.snack],
                      onSortTypeChanged: (sort) =>
                          _setSortFor(IntakeTypeEntity.snack, sort),
                    ),
                  ),
              ]),
            const SizedBox(height: Dimens.spacing16),
          ],
        ),
      ],
    );
  }

  // #182: Compute from actual intakes instead of stale cached values
  List<IntakeEntity> get _allIntakes => [
    ...widget.breakfastIntake,
    ...widget.lunchIntake,
    ...widget.dinnerIntake,
    ...widget.snackIntake,
  ];

  // _getCaloriesTrackedDisplayString went with the rating

  bool get _showsCurrentDay =>
      DateUtils.isSameDay(widget.selectedDay, widget.currentDay);

  /// A section's "delete all" deletes on the day it was listed under, so
  /// the callback is bound to that day per build.
  Function(IntakeEntity, TrackedDayEntity?) get _deleteIntakeOnShownDay {
    final day = widget.selectedDay;
    return (intake, _) => widget.onDeleteIntake(intake, day);
  }

  void showCopyOrDeleteIntakeDialog(
    BuildContext context,
    IntakeEntity intakeEntity,
    DateTime day,
  ) async {
    final copyOrDelete = await showDialog<bool>(
      context: context,
      // the copy opens a picker
      builder: (context) => const CopyOrDeleteDialog(toPicker: true),
    );
    // the delete asks nothing more, so it goes ahead
    // even when the day moved on while the choice was open and this day's
    // view was rebuilt away (#1360); the Diary shows the Undo
    if (copyOrDelete == false) {
      widget.onDeleteIntake(intakeEntity, day);
      return;
    }
    if (context.mounted) {
      if (copyOrDelete != null && !copyOrDelete) {
        showDeleteIntakeDialog(context, intakeEntity, day);
      } else if (copyOrDelete != null && copyOrDelete) {
        showCopyDialog(context, intakeEntity);
      }
    }
  }

  void showCopyDialog(BuildContext context, IntakeEntity intakeEntity) async {
    // any day and meal, not only today's (fork/copy)
    await copyIntakesWithDialog(context, [intakeEntity], intakeEntity.type);
  }

  void showDeleteIntakeDialog(
    BuildContext context,
    IntakeEntity intakeEntity,
    DateTime day,
  ) async {
    // deleted at once, with Undo on the snackbar,
    // in place of upstream's confirmation dialog
    widget.onDeleteIntake(intakeEntity, day);
  }

  void onIntakeItemLongPressed(
    BuildContext context,
    IntakeEntity intakeEntity,
  ) async {
    final day = widget.selectedDay;
    // today's entries copy too
    showCopyOrDeleteIntakeDialog(context, intakeEntity, day);
  }

  void onActivityItemLongPressed(
    BuildContext context,
    UserActivityEntity activityEntity,
  ) async {
    final day = widget.selectedDay;
    // an activity copies to a picked day, from
    // any day; deleting today's still asks first
    final copyOrDelete = await showDialog<bool>(
      context: context,
      builder: (context) => const CopyOrDeleteDialog(toPicker: true),
    );
    if (!context.mounted) return;
    if (copyOrDelete == true) {
      await copyActivitiesWithDialog(context, [activityEntity]);
    } else if (copyOrDelete == false) {
      if (DateUtils.isSameDay(day, widget.currentDay)) {
        final shouldDelete = await showDialog<bool>(
          context: context,
          builder: (context) => const DeleteDialog(),
        );
        if (shouldDelete == null) return;
      }
      widget.onDeleteActivity(activityEntity, day);
    }
  }
}
