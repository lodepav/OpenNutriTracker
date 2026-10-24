import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:opennutritracker/core/data/data_source/config_data_source.dart';
import 'package:opennutritracker/core/data/data_source/custom_activity_template_dbo.dart';
import 'package:opennutritracker/core/data/data_source/user_activity_dbo.dart';
import 'package:opennutritracker/core/data/dbo/config_dbo.dart';
import 'package:opennutritracker/core/data/dbo/fasting_session_dbo.dart';
import 'package:opennutritracker/core/data/dbo/favourite_meal_dbo.dart';
import 'package:opennutritracker/core/data/dbo/intake_dbo.dart';
import 'package:opennutritracker/core/data/dbo/meal_dbo.dart';
import 'package:opennutritracker/core/data/dbo/profile_dbo.dart';
import 'package:opennutritracker/core/data/dbo/recipe_dbo.dart';
import 'package:opennutritracker/core/data/dbo/tracked_day_dbo.dart';
import 'package:opennutritracker/core/data/dbo/user_dbo.dart';
import 'package:opennutritracker/core/data/dbo/water_intake_dbo.dart';
import 'package:opennutritracker/core/data/dbo/weight_log_dbo.dart';
import 'package:opennutritracker/core/utils/hive_db_provider.dart';
import 'package:opennutritracker/features/settings/domain/export_import_failure.dart';
import 'package:opennutritracker/fork/backup/profiles_backup.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import '../../helpers/fake_hive_db_provider.dart';
import '../../helpers/hive_test_setup.dart';

class _Paths extends PathProviderPlatform with MockPlatformInterfaceMixin {
  final String root;

  _Paths(this.root);

  @override
  Future<String?> getApplicationDocumentsPath() async => root;
}

Future<Box<E>> _plain<E>(String baseName, String suffix) =>
    Hive.openBox<E>(HiveDBProvider.boxNameFor(baseName, suffix));

/// The active profile "me" (the first, unsuffixed boxes) and the registry.
Future<FakeHiveDBProvider> _device({String active = 'me'}) async {
  final db = FakeHiveDBProvider(
    activeProfileId: active,
    configBox: await _plain<ConfigDBO>(HiveDBProvider.configBoxName, ''),
    appConfigBox: await Hive.openBox<ConfigDBO>('app_config'),
    intakeBox: await _plain<IntakeDBO>(HiveDBProvider.intakeBoxName, ''),
    userActivityBox: await _plain<UserActivityDBO>(
      HiveDBProvider.userActivityBoxName,
      '',
    ),
    userBox: await _plain<UserDBO>(HiveDBProvider.userBoxName, ''),
    trackedDayBox: await _plain<TrackedDayDBO>(
      HiveDBProvider.trackedDayBoxName,
      '',
    ),
    customMealBox: await Hive.openBox<MealDBO>('custom_meals'),
    recipeBox: await Hive.openBox<RecipeDBO>('recipes'),
    customActivityTemplateBox: await Hive.openBox<CustomActivityTemplateDBO>(
      'templates',
    ),
    weightLogBox: await _plain<WeightLogDBO>(
      HiveDBProvider.weightLogBoxName,
      '',
    ),
    waterIntakeBox: await _plain<WaterIntakeDBO>(
      HiveDBProvider.waterIntakeBoxName,
      '',
    ),
    fastingBox: await _plain<FastingSessionDBO>(
      HiveDBProvider.fastingBoxName,
      '',
    ),
    favouriteMealBox: await _plain<FavouriteMealDBO>(
      HiveDBProvider.favouriteMealBoxName,
      '',
    ),
    profileBox: await Hive.openBox<ProfileDBO>('profiles'),
  );
  await ConfigDataSource(db).initializeConfig();
  return db;
}

ProfileDBO _kid() => ProfileDBO(
  id: 'kid',
  name: 'Kid',
  createdAt: DateTime(2026, 3, 1),
  boxSuffix: 'kid',
);

Future<List<WeightLogDBO>> _kidWeights() async {
  final box = await _plain<WeightLogDBO>(
    HiveDBProvider.weightLogBoxName,
    'kid',
  );
  final all = box.values.toList();
  await box.close();
  return all;
}

