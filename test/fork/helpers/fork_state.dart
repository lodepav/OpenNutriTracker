// Every key test/fork/backup/stored_fields.dart lists, away from its
// default: what stored_fields_test.dart backs up and restores, and what a
// release's upgrade fixture holds for later code to read back
// (test/fork/upgrade/write_fork_state.dart). Synthetic data only.
import 'dart:io';

import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/utils/hive_db_provider.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_store.dart';
import 'package:opennutritracker/fork/adaptive/expenditure.dart';
import 'package:opennutritracker/fork/adaptive/macro_program.dart';
import 'package:opennutritracker/fork/amounts/own_portions.dart';
import 'package:opennutritracker/fork/amounts/remembered_amounts.dart';
import 'package:opennutritracker/fork/backup/auto_backup.dart';
import 'package:opennutritracker/fork/backup/storage_rescue.dart';
import 'package:opennutritracker/fork/body/measurement_store.dart';
import 'package:opennutritracker/fork/bulk/photo_meal_memory_store.dart';
import 'package:opennutritracker/fork/display/display_prefs.dart';
import 'package:opennutritracker/fork/goal/goal_progress.dart';
import 'package:opennutritracker/fork/health/weight_import.dart';
import 'package:opennutritracker/fork/leftovers/meal_groups.dart';
import 'package:opennutritracker/fork/off/off_kinds.dart';
import 'package:opennutritracker/fork/phases/phases.dart';
import 'package:opennutritracker/fork/photos/photo_store.dart';
import 'package:opennutritracker/fork/plan/plan_store.dart';
import 'package:opennutritracker/fork/reminders/reminders.dart';
import 'package:opennutritracker/fork/update/update_notice.dart';

import '../backup/stored_fields.dart';

/// Monday to Friday 100 kcal under, the weekend 250 over.
const _weekdayOffsets = [-100.0, -100.0, -100.0, -100.0, -100.0, 250.0, 250.0];

/// Every field away from its default, so a restore that drops one shows.
const forkStateSettings = AdaptiveSettings(
  smoothedTrend: true,
  adaptiveTarget: true,
  cycleWindow: true,
  fixedTarget: true,
  fixedKcal: 2300,
  fixedMacros: FixedMacros(proteinG: 150, carbsG: 250, fatG: 70),
  weekdayOffsets: _weekdayOffsets,
  macroProgram: MacroProgram(proteinGPerKg: 2.2),
  responsiveness: Responsiveness.responsive,
  activityMode: ActivityMode.daily,
  countSteps: false,
  countWorkouts: false,
  workoutSharePct: 80,
  checkInWeekday: 3,
  maxCheckInChangeKcal: 300,
  autoAcceptCheckIn: true,
  flatEnergy: true,
);

Future<Box<E>> _openAs<E>(String name) async =>
    Hive.isBoxOpen(name) ? Hive.box<E>(name) : await Hive.openBox<E>(name);

/// [name] as the app opens it: per profile and encrypted where the app's
/// is, and in its type, since Hive refuses a box open as another.
Future<Box<dynamic>> openForkBox(String name) {
  final db = locator<HiveDBProvider>();
  final suffix = db.profileBox.get(db.activeProfileId)?.boxSuffix ?? '';
  return switch (name) {
    forkFlagsBox => _openAs<bool>(name),
    MealGroupStore.boxName => _openAs<Map>(name),
    AdaptiveStore.boxName ||
    WeightImport.boxName ||
    PhotoMealMemoryStore.boxName => db.openScopedBox<dynamic>(name, suffix),
    OffKinds.boxName => db.openScopedBox<dynamic>(name, ''),
    _ => _openAs<dynamic>(name),
  };
}

/// [value] as JSON gives it back: dates as ISO text, map keys as text,
/// sets as lists; so a stored value and one read compare as data.
Object? jsonOf(Object? value) => switch (value) {
  DateTime() => value.toIso8601String(),
  Map() => {
    for (final MapEntry(:key, :value) in value.entries) '$key': jsonOf(value),
  },
  Iterable() => [for (final v in value) jsonOf(v)],
  _ => value,
};

/// The fixture's reminders never reach the OS.
class _NoOs implements ReminderScheduler {
  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<void> schedule(PlannedReminder reminder, {String? body}) async {}

  @override
  Future<void> cancel(ReminderKind kind) async {}
}

