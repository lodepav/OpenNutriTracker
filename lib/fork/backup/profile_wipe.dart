import 'package:opennutritracker/core/utils/hive_db_provider.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_store.dart';
import 'package:opennutritracker/fork/health/weight_import.dart';

/// The fork's own boxes of a profile: the adaptive settings, check-ins and
/// body measurements, and what Health Connect's weight import has read.
const forkProfileBoxes = [AdaptiveStore.boxName, WeightImport.boxName];

/// Empties them for the active profile when its data is deleted (seam
/// S102), as upstream empties its own: else a reset profile, or one set
/// up after the demo, starts with the old one's measurements and targets.
/// Upstream's tests of the delete run without the locator, and so without
/// these.
Future<void> clearForkProfileData() async {
  if (!locator.isRegistered<HiveDBProvider>()) return;
  final db = locator<HiveDBProvider>();
  final suffix = db.profileBox.get(db.activeProfileId)?.boxSuffix ?? '';
  for (final name in forkProfileBoxes) {
    await (await db.openScopedBox<dynamic>(name, suffix)).clear();
  }
  // What the app holds of them in memory.
  await AdaptiveStore().load();
}
