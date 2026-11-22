import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:opennutritracker/core/data/data_source/user_data_source.dart';
import 'package:opennutritracker/core/data/dbo/water_intake_dbo.dart';
import 'package:opennutritracker/core/data/repository/water_intake_repository.dart';
import 'package:opennutritracker/core/utils/hive_db_provider.dart';
import 'package:opennutritracker/features/fasting/data/data_source/fasting_data_source.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_store.dart';
import 'package:opennutritracker/fork/backup/backup_extras.dart';
import 'package:opennutritracker/fork/backup/profile_wipe.dart';
import 'package:opennutritracker/fork/custom_food/serving_mode.dart';
import 'package:opennutritracker/fork/health/steps.dart';
import 'package:opennutritracker/fork/leftovers/meal_groups.dart';
import 'package:opennutritracker/fork/leftovers/meal_photo_cache.dart';
import 'package:opennutritracker/fork/phases/phases.dart';
import 'package:opennutritracker/fork/photos/photo_store.dart';
import 'package:opennutritracker/fork/plan/plan_store.dart';

import '../helpers/fork_state.dart';
import '../open/open_fixture.dart';
import 'stored_fields.dart';

/// Upstream's own boxes, which this list does not cover.
const _upstreamBoxes = {
  HiveDBProvider.configBoxName,
  HiveDBProvider.intakeBoxName,
  HiveDBProvider.userActivityBoxName,
  HiveDBProvider.userBoxName,
  HiveDBProvider.trackedDayBoxName,
  HiveDBProvider.customMealBoxName,
  HiveDBProvider.recipeBoxName,
  HiveDBProvider.cachedOffMealBoxName,
  HiveDBProvider.cachedOffMealTimestampsBoxName,
  HiveDBProvider.customActivityTemplateBoxName,
  HiveDBProvider.weightLogBoxName,
  HiveDBProvider.waterIntakeBoxName,
  HiveDBProvider.fastingBoxName,
  HiveDBProvider.favouriteMealBoxName,
  HiveDBProvider.profileBoxName,
  HiveDBProvider.appConfigBoxName,
};

/// The water log is upstream's and not in the fixture's provider.
class _NoWater extends Fake implements WaterIntakeRepository {
  @override
  Future<List<WaterIntakeDBO>> getAllEntriesDBO() async => const [];

  @override
  Future<void> addAllEntries(List<WaterIntakeDBO> entries) async {}
}

/// What a backed-up box holds after a restore: a meal group's photo path
/// is dropped, since the photo stays on the phone it was taken on.
Map<dynamic, Object?> _restored(String name, Map<dynamic, Object?> before) =>
    name != MealGroupStore.boxName
    ? before
    : {
        for (final MapEntry(:key, :value) in before.entries)
          key: {...value! as Map}..remove('photoPath'),
      };

/// Keys whose default is not null, false or empty.
// isDemoProfile: unset is the default; false is a real mark, and the only one a restore brings back.
const _ownDefaults = {'keepMealPhotos': true, 'isDemoProfile': null};

/// Null, false, empty, or [AdaptiveSettings]' own default.
bool _isDefault(String key, Object? value) {
  if (_ownDefaults.containsKey(key)) {
    return value == null || value == _ownDefaults[key];
  }
  final defaults = const AdaptiveSettings().toJson();
  if (defaults.containsKey(key)) return equals(defaults[key]).matches(value, {});
  return switch (value) {
    null || false => true,
    Iterable(:final isEmpty) || Map(:final isEmpty) => isEmpty,
    _ => false,
  };
}