void main() {
  late Directory root;
  late PathProviderPlatform paths;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('fork_profiles_backup_');
    paths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(root.path);
    Hive.init(root.path);
    registerHiveAdaptersOnce();
  });

  tearDown(() async {
    await Hive.close();
    PathProviderPlatform.instance = paths;
    await root.delete(recursive: true);
  });

  Future<Archive> exportWithKid(FakeHiveDBProvider db) async {
    await db.profileBox.put(
      'me',
      ProfileDBO(
        id: 'me',
        name: 'Me',
        createdAt: DateTime(2026),
        boxSuffix: '',
      ),
    );
    await db.profileBox.put('kid', _kid());
    final weights = await _plain<WeightLogDBO>(
      HiveDBProvider.weightLogBoxName,
      'kid',
    );
    await weights.add(WeightLogDBO(date: DateTime(2026, 6, 1), weightKg: 31));
    await weights.close();

    final archive = Archive();
    await ProfilesBackup(db, openBox: _plain).addTo(archive);
    return archive;
  }

  test("another profile's data goes into its own folder", () async {
    final archive = await exportWithKid(await _device());

    final listed =
        jsonDecode(
              utf8.decode(
                archive.findFile('profiles.json')!.content as List<int>,
              ),
            )
            as Map<String, dynamic>;
    expect(listed['mainProfileId'], 'me');
    expect([
      for (final p in listed['profiles'] as List) p['id'],
    ], unorderedEquals(['me', 'kid']));
    final weights = archive.findFile('profiles/kid/weight_log.json')!;
    expect(utf8.decode(weights.content as List<int>), contains('31'));
    expect(archive.findFile('profiles/me/weight_log.json'), isNull);
    expect(archive.findFile('profiles/kid/custom_meals.json'), isNull);
    expect(Hive.isBoxOpen('WeightLogBoxkid'), isFalse);
  });

  test('a new phone gets the other profile back, once', () async {
    final db = await _device();
    final archive = await exportWithKid(db);
    await db.profileBox.delete('kid');
    await Hive.deleteBoxFromDisk(
      HiveDBProvider.boxNameFor(HiveDBProvider.weightLogBoxName, 'kid'),
    );

    final backup = ProfilesBackup(db, openBox: _plain);
    await backup.prepareRestore(archive)!();
    await backup.prepareRestore(archive)!();

    expect(db.profileBox.get('kid')?.name, 'Kid');
    expect([for (final w in await _kidWeights()) w.weightKg], [31]);
  });

  test("a restored profile never takes another profile's boxes", () async {
    final db = await _device();
    final exported = await exportWithKid(db);
    await db.profileBox.delete('kid');
    await Hive.deleteBoxFromDisk(
      HiveDBProvider.boxNameFor(HiveDBProvider.weightLogBoxName, 'kid'),
    );
    // The device's own profile now has the boxes "kid" names; the file
    // claims them in another case, which Hive folds together.
    await db.profileBox.put(
      'pal',
      ProfileDBO(
        id: 'pal',
        name: 'Pal',
        createdAt: DateTime(2026),
        boxSuffix: 'kid',
      ),
    );
    final listed =
        jsonDecode(
              utf8.decode(
                exported.findFile('profiles.json')!.content as List<int>,
              ),
            )
            as Map<String, dynamic>;
    for (final p in listed['profiles'] as List) {
      if (p['id'] == 'kid') p['boxSuffix'] = 'KID';
    }
    final archive = Archive();
    for (final f in exported.files) {
      if (f.name != 'profiles.json') archive.addFile(f);
    }
    final json = utf8.encode(jsonEncode(listed));
    archive.addFile(ArchiveFile('profiles.json', json.length, json));

    await ProfilesBackup(db, openBox: _plain).prepareRestore(archive)!();

    final suffix = db.profileBox.get('kid')!.boxSuffix;
    expect(suffix.toLowerCase(), isNot('kid'));
    expect(suffix, matches(RegExp(r'^[a-z0-9]+$')));
    expect(await _kidWeights(), isEmpty);
  });

  test('a backup made in another profile is refused there', () async {
    final archive = await exportWithKid(await _device());
    await Hive.close();
    final kidActive = await _device(active: 'kid');

    expect(
      () => ProfilesBackup(kidActive, openBox: _plain).prepareRestore(archive),
      throwsA(isA<ExportImportFailure>()),
    );
  });

  test('a zip without profiles.json restores nothing here', () async {
    expect(
      ProfilesBackup(
        await _device(),
        openBox: _plain,
      ).prepareRestore(Archive()),
      isNull,
    );
  });
}
