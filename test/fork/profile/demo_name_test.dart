import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/profile_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_profiles_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/update_profile_usecase.dart';
import 'package:opennutritracker/core/utils/demo/demo_seeder.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/fork/startup.dart';

import '../upgrade/boot_app.dart';

// S427: Try Demo on a profile added with a name keeps that name; only an
// unnamed profile becomes "Alex Demo", and leaving demo keeps a typed name.
Future<void> _rename(String name) async {
  final active = locator<GetProfilesUsecase>().getActiveProfile()!;
  await locator<UpdateProfileUsecase>().updateProfile(
    ProfileEntity(
      id: active.id,
      name: name,
      createdAt: active.createdAt,
      boxSuffix: active.boxSuffix,
      imagePath: active.imagePath,
    ),
  );
}

void main() {
  test('Try Demo keeps a typed name and names an unnamed profile', () async {
    await bootApp(Directory.systemTemp.createTempSync('demo_name'));
    await forkStartup();
    String name() => locator<GetProfilesUsecase>().getActiveProfile()!.name;

    await _rename('');
    await seedDemoData(DemoSeedOptions.onboarding);
    expect(name(), 'Alex Demo');

    await _rename('Test');
    await seedDemoData(DemoSeedOptions.onboarding);
    expect(name(), 'Test');

    await exitDemoMode();
    expect(name(), 'Test');

    await _rename('');
    await seedDemoData(DemoSeedOptions.onboarding);
    await exitDemoMode();
    expect(name(), '');
  }, timeout: const Timeout(Duration(minutes: 5)));
}
