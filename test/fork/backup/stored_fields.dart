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
    'phaseGoalNotice': StoredField.notBackedUp(
      "the owner's choice (2026-11-14): Home's note that a phase moved the "
      'goal; lost, the note is not shown again (phases.dart)',
    ),
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
    'weighInReminder': backedUp,
    'checkInReminder': backedUp,
    'sidePart': StoredField.notBackedUp(
      "the owner's choice (2026-11-14): which pair of sides the tile "
      'compares; lost, it shows arms until picked again (side_compare.dart)',
    ),
    'strengthAnswered': StoredField.notBackedUp(
      "the owner's choice (2026-11-14): the strength suggestion last applied "
      'or put off; lost, Home may offer it again (strength_card.dart)',
    ),
    'bodyFatImport': StoredField.notBackedUp(
      "the owner's choice (2026-11-14): per-device import state; lost, the "
      'import is off until turned on, and then reads the last 30 days again '
      '(body_fat_import.dart)',
    ),
    'nutritionExport': StoredField.notBackedUp(
      "the owner's choice (2026-11-14): per-device export state; lost, the "
      'export is off until turned on, and then writes the last 14 days again '
      '(nutrition_export.dart)',
    ),
    'movedDishIds': StoredField.notBackedUp(
      "per device: this profile's dish ids moved here (moved_dish_ids.dart)",
    ),
  },
  WeightImport.boxName: {
    'enabled': StoredField.notBackedUp(
      "the owner's choice (2026-11-14): the weight import's switch, per "
      'device with its permission; lost, it is off until turned on again',
    ),
    'lastImportAt': StoredField.notBackedUp(
      "the owner's choice (2026-11-14): per-device import state; lost, the "
      'next import reads the last 30 days again (weight_import.dart)',
    ),
    'filed': StoredField.notBackedUp(
      "the owner's choice (2026-11-14): what the import filed per day; "
      'lost, the rows in the log count as typed and are kept, and a day '
      'deleted since can be filled again',
    ),
  },
  // For every profile.
  forkFlagsBox: {
    'starterRecipesSeeded': StoredField.notBackedUp(
      'per install: the starter recipes are seeded once (starter_recipes.dart)',
    ),
    'movedDishIds': StoredField.notBackedUp(
      "per install: the search cache's dish ids moved (moved_dish_ids.dart)",
    ),
    'keepMealPhotos': backedUp,
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
  // Without the photo paths: the photos stay on the phone they were taken on.
  MealGroupStore.boxName: backedUp,
};
