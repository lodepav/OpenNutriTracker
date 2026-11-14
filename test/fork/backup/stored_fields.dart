import 'package:opennutritracker/fork/adaptive/adaptive_store.dart';
import 'package:opennutritracker/fork/backup/auto_backup.dart';
import 'package:opennutritracker/fork/bulk/photo_meal_memory_store.dart';
import 'package:opennutritracker/fork/health/weight_import.dart';
import 'package:opennutritracker/fork/leftovers/meal_groups.dart';
import 'package:opennutritracker/fork/off/off_kinds.dart';
import 'package:opennutritracker/fork/update/update_notice.dart';

/// Whether a backup and restore brings a stored key back; when not, why.
class StoredField {
  final String? reason;

  const StoredField.notBackedUp(String this.reason);

  const StoredField._backedUp() : reason = null;

  bool get isBackedUp => reason == null;
}

const backedUp = StoredField._backedUp();

/// `StarterRecipeSeeder`'s and `MealPhotoCache`'s box; its name is private.
const forkFlagsBox = 'fork_flags';

/// Every key the fork stores, by box. A new key goes here as [backedUp] or
/// as [StoredField.notBackedUp] with its reason; stored_fields_test.dart
/// fails until it does, and proves each entry by a backup and restore.
const storedFields = <String, Map<String, StoredField>>{
  // Per profile.
  AdaptiveStore.boxName: {
    // AdaptiveSettings.toJson.
    'smoothedTrend': backedUp,
    'adaptiveTarget': backedUp,
    'cycleWindow': backedUp,
    'fixedTarget': backedUp,
    'fixedKcal': backedUp,
    'fixedMacros': backedUp,
    'weekdayOffsets': backedUp,
    'macroProgram': backedUp,
    'responsiveness': backedUp,
    'activityMode': backedUp,
    'countSteps': backedUp,
    'countWorkouts': backedUp,
    'workoutSharePct': backedUp,
    'checkInWeekday': backedUp,
    'maxCheckInChangeKcal': backedUp,
    'autoAcceptCheckIn': backedUp,
    'flatEnergy': backedUp,
    'checkIns': backedUp,
    'skippedDays': backedUp,
    // PhaseStore.
    'phasePlan': backedUp,
    'goalHistory': backedUp,
    'goalsUpcoming': backedUp,
    'milestoneStep': backedUp,
    'phaseApplied': backedUp,
    'phaseGoalNotice': StoredField.notBackedUp('not decided (2026-11-14)'),
    'plannedFoods': backedUp,
    'measurements': backedUp,
    'progressPhotos': backedUp,
    'ownPortions': backedUp,
    'amounts': StoredField.notBackedUp(
      'rebuilds itself with the next logs (remembered_amounts.dart)',
    ),
    // AdaptiveStore.keptKeys.
    'steps': backedUp,
    'workoutSteps': backedUp,
    'stepsOn': backedUp,
    'stepGoal': backedUp,
    'macroOrder': backedUp,
    'diaryByHour': backedUp,
    'homeShowsEaten': backedUp,
    'showWater': backedUp,
    'showFasting': backedUp,
    'homeTiles': backedUp,
    'homeSections': backedUp,
    'trendsLayout': backedUp,
    'trendsTiles': backedUp,
    'goalStart': backedUp,
    'goalStartNoTarget': backedUp,
    'weighInReminder': StoredField.notBackedUp('not decided (2026-11-14)'),
    'checkInReminder': StoredField.notBackedUp('not decided (2026-11-14)'),
    'sidePart': StoredField.notBackedUp('not decided (2026-11-14)'),
    'strengthAnswered': StoredField.notBackedUp('not decided (2026-11-14)'),
    'bodyFatImport': StoredField.notBackedUp('not decided (2026-11-14)'),
    'nutritionExport': StoredField.notBackedUp('not decided (2026-11-14)'),
    'movedDishIds': StoredField.notBackedUp(
      "per device: this profile's dish ids moved here (moved_dish_ids.dart)",
    ),
  },
  WeightImport.boxName: {
    'enabled': StoredField.notBackedUp('not decided (2026-11-14)'),
    'lastImportAt': StoredField.notBackedUp('not decided (2026-11-14)'),
    'filed': StoredField.notBackedUp('not decided (2026-11-14)'),
  },
  // For every profile.
  forkFlagsBox: {
    'starterRecipesSeeded': StoredField.notBackedUp(
      'per install: the starter recipes are seeded once (starter_recipes.dart)',
    ),
    'movedDishIds': StoredField.notBackedUp(
      "per install: the search cache's dish ids moved (moved_dish_ids.dart)",
    ),
    'keepMealPhotos': StoredField.notBackedUp(
      'per device: the meal photos it governs never leave the phone '
      '(meal_photo_cache.dart)',
    ),
  },
  AutoBackup.boxName: {
    'folderUri': StoredField.notBackedUp('per device: the backup folder'),
    'folderName': StoredField.notBackedUp('per device: the backup folder'),
    'lastSuccessAt': StoredField.notBackedUp(
      "per device: the automatic backup's last run",
    ),
    'lastErrorAt': StoredField.notBackedUp(
      "per device: the automatic backup's last run",
    ),
    'lastError': StoredField.notBackedUp(
      "per device: the automatic backup's last run",
    ),
    'setAsideOn': StoredField.notBackedUp(
      'per device: when the recovery screen set the files aside',
    ),
    'restorePending': StoredField.notBackedUp(
      'per device: a recovery restore still to run (storage_rescue.dart)',
    ),
  },
  UpdateNotice.boxName: {
    'seen': StoredField.notBackedUp('per device: the update last offered'),
  },
};

/// Boxes whose keys are data (by barcode, by time, by intake id), listed
/// whole.
const storedBoxes = <String, StoredField>{
  PhotoMealMemoryStore.boxName: StoredField.notBackedUp(
    'never in a backup or an export (photo_meal_memory_store.dart)',
  ),
  OffKinds.boxName: StoredField.notBackedUp(
    'learnt again from the next search or scan (off_kinds.dart)',
  ),
  MealGroupStore.boxName: StoredField.notBackedUp('not decided (2026-11-14)'),
};