/// Sets every listed key of the active profile and the install away from
/// its default, today being [today]: [meal] is planned, portioned and
/// remembered, and a progress photo is written under [photos].
Future<void> fillForkState({
  required DateTime today,
  required MealEntity meal,
  required Directory photos,
}) async {
  DateTime day(int offset) =>
      DateTime(today.year, today.month, today.day + offset);
  DateTime at(int offset, int hour) =>
      DateTime(today.year, today.month, today.day + offset, hour);

  final adaptive = await AdaptiveStore.openActiveBox();
  final store = AdaptiveStore();
  await store.save(forkStateSettings);
  // Today's: after any check-in already here, as a merge sorts them.
  await store.addCheckIn(
    CheckInRecord(
      date: day(0),
      expenditureKcal: 2650,
      proposedKcal: 2150,
      acceptedKcal: 2200,
      activityKcal: 120,
      goalRateKgPerWeek: -0.5,
      targetWeightKg: 78,
      basis: 'adaptive',
    ),
  );
  await store.setSkipped(day(-15), true);
  // In 2100: the phase runner leaves a plan not yet begun alone, so the
  // start after an update reads it as it was written.
  final phases = PhaseStore();
  await phases.save(
    PhasePlan(
      start: DateTime(2100, 1, 4),
      startKg: 85.5,
      targetKg: 78,
      phases: const [
        DietPhase(kind: PhaseKind.cut, kgPerWeek: -0.5, weeks: 3),
        DietPhase(kind: PhaseKind.maintain, kgPerWeek: 0, weeks: 1),
        DietPhase(kind: PhaseKind.cut, kgPerWeek: -0.5, weeks: 12, untilKg: 78),
      ],
    ),
  );
  await phases.saveUpcoming([
    PhasePlan(
      start: DateTime(2100, 5, 3),
      startKg: 78,
      phases: const [
        DietPhase(kind: PhaseKind.maintain, kgPerWeek: 0, weeks: 8),
      ],
    ),
  ]);
  await phases.addToHistory([
    GoalRecord(
      kind: PhaseKind.bulk,
      start: day(-200),
      end: day(-60),
      startKg: 80,
      endKg: 86,
      targetKg: 86,
    ),
  ]);
  await phases.saveMilestoneStep(2);
  await phases.markApplied('cut-1');
  await phases.saveGoalNotice((
    title: 'Diet break',
    fromKcal: 2100,
    toKcal: 2500,
  ));
  await GoalStartStore().save(
    GoalStart(date: day(-28), kg: 85.5, targetKg: 78, paceKgPerWeek: -0.5),
  );
  await DisplayPrefs.setMacroOrder([Macro.protein, Macro.fat, Macro.carbs]);
  await DisplayPrefs.setDiaryByHour(true);
  await DisplayPrefs.setHomeShowsEaten(true);
  await DisplayPrefs.setShowWater(true);
  await DisplayPrefs.setShowFasting(true);
  await OwnPortions().add(meal, 'my bowl', 180);
  await RememberedAmounts().remember(meal, 'g', '150');
  await MeasurementStore().addDay(day(-2), {BodyMetric.waist: 90.5});
  await PlanStore().add(
    [(meal: meal, unit: 'g', amountText: '150', kcal: 180)],
    IntakeTypeEntity.dinner,
    day(2),
  );
  await PhotoStore(null, () async => photos).add(day(-3), [1, 2, 3]);
  final reminders = Reminders(
    scheduler: _NoOs(),
    clock: () => at(0, 14),
    checkInDueDay: () async => null,
    checkInResult: () async => null,
  );
  await reminders.set(ReminderKind.weighIn, (hour: 7, minute: 30));
  await reminders.set(ReminderKind.checkIn, (hour: 9, minute: 0));
  await adaptive.putAll({
    'steps': {day(-1).toIso8601String().substring(0, 10): 9000},
    'workoutSteps': {
      'open-workout-2': {'steps': 500, 'final': true},
    },
    'stepsOn': true,
    'stepGoal': 9000,
    'homeTiles': {
      'order': ['water', 'fasting'],
      'hidden': ['steps'],
    },
    'homeSections': {
      'order': ['plan', 'ring'],
      'hidden': <String>[],
    },
    'trendsLayout': {
      'order': ['weight', 'expenditure'],
      'hidden': ['photos'],
    },
    'trendsTiles': {
      'order': ['steps'],
      'hidden': ['kcal'],
    },
    'goalStartNoTarget': true,
    'sidePart': 'waist',
    'strengthAnswered': '{"key":"protein","at":"2026-11-01T09:00:00.000"}',
    'bodyFatImport': {'enabled': true, 'filed': <String, Object>{}},
    'nutritionExport': {'enabled': true, 'written': <String, Object>{}},
    'movedDishIds': true,
    'photoDisclosureSeen': 'openrouter|Google|false',
  });
  await (await openForkBox(WeightImport.boxName)).putAll({
    'enabled': true,
    'lastImportAt': at(0, 7),
    'filed': {
      '2026-11-01': {'kg': 84.0},
    },
  });
  await (await openForkBox(forkFlagsBox)).putAll(<String, bool>{
    'starterRecipesSeeded': true,
    'movedDishIds': true,
    'keepMealPhotos': false,
  });
  await (await openForkBox(AutoBackup.boxName)).putAll({
    'folderUri': 'content://folder',
    'folderName': 'Backups',
    'lastSuccessAt': at(0, 6),
    'lastErrorAt': at(-1, 6),
    'lastError': 'io',
    'dismissedErrorAt': at(-1, 6),
    'restoredWhileOff': true,
    AutoBackup.setAsideOnKey: at(-2, 6),
    StorageRescue.pendingKey: true,
  });
  await (await openForkBox(
    UpdateNotice.boxName,
  )).put(UpdateNotice.seenKey, '1.2.3');
  await (await openForkBox(PhotoMealMemoryStore.boxName)).put('1', '{}');
  await (await openForkBox(OffKinds.boxName)).put('4001234567890', '🥛');
  final group = {
    'intakeIds': ['i1', 'i2'],
    'loggedAt': at(0, 13).toIso8601String(),
    'photoPath': '${photos.path}/fork_meal_photos/1.webp',
  };
  await (await openForkBox(
    MealGroupStore.boxName,
  )).putAll(<String, Map>{'i1': group, 'i2': group});
}
