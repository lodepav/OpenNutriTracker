import 'package:flutter/material.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_activity_entity.dart';
import 'package:opennutritracker/core/domain/usecase/add_intake_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/add_tracked_day_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_intake_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_kcal_goal_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_macro_goal_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_user_activity_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/log_user_activity_usecase.dart';
import 'package:opennutritracker/core/utils/calc/day_boundary_calc.dart';
import 'package:opennutritracker/core/utils/id_generator.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/core/utils/tracked_day_lock.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_service.dart';

/// [time] on the logical [day] that starts [offsetMinutes] after midnight:
/// a time before the start is the next calendar date's. Never a bare
/// midnight, which would read as a date-only entry of that date.
DateTime momentOn(DateTime day, TimeOfDay time, int offsetMinutes) {
  final minutes = time.hour * 60 + time.minute;
  return DateTime(
    day.year,
    day.month,
    day.day + (minutes < offsetMinutes ? 1 : 0),
    time.hour,
    time.minute,
    0,
    0,
    minutes == 0 ? 1 : 0,
  );
}

/// Copies diary entries to any day: one entry, a meal, or a whole day with
/// its activities. A copy gets a new id and keeps the logged food, amount and
/// unit; it lands at the same time of the target logical day, so a day start
/// other than midnight holds. Entries are written one after another: the
/// tracked-day totals are a read-modify-write, and upstream's own copy of a
/// meal section, which fires them all at once, under-counts the day.
///
/// Ported from theoleuthardt's `CopyEntriesUsecase` (GPL-3.0, their #127),
/// without the water copy, on upstream's goal lookups.
class CopyEntries {
  final AddIntakeUsecase _addIntake;
  final AddTrackedDayUsecase _trackedDay;
  final GetKcalGoalUsecase _kcalGoal;
  final GetMacroGoalUsecase _macroGoal;
  final GetConfigUsecase _config;
  final GetIntakeUsecase _intakes;
  final GetUserActivityUsecase _activities;
  final LogUserActivityUsecase _logActivity;
  final String Function() _newId;

  CopyEntries(
    this._addIntake,
    this._trackedDay,
    this._kcalGoal,
    this._macroGoal,
    this._config,
    this._intakes,
    this._activities,
    this._logActivity, {
    String Function()? newId,
  }) : _newId = newId ?? IdGenerator.getUniqueID;

  CopyEntries.fromLocator()
    : this(
        locator(),
        locator(),
        locator(),
        locator(),
        locator(),
        locator(),
        locator(),
        locator(),
      );

  /// Copies [intakes] to the logical day [day], into meal [type] (null keeps
  /// each entry's own). False when a profile switch stopped it.
  Future<bool> copyIntakes(
    List<IntakeEntity> intakes,
    DateTime day, {
    IntakeTypeEntity? type,
  }) async =>
      // Each entry and its row together, in the profile it began in (#1317).
      await withTrackedDayLockOnProfile(() async {
        final offset = (await _config.getConfig()).dayStartOffsetTotalMinutes;
        final target = _dateOf(day);
        for (final intake in intakes) {
          final copy = IntakeEntity(
            id: _newId(),
            unit: intake.unit,
            amount: intake.amount,
            type: type ?? intake.type,
            meal: intake.meal,
            dateTime: _moveTo(intake.dateTime, target, offset),
          );
          await _addIntake.addIntake(copy);
          await _addToTrackedDay(copy, target);
        }
        return true;
      }) ??
      false;

  /// Copies [intakes] to the moment [at], all of them, on the logical day
  /// [at] is listed under ("copy to now"), or to [time] on the logical day
  /// [at] when [time] is set. Into meal [type] (null keeps each entry's own).
  /// The logical day written to, or null when a profile switch stopped it.
  Future<DateTime?> copyIntakesAt(
    List<IntakeEntity> intakes,
    DateTime at, {
    TimeOfDay? time,
    IntakeTypeEntity? type,
  }) =>
      // Each entry and its row together, in the profile it began in (#1317).
      withTrackedDayLockOnProfile(() async {
        final offset = (await _config.getConfig()).dayStartOffsetTotalMinutes;
        if (time != null) at = momentOn(at, time, offset);
        final target = _dateOf(DayBoundaryCalc.dayLabelOf(at, offset));
        for (final intake in intakes) {
          final copy = IntakeEntity(
            id: _newId(),
            unit: intake.unit,
            amount: intake.amount,
            type: type ?? intake.type,
            meal: intake.meal,
            dateTime: at,
          );
          await _addIntake.addIntake(copy);
          await _addToTrackedDay(copy, target);
        }
        return target;
      });

