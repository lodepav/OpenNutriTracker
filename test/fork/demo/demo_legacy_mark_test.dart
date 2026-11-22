import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/usecase/create_profile_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_profiles_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/switch_profile_usecase.dart';
import 'package:opennutritracker/core/utils/demo/demo_seeder.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_store.dart';
import 'package:opennutritracker/fork/demo/demo_profile.dart';
import 'package:opennutritracker/fork/startup.dart';

import '../upgrade/boot_app.dart';

// G3-22: a demo seeded by an older release has the flag and no mark; it
// keeps its banner when the user adds a profile and comes back.
void main() {
  test('a demo seeded before the mark keeps its banner across a switch', () async {
    await bootApp(Directory.systemTemp.createTempSync('demo_legacy'));
    await forkStartup();
    Future<bool> banner() async =>
        (await locator<GetConfigUsecase>().getConfig()).isDemoData;
    final switcher = locator<SwitchProfileUsecase>();
    await seedDemoData(DemoSeedOptions.onboarding);
    final demo = locator<GetProfilesUsecase>().getActiveProfile()!;
    // as an older release left it: the flag, no mark, never adopted
    await (await AdaptiveStore.openActiveBox()).delete('isDemoProfile');
    await forgetDemoAdoption();
    // the banner on Home takes the mark for the profile showing it
    await adoptDemoMark();

    final other = await locator<CreateProfileUsecase>().createProfile(
      name: 'Sam',
    );
    await switcher.switchProfile(other);
    // a banner still up on Sam before the sync, as after deleting the
    // demo while on it: the one adoption is spent, Sam is not marked
    await adoptDemoMark();
    await syncDemoFlag();
    expect(await banner(), isFalse);
    await switcher.switchProfile(demo);
    await syncDemoFlag();
    expect(await banner(), isTrue);
  }, timeout: const Timeout(Duration(minutes: 5)));
}
