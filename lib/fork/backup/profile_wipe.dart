import 'package:opennutritracker/core/domain/entity/profile_entity.dart';
import 'package:opennutritracker/core/utils/hive_db_provider.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_store.dart';
import 'package:opennutritracker/fork/bulk/photo_meal_memory_store.dart';
import 'package:opennutritracker/fork/health/weight_import.dart';
import 'package:opennutritracker/fork/photos/photo_store.dart';

/// The fork's own boxes of a profile: the adaptive settings, check-ins,
/// body measurements and progress photos' index, what Health Connect's weight import has read, and the
/// photo meals logged (`PhotoMealMemoryStore`).
const forkProfileBoxes = [
  AdaptiveStore.boxName,
  WeightImport.boxName,
  PhotoMealMemoryStore.boxName,
];

/// Empties them for the active profile when its data is deleted (seam
/// S102), as upstream empties its own: else a reset profile, or one set
/// up after the demo, starts with the old one's measurements and targets.
/// Its progress photos' images go first, while their index in the
/// adaptive box can still be read; one another profile also holds stays.
/// Upstream's tests of the delete run without the locator, and so without
/// these.
Future<void> clearForkProfileData() async {
  if (!locator.isRegistered<HiveDBProvider>()) return;
  final db = locator<HiveDBProvider>();
  final active = db.profileBox.get(db.activeProfileId);
  final suffix = active?.boxSuffix ?? '';
  // shortcut: with no registry row for the active profile its images stay
  // on the device (only the index is cleared); no such state is known.
  if (active != null) {
    await deleteProfilePhotos(db, ProfileEntity.fromProfileDBO(active), [
      for (final p in db.profileBox.values)
        if (p.id != active.id) ProfileEntity.fromProfileDBO(p),
    ]);
  }
  for (final name in forkProfileBoxes) {
    await (await db.openScopedBox<dynamic>(name, suffix)).clear();
  }
  // What the app holds of them in memory.
  await AdaptiveStore().load();
}
