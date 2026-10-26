import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:opennutritracker/features/add_meal/data/data_sources/sp_food_data_source.dart';
import 'package:opennutritracker/core/domain/usecase/delete_weight_log_usecase.dart';
import 'package:opennutritracker/core/utils/ai_credential_storage.dart';
import 'package:opennutritracker/core/utils/hive_db_provider.dart';
import 'package:opennutritracker/core/utils/hive_storage_integrity_exception.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_store.dart';
import 'package:opennutritracker/fork/backup/auto_backup.dart';
import 'package:opennutritracker/fork/backup/backup_extras.dart';
import 'package:opennutritracker/fork/backup/profiles_backup.dart';
import 'package:opennutritracker/fork/backup/storage_rescue.dart';
import 'package:opennutritracker/fork/dev/fake_ai.dart';
import 'package:opennutritracker/fork/dish/starter_recipes.dart';
import 'package:opennutritracker/fork/display/display_prefs.dart';
import 'package:opennutritracker/fork/food/food_table_licenses.dart';
import 'package:opennutritracker/fork/food/local_food_data_source.dart';
import 'package:opennutritracker/fork/health/body_fat_import.dart';
import 'package:opennutritracker/fork/health/nutrition_export.dart';
import 'package:opennutritracker/fork/health/weight_import.dart';
import 'package:opennutritracker/fork/health/weight_import_ui.dart';
import 'package:opennutritracker/fork/leftovers/meal_photo_cache.dart';
import 'package:opennutritracker/fork/off/off_kinds.dart';
import 'package:opennutritracker/fork/phases/phases.dart';
import 'package:opennutritracker/fork/reminders/reminders.dart';

/// The fork's start-up, called once from upstream's `initLocator` and once
/// from `main`'s bootstrap, so each of those upstream files carries one
/// call rather than the fork's code.

/// Seams S1 and S113: the fork's services in the locator, over upstream's.
/// Called after upstream's registrations and before anything resolves them.
void registerFork() {
  // S1: search the bundled open tables, not the hosted backend (D11)
  _replace<SpFoodDataSource>(() => LocalFoodDataSource());
  registerFoodTableLicenses();
  if (forkFakeAi) {
    _replace<http.Client>(() => FakeAiClient(http.Client()));
  }
  // S113: deleting today's weigh-in sets the profile weight back
  _replace<DeleteWeightLogUsecase>(
    () => DeleteWeightLogUsecase(locator(), locator()),
  );
}

void _replace<T extends Object>(T Function() create) {
  locator.unregister<T>();
  locator.registerLazySingleton<T>(create);
}

/// Seam S21: the fork's own files in the JSON backup and its restore.
BackupExtras forkBackupExtras(HiveDBProvider hiveDBProvider) => BackupExtras(
  locator(),
  locator(),
  locator(),
  user: locator(),
  config: locator(),
  profiles: ProfilesBackup(hiveDBProvider),
);

/// Seam S6: the fork's stores and background jobs, after upstream's
/// bootstrap. Returns the integrity failure of a fork box, for upstream's
/// recovery screen, or null.
Future<HiveStorageIntegrityException?> forkStartup() async {
  // Saved once per install, off the start path.
  unawaited(StarterRecipeSeeder.fromLocator().run());
  unawaited(MealPhotoCache().prune());
  try {
    await AdaptiveStore.start();
    await DisplayPrefs.start();
    await OffKinds.start(); // S117
    await AutoBackup.start();
    await StorageRescue().finishPending(); // S112
    await WeightImport.start(refreshAfterWeightImport);
    BodyFatImport.start();
    NutritionExport.start();
    await Reminders.start();
    await PhaseRunner.start();
  } on HiveStorageIntegrityException catch (error, stackTrace) {
    // The fork's per-profile box opens here, after upstream's: a box that
    // fails its checksum gets upstream's recovery screen, not a hung splash.
    Logger('main').severe(
      'Fork database integrity failure (code=${error.code})',
      error,
      stackTrace,
    );
    return error;
  }
  if (forkFakeAi) await enableFakeAi(locator<AiCredentialStorage>());
  return null;
}
