import 'package:flutter/foundation.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:opennutritracker/core/domain/usecase/add_config_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/core/utils/hive_db_provider.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_store.dart';

/// Which profile holds the demo (G3-22). Upstream's `isDemoData` is one flag
/// for the whole app, so onboarding a second profile turned the demo
/// profile's banner off. The mark lives in the profile's own fork box, and
/// each switch copies it into `isDemoData` for the profile switched to
/// ([syncDemoFlag], [adoptDemoMark]). A restore ends it
/// ([syncRestoredDemoMark]).
const demoProfileKey = 'isDemoProfile';
const _key = demoProfileKey;

/// Whether the legacy adoption below has run, for the whole install. Not in
/// a backup: it records this install's one upgrade from before the mark.
const _adoptionBox = 'fork_demo_mark';
const _adoptedKey = 'adopted';

/// Marks the active profile as holding the demo, or not. Marks are in use
/// from then on, so no legacy adoption is needed.
Future<void> markDemoProfile(bool demo) async {
  await (await AdaptiveStore.openActiveBox()).put(_key, demo);
  await (await Hive.openBox<dynamic>(_adoptionBox)).put(_adoptedKey, true);
}

/// For tests: as an install from before the mark.
@visibleForTesting
Future<void> forgetDemoAdoption() async =>
    (await Hive.openBox<dynamic>(_adoptionBox)).delete(_adoptedKey);

bool get _wired =>
    // widget tests of the profile switch register none of these
    locator.isRegistered<HiveDBProvider>() &&
    locator.isRegistered<GetConfigUsecase>() &&
    locator.isRegistered<AddConfigUsecase>();

/// Run by the banner: a demo seeded before the mark existed shows the
/// banner by `isDemoData` alone, so the profile showing it takes the mark.
/// Once per install, on the first banner after the upgrade, which is the
/// demo profile's at launch: a banner later left up on another profile, as
/// after deleting the demo while on it, must not mark that one.
Future<void> adoptDemoMark() async {
  if (!_wired || _adoptedThisRun) return;
  _adoptedThisRun = true;
  final adoption = await Hive.openBox<dynamic>(_adoptionBox);
  if (adoption.get(_adoptedKey) == true) return;
  await adoption.put(_adoptedKey, true);
  final open = await AdaptiveStore.openActiveBox();
  if (open.get(_key) == null) await open.put(_key, true);
}

var _adoptedThisRun = false;

/// Run after a switch: sets `isDemoData` from the active profile's mark,
/// so a profile without one shows no banner.
Future<void> syncDemoFlag() async {
  if (!_wired) return;
  final mark = (await AdaptiveStore.openActiveBox()).get(_key);
  await locator<AddConfigUsecase>().setConfigIsDemoData(mark == true);
}

/// Whether the active profile was marked as no longer a demo, as after a
/// restore: leaving the demo then must not wipe it.
Future<bool> activeProfileLeftDemo() async =>
    (await AdaptiveStore.openActiveBox()).get(_key) == false;

/// Run after a restore: it wrote real data into the active profile, and
/// leaving a demo wipes the profile, so the profile is no longer a demo,
/// whatever the backup was.
Future<void> syncRestoredDemoMark() async {
  if (!_wired) return;
  await (await AdaptiveStore.openActiveBox()).put(_key, false);
  await syncDemoFlag();
}
