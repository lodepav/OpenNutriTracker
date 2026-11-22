import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/data/repository/recipe_repository.dart';
import 'package:opennutritracker/core/domain/entity/recipe_entity.dart';
import 'package:opennutritracker/core/domain/usecase/add_config_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/create_profile_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/delete_all_user_data_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/delete_profile_usecase.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_profiles_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/switch_profile_usecase.dart';
import 'package:opennutritracker/core/utils/demo/demo_seeder.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/fork/demo/demo_profile.dart';
import 'package:opennutritracker/fork/startup.dart';

import '../upgrade/boot_app.dart';

// G3-22: the demo is the demo profile's, not the app's. A second profile
// shows no banner, the demo profile keeps it, and leaving the demo with
// another profile around keeps the recipes they share.
void main() {
  test('the demo banner stays with the demo profile', () async {
    await bootApp(Directory.systemTemp.createTempSync('demo_profile'));
    await forkStartup();
    Future<bool> banner() async =>
        (await locator<GetConfigUsecase>().getConfig()).isDemoData;
    final switcher = locator<SwitchProfileUsecase>();

    await seedDemoData(DemoSeedOptions.onboarding);
    final demo = locator<GetProfilesUsecase>().getActiveProfile()!;
    expect(await banner(), isTrue);

    final other = await locator<CreateProfileUsecase>().createProfile(
      name: 'Sam',
    );
    await switcher.switchProfile(other);
    await syncDemoFlag();
    expect(await banner(), isFalse, reason: 'the new profile is not a demo');

    await switcher.switchProfile(demo);
    await syncDemoFlag();
    expect(await banner(), isTrue, reason: 'the demo profile still is');

    // A restore wrote real data here, whatever the backup said: leaving the
    // demo would wipe it, so the profile is no longer a demo (F1)
    await syncRestoredDemoMark();
    expect(await banner(), isFalse, reason: 'a restored profile is not a demo');
    await switcher.switchProfile(other);
    await syncDemoFlag();
    await switcher.switchProfile(demo);
    await syncDemoFlag();
    expect(await banner(), isFalse, reason: 'and it stays so after a switch');
    // The banner on screen was read before the restore: leaving the demo
    // from it must not wipe the restored profile
    final restoredName = locator<GetProfilesUsecase>().getActiveProfile()!.name;
    await exitDemoMode();
    expect(
      locator<GetProfilesUsecase>().getActiveProfile()!.name,
      restoredName,
      reason: 'a restored profile is not reset by leaving the demo',
    );
    await markDemoProfile(true);
    await syncDemoFlag();

    // Sam's own recipe, in the library every profile shares
    await locator<RecipeRepository>().saveRecipe(
      RecipeEntity(
        id: 'sams-soup',
        name: "Sam's soup",
        description: null,
        ingredients: const [],
        totalWeightG: 400,
        aggregatedNutrimentsPer100: MealNutrimentsEntity.empty(),
        createdAt: DateTime(2026, 11, 1),
        updatedAt: DateTime(2026, 11, 1),
        servingsCount: 2,
      ),
    );
    await exitDemoMode();
    expect(await banner(), isFalse);
    await switcher.switchProfile(other);
    await syncDemoFlag();
    await switcher.switchProfile(demo);
    await syncDemoFlag();
    expect(await banner(), isFalse, reason: 'left, the demo stays left');
    expect(
      locator<RecipeRepository>().getRecipeById('sams-soup'),
      isNotNull,
      reason: 'the library is shared with Sam, so it is not wiped',
    );

    // deleting the demo profile while on it leaves Sam without a banner
    await seedDemoData(DemoSeedOptions.onboarding);
    expect(await banner(), isTrue);
    await locator<DeleteProfileUsecase>().deleteProfile(demo);
    await syncDemoFlag(); // the coordinator's switch to the fallback
    expect(locator<GetProfilesUsecase>().activeProfileId, other.id);
    expect(await banner(), isFalse);

    // Settings' delete all ends the demo too: no banner comes back
    await seedDemoData(DemoSeedOptions.onboarding);
    await locator<DeleteAllUserDataUsecase>().deleteAll();
    await locator<AddConfigUsecase>().setConfigIsDemoData(false);
    final third = await locator<CreateProfileUsecase>().createProfile(
      name: 'Kim',
    );
    await switcher.switchProfile(third);
    await syncDemoFlag();
    await switcher.switchProfile(other);
    await syncDemoFlag();
    expect(await banner(), isFalse);
  }, timeout: const Timeout(Duration(minutes: 5)));
}