void main() {
  late Directory dir;
  OpenFixture? fixture;

  /// The open fixture, then every listed key away from its default.
  Future<OpenFixture> fill() async {
    final f = fixture = await fillOpenFixture(dir, openToday());
    await fillForkState(
      today: f.today,
      meal: f.chicken,
      photos: Directory('${dir.path}/photos'),
    );
    return f;
  }

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('stored_fields');
  });

  tearDown(() async {
    await disposeOpenFixture(fixture);
    fixture = null;
    PhaseStore.changes.value = 0;
    CustomFoodModes.perServing.value = const {};
    PhaseStore.goalNotice.value = null;
    PlanStore.changes.value = 0;
    PhotoStore.changes.value = 0;
    StepCounts.changes.value = 0;
    await Hive.close();
    await dir.delete(recursive: true);
  });

  test('every key the fork stores is on the list', () async {
    await fill();
    final problems = <String>[];
    final listed = {
      for (final name in [...storedFields.keys, ...storedBoxes.keys])
        name.toLowerCase(),
    };
    for (final name in HiveDBProvider.perProfileBoxNames) {
      if (_upstreamBoxes.contains(name)) continue;
      if (!listed.contains(name.toLowerCase())) {
        problems.add('perProfileBoxNames has $name');
      }
    }
    for (final name in forkProfileBoxes) {
      if (!listed.contains(name.toLowerCase())) {
        problems.add('forkProfileBoxes has $name');
      }
    }
    final upstream = {for (final n in _upstreamBoxes) n.toLowerCase()};
    for (final file in dir.listSync().whereType<File>()) {
      final name = file.uri.pathSegments.last;
      if (!name.endsWith('.hive')) continue;
      final box = name.substring(0, name.length - '.hive'.length);
      if (!upstream.contains(box) && !listed.contains(box)) {
        problems.add('the box $box is on disk');
      }
    }
    for (final MapEntry(key: name, value: fields) in storedFields.entries) {
      for (final key in (await openForkBox(name)).keys) {
        if (!fields.containsKey(key)) problems.add('$name holds "$key"');
      }
    }
    expect(
      problems,
      isEmpty,
      reason:
          '${problems.join('\n')}\nAdd each to '
          'test/fork/backup/stored_fields.dart as backedUp, or as '
          'StoredField.notBackedUp with a one-line reason.',
    );
  });

  test('the list holds what the code backs up, and nothing the code no '
      'longer has', () {
    final adaptive = storedFields[AdaptiveStore.boxName]!;
    for (final key in [
      ...AdaptiveStore.keptKeys,
      ...const AdaptiveSettings().toJson().keys,
    ]) {
      expect(adaptive[key]?.isBackedUp, isTrue, reason: '$key is backed up');
    }
    final source = [
      for (final file in Directory('lib/fork').listSync(recursive: true))
        if (file is File && file.path.endsWith('.dart'))
          file.readAsStringSync(),
    ].join('\n');
    final names = [
      for (final MapEntry(key: box, value: fields) in storedFields.entries) ...[
        box,
        ...fields.keys,
      ],
      ...storedBoxes.keys,
    ];
    for (final name in names) {
      expect(
        source.contains("'$name'"),
        isTrue,
        reason: '"$name" is in no file under lib/fork: drop it from the list',
      );
    }
  });

  test('a backup and restore brings back every key the list calls backed '
      'up, and none of the others', () async {
    final f = await fill();
    final before = <String, Map<dynamic, Object?>>{
      for (final name in storedFields.keys)
        name: Map.of((await openForkBox(name)).toMap()),
    };
    final wholeBefore = {
      for (final name in storedBoxes.keys)
        name: Map.of((await openForkBox(name)).toMap()),
    };
    final unset = [
      for (final MapEntry(key: name, value: fields) in storedFields.entries)
        for (final MapEntry(key: key, value: field) in fields.entries)
          if (field.isBackedUp
              ? _isDefault(key, before[name]![key])
              : !before[name]!.containsKey(key))
            '$name.$key',
      for (final name in storedBoxes.keys)
        if (wholeBefore[name]!.isEmpty) name,
    ];
    expect(unset, isEmpty, reason: 'the fill must set these');

    final extras = BackupExtras(
      _NoWater(),
      FastingDataSource(f.db),
      f.customMeals,
      photos: () =>
          PhotoStore(null, () async => Directory('${dir.path}/photos')),
      mealPhotos: () => MealPhotoCache(
        dir: () async => Directory('${dir.path}/fork_meal_photos'),
      ),
      replanReminders: () async {},
      user: UserDataSource(f.db),
      config: f.configSource,
    );
    final archive = Archive();
    await extras.addTo(archive);
    for (final name in [...storedFields.keys, ...storedBoxes.keys]) {
      await (await openForkBox(name)).clear();
    }
    await extras.prepareTargetRestore(archive)();
    await extras.prepareRestore(archive)();

    final lost = <String>[];
    final leaked = <String>[];
    for (final MapEntry(key: name, value: fields) in storedFields.entries) {
      final box = await openForkBox(name);
      for (final MapEntry(key: key, value: field) in fields.entries) {
        if (field.isBackedUp) {
          if (!equals(before[name]![key]).matches(box.get(key), {})) {
            lost.add('$name.$key: ${before[name]![key]} -> ${box.get(key)}');
          }
        } else if (!_isDefault(key, box.get(key))) {
          leaked.add('$name.$key: ${box.get(key)}');
        }
      }
    }
    for (final MapEntry(key: name, value: field) in storedBoxes.entries) {
      final after = (await openForkBox(name)).toMap();
      if (!field.isBackedUp) {
        if (after.isNotEmpty) leaked.add(name);
      } else if (!equals(
        _restored(name, wholeBefore[name]!),
      ).matches(after, {})) {
        lost.add(name);
      }
    }
    expect(lost, isEmpty, reason: 'backedUp, but not restored');
    expect(leaked, isEmpty, reason: 'notBackedUp, but restored');
  });
}