  /// Puts deleted [intakes] back as they were, ids and times included, on
  /// the logical day [day] they were taken from (the delete's undo).
  Future<void> restoreIntakes(List<IntakeEntity> intakes, DateTime day) async {
    final target = _dateOf(day);
    for (final intake in intakes) {
      await _addIntake.addIntake(intake);
      await _addToTrackedDay(intake, target);
    }
  }

  /// Every intake of the logical day [day], earliest first.
  Future<List<IntakeEntity>> intakesOf(DateTime day) async {
    final config = await _config.getConfig();
    final source = _dateOf(day);
    return [
      for (final get in [
        _intakes.getBreakfastIntakeByDay,
        _intakes.getLunchIntakeByDay,
        _intakes.getDinnerIntakeByDay,
        _intakes.getSnackIntakeByDay,
      ])
        ...await get(
          source,
          dayStartOffsetHours: config.dayStartOffsetHours,
          dayStartOffsetMinutes: config.dayStartOffsetMinutes,
        ),
    ]..sort((a, b) => a.dateTime.compareTo(b.dateTime));
  }

  /// False when a profile switch stopped it.
  Future<bool> copyActivities(
    List<UserActivityEntity> activities,
    DateTime day,
  ) async =>
      await withTrackedDayLockOnProfile(() async {
        final offset = (await _config.getConfig()).dayStartOffsetTotalMinutes;
        final target = _dateOf(day);
        for (final activity in activities) {
          await _logActivity.logActivity(
            UserActivityEntity(
              _newId(),
              activity.duration,
              activity.burnedKcal,
              _moveTo(activity.date, target, offset),
              activity.physicalActivityEntity,
              userKcal: activity.userKcal,
            ),
            day: target,
          );
        }
        return true;
      }) ??
      false;

  /// Copies every intake of the logical day [from] to [to], each in its own
  /// meal, and the day's activities when [activities] is set. Read and
  /// written in one profile: false when a profile switch stopped it.
  Future<bool> copyDay(
    DateTime from,
    DateTime to, {
    bool activities = false,
  }) async =>
      await withTrackedDayLockOnProfile(() async {
        final config = await _config.getConfig();
        final hours = config.dayStartOffsetHours;
        final minutes = config.dayStartOffsetMinutes;
        final source = _dateOf(from);
        final intakes = await intakesOf(from);
        await copyIntakes(intakes, to);
        if (activities) {
          await copyActivities(
            await _activities.getUserActivityByDay(
              source,
              dayStartOffsetHours: hours,
              dayStartOffsetMinutes: minutes,
            ),
            to,
          );
        }
        return true;
      }) ??
      false;

  static DateTime _dateOf(DateTime day) =>
      DateTime(day.year, day.month, day.day);

  /// [moment] at the same clock time of the logical day labelled [target],
  /// on the next calendar date when it fell after midnight; by its fields,
  /// so a DST change between the days does not move it.
  static DateTime _moveTo(DateTime moment, DateTime target, int offset) {
    // A date-only entry (an import's) names its day: it moves as a label.
    if (DayBoundaryCalc.isDayLabel(moment)) return target;
    final local = moment.toLocal();
    final sourceDay = DayBoundaryCalc.logicalDayOfMinutes(local, offset);
    final afterMidnight = !DateUtils.isSameDay(local, sourceDay);
    return DateTime(
      target.year,
      target.month,
      target.day + (afterMidnight ? 1 : 0),
      local.hour,
      local.minute,
      local.second,
      local.millisecond,
      local.microsecond,
    );
  }

  /// As upstream's meal detail does after logging an entry.
  Future<void> _addToTrackedDay(IntakeEntity intake, DateTime day) async {
    if (!await _trackedDay.hasTrackedDay(day)) {
      final kcal = await forkGoalOnDay(await _kcalGoal.getKcalGoal(), day);
      await _trackedDay.addNewTrackedDay(
        day,
        kcal,
        await _macroGoal.getCarbsGoal(kcal),
        await _macroGoal.getFatsGoal(kcal),
        await _macroGoal.getProteinsGoal(kcal),
      );
    }
    await _trackedDay.addDayCaloriesTracked(day, intake.totalKcal);
    await _trackedDay.addDayMacrosTracked(
      day,
      carbsTracked: intake.totalCarbsGram,
      fatTracked: intake.totalFatsGram,
      proteinTracked: intake.totalProteinsGram,
    );
  }
}
