// A phone updated from any release keeps its data: the current code starts on
// what each release left on disk (test/fork/upgrade/fixtures/, written by
// fork/tools/upgrade_fixture.sh; each release adds its own).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:hive_ce/hive.dart';
import 'package:opennutritracker/core/data/dbo/favourite_meal_dbo.dart';
import 'package:opennutritracker/core/data/dbo/intake_dbo.dart';
import 'package:opennutritracker/core/data/dbo/intake_type_dbo.dart';
import 'package:opennutritracker/core/data/dbo/meal_dbo.dart';
import 'package:opennutritracker/core/data/dbo/meal_nutriments_dbo.dart';
import 'package:opennutritracker/core/data/repository/config_repository.dart';
import 'package:opennutritracker/core/data/repository/user_repository.dart';
import 'package:opennutritracker/core/utils/hive_db_provider.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_store.dart';
import 'package:opennutritracker/fork/amounts/own_portions.dart';
import 'package:opennutritracker/fork/backup/auto_backup.dart';
import 'package:opennutritracker/fork/bulk/photo_disclosure.dart';
import 'package:opennutritracker/fork/body/measurement_store.dart';
import 'package:opennutritracker/fork/display/display_prefs.dart';
import 'package:opennutritracker/fork/food/moved_dish_ids.dart';
import 'package:opennutritracker/fork/goal/goal_progress.dart';
import 'package:opennutritracker/fork/health/steps.dart';
import 'package:opennutritracker/fork/layout/home_layout.dart';
import 'package:opennutritracker/fork/layout/layout_store.dart';
import 'package:opennutritracker/fork/leftovers/meal_groups.dart';
import 'package:opennutritracker/fork/leftovers/meal_photo_cache.dart';
import 'package:opennutritracker/fork/off/off_kinds.dart';
import 'package:opennutritracker/fork/phases/phases.dart';
import 'package:opennutritracker/fork/photos/photo_store.dart';
import 'package:opennutritracker/fork/plan/plan_store.dart';
import 'package:opennutritracker/fork/reminders/reminders.dart';
import 'package:opennutritracker/fork/report/trends_layout.dart';
import 'package:opennutritracker/fork/update/update_notice.dart';
import 'package:opennutritracker/fork/health/weight_import.dart';
import 'package:opennutritracker/fork/startup.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../backup/stored_fields.dart';
import '../helpers/fork_state.dart';
import 'boot_app.dart';
import 'write_fork_state.dart' show notInFixture;

void main() {
  final fixtures =
      Directory('test/fork/upgrade/fixtures')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.tar.gz'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  test('there are fixtures', () => expect(fixtures, isNotEmpty));

  for (final fixture in fixtures) {
    final version = fixture.uri.pathSegments.last.replaceAll('.tar.gz', '');

    test('$version: its data survives the update', () async {
      final facts = await _unpackAndBoot(fixture, version);
      expect(await forkStartup(), isNull);

      final db = locator<HiveDBProvider>();
      expect(db.intakeBox.length, facts['intakes']);
      // Reads every entry, in every box the seeder filled: a field read at the
      // wrong index would throw here, or come back as another number.
      expect(
        db.intakeBox.values.fold<double>(0, (sum, i) => sum + i.amount),
        facts['intakeAmount'],
      );
      expect(db.trackedDayBox.values.toList(), hasLength(facts['trackedDays']));
      expect(db.weightLogBox.values.toList(), hasLength(facts['weights']));
      expect(
        db.userActivityBox.values.toList(),
        hasLength(facts['activities']),
      );
      expect(db.waterIntakeBox.values.toList(), hasLength(facts['water']));
      expect(
        db.recipeBox.values.toList(),
        hasLength(greaterThanOrEqualTo(facts['recipes'] as int)),
      );
      expect(db.profileBox.values.toList(), hasLength(facts['profiles']));

      final user = await locator<UserRepository>().getUserData();
      expect(user.weightKG, greaterThan(0));
      await locator<ConfigRepository>().getConfig();
      expect(AdaptiveStore.settings.value.adaptiveTarget, isTrue);
      expect(AdaptiveStore.settings.value.smoothedTrend, isTrue);
    });

    // From the release whose fixture holds it (write_fork_state.dart) on:
    // each key that release stored, read through today's store, against
    // the value it wrote.
    final forkState = _forkStateOf(fixture);
    if (forkState == null) continue;
    group('$version: fork state', () {
      setUpAll(() async {
        await _unpackAndBoot(fixture, version);
        expect(await forkStartup(), isNull);
      });
      final fields = forkState['fields'] as Map<String, dynamic>;
      for (final MapEntry(key: box, value: keys) in fields.entries) {
        for (final MapEntry(:key, value: written)
            in (keys as Map<String, dynamic>).entries) {
          test('$box.$key reads back', () async {
            final read = _fieldReaders[box]?[key];
            expect(read, isNotNull, reason: 'no reader: add one below');
            expect(jsonOf(await read!()), written);
          });
        }
      }
      final boxes = forkState['boxes'] as Map<String, dynamic>;
      for (final MapEntry(key: box, value: written) in boxes.entries) {
        test('$box reads back', () async {
          final read = _boxReaders[box];
          expect(read, isNotNull, reason: 'no reader: add one below');
          expect(jsonOf(await read!()), written);
        });
      }
    });
  }

  // No kept fixture holds fork state before the next release, so a stored
  // key added without a reader would only fail on the day of that release.
  test('every stored fork key has a reader', () {
    expect([
      for (final MapEntry(key: box, value: keys) in storedFields.entries)
        for (final key in keys.keys)
          if (!notInFixture.contains('$box.$key') &&
              _fieldReaders[box]?[key] == null)
            '$box.$key',
      for (final box in storedBoxes.keys)
        if (!notInFixture.contains(box) && _boxReaders[box] == null) box,
    ], isEmpty);
  });

  // v0.9.0 to v0.10.1 logged chicken cutlets on Caesar wrap's id; the update
  // gives them their own (lib/fork/food/moved_dish_ids.dart). The entries are
  // written as v0.10.1 wrote them, onto that release's data.
  test('0.10.1: a cutlets entry and favourite stay cutlets', () async {
    final fixture = fixtures.singleWhere(
      (f) => f.path.endsWith('/0.10.1.tar.gz'),
    );
    await _unpackAndBoot(fixture, '0.10.1');
    final db = locator<HiveDBProvider>();
    MealDBO dish(String name) => MealDBO(
      code: '30000024',
      name: name,
      brands: null,
      thumbnailImageUrl: null,
      mainImageUrl: null,
      url: null,
      mealQuantity: null,
      mealUnit: 'g',
      servingQuantity: 90,
      servingUnit: 'g',
      servingSize: '1 cutlet',
      nutriments: MealNutrimentsDBO(
        energyKcal100: 215,
        carbohydrates100: 9,
        fat100: 13,
        proteins100: 16,
        sugars100: 1,
        saturatedFat100: 3,
        fiber100: 0.5,
      ),
      source: MealSourceDBO.fdc,
      backendSource: 'fork_dishes',
      dataVersion: 1,
    );
    const cutlets =
        'Chicken cutlets, fried (cāļa kotletes, minced chicken patties, '
        'chicken kotlety)';
    const wrap = 'Caesar wrap, chicken (chicken caesar wrap)';
    for (final (id, name) in [('s215-cutlets', cutlets), ('s215-wrap', wrap)]) {
      await db.intakeBox.put(
        id,
        IntakeDBO(
          id: id,
          unit: 'g',
          amount: 180,
          type: IntakeTypeDBO.lunch,
          meal: dish(name),
          dateTime: DateTime(2026, 10, 20, 13),
        ),
      );
    }
    await db.favouriteMealBox.put(
      'fdc:30000024',
      FavouriteMealDBO(meal: dish(cutlets), addedAt: DateTime(2026, 10, 1)),
    );

    expect(await forkStartup(), isNull);

    expect(db.intakeBox.get('s215-cutlets')!.meal.code, '30000047');
    expect(db.intakeBox.get('s215-cutlets')!.amount, 180);
    expect(db.intakeBox.get('s215-wrap')!.meal.code, '30000024');
    expect(db.favouriteMealBox.containsKey('fdc:30000024'), isFalse);
    expect(db.favouriteMealBox.get('fdc:30000047')!.meal.name, cutlets);
  });
}

/// What [fixture]'s release recorded of the fork's state, or null for a
/// release before write_fork_state.dart.
Map<String, dynamic>? _forkStateOf(File fixture) {
  final json = Process.runSync('tar', [
    '-xzOf',
    fixture.path,
    '--wildcards',
    '*fixture.json',
  ]);
  if (json.exitCode != 0) throw StateError('${fixture.path}: ${json.stderr}');
  final facts = jsonDecode(json.stdout as String) as Map<String, dynamic>;
  return facts['forkState'] as Map<String, dynamic>?;
}

/// Today's settings, as the release stored them.
Future<Object?> _setting(String key) async =>
    (await AdaptiveStore().read()).toJson()[key];

/// A key with no reader that gives the whole stored value: as its store's
/// box gives it back.
Future<Object?> _stored(String box, String key) async =>
    (await openForkBox(box)).get(key);

Future<Object?> _layout(String key) async {
  final layout = await LayoutStore(key).layout();
  return {'order': layout.order, 'hidden': layout.hidden.toList()};
}

Future<Object?> _reminder(ReminderKind kind) async {
  final time = await Reminders().timeOf(kind);
  return time == null ? null : {'hour': time.hour, 'minute': time.minute};
}

WeightImport get _weightImport =>
    WeightImport(const HealthStoreWeights(), locator(), locator());

/// Each key a release stored, read the way today's code reads it, in the
/// shape it was stored in. A key renamed, or a value read in another shape,
/// fails here on every fixture that holds it.
final _fieldReaders = <String, Map<String, Future<Object?> Function()>>{
  AdaptiveStore.boxName: {
    for (final key in const [
      'smoothedTrend',
      'adaptiveTarget',
      'cycleWindow',
      'fixedTarget',
      'fixedKcal',
      'fixedMacros',
      'weekdayOffsets',
      'macroProgram',
      'responsiveness',
      'activityMode',
      'countSteps',
      'countWorkouts',
      'workoutSharePct',
      'checkInWeekday',
      'maxCheckInChangeKcal',
      'autoAcceptCheckIn',
      'flatEnergy',
    ])
      key: () => _setting(key),
    'checkIns': () async => [
      for (final c in await AdaptiveStore().history()) c.toJson(),
    ],
    'skippedDays': () async => [
      for (final d in (await AdaptiveStore().skippedDays()).toList()..sort())
        d.toIso8601String().substring(0, 10),
    ],
    'phasePlan': () async => (await PhaseStore().plan())?.toJson(),
    'goalHistory': () async => [
      for (final r in await PhaseStore().history()) r.toJson(),
    ],
    'goalsUpcoming': () async => [
      for (final p in await PhaseStore().upcoming()) p.toJson(),
    ],
    'milestoneStep': () => PhaseStore().milestoneStep(),
    'phaseApplied': () => PhaseStore().applied(),
    'phaseGoalNotice': () async =>
        switch (await PhaseStore().savedGoalNotice()) {
          final n? => {
            'title': n.title,
            'fromKcal': n.fromKcal,
            'toKcal': n.toKcal,
          },
          null => null,
        },
    'plannedFoods': () async => [
      for (final f in await PlanStore().all()) f.toJson(),
    ],
    'measurements': () async => [
      for (final m in await MeasurementStore().all()) m.toJson(),
    ],
    'progressPhotos': () async => [
      for (final p in await PhotoStore().all()) p.toJson(),
    ],
    'ownPortions': () => OwnPortions().all(),
    'amounts': () => _stored(AdaptiveStore.boxName, 'amounts'),
    'steps': () async => {
      for (final MapEntry(:key, :value)
          in (await StepCounts().cached()).entries)
        key.toIso8601String().substring(0, 10): value,
    },
    'workoutSteps': () => _stored(AdaptiveStore.boxName, 'workoutSteps'),
    'stepsOn': () => StepCounts().isOn(),
    'stepGoal': () => StepCounts().goal(),
    'macroOrder': () async => [
      for (final m in DisplayPrefs.macroOrder.value) m.name,
    ],
    'diaryByHour': () async => DisplayPrefs.diaryByHour.value,
    'homeShowsEaten': () async => DisplayPrefs.homeShowsEaten.value,
    'showWater': () async => DisplayPrefs.showWater.value,
    'showFasting': () async => DisplayPrefs.showFasting.value,
    'homeTiles': () => _layout(homeTilesKey),
    'homeSections': () => _layout(homeSectionsKey),
    'trendsLayout': () => _layout(TrendsLayoutStore.storeKey),
    'trendsTiles': () => _layout(TrendsTilesStore.storeKey),
    'goalStart': () async => (await GoalStartStore().read())?.toJson(),
    'goalStartNoTarget': () =>
        _stored(AdaptiveStore.boxName, GoalStartStore.noTargetKey),
    'weighInReminder': () => _reminder(ReminderKind.weighIn),
    'checkInReminder': () => _reminder(ReminderKind.checkIn),
    'sidePart': () => _stored(AdaptiveStore.boxName, 'sidePart'),
    'strengthAnswered': () =>
        _stored(AdaptiveStore.boxName, 'strengthAnswered'),
    'bodyFatImport': () => _stored(AdaptiveStore.boxName, 'bodyFatImport'),
    'nutritionExport': () => _stored(AdaptiveStore.boxName, 'nutritionExport'),
    'movedDishIds': () =>
        _stored(AdaptiveStore.boxName, MovedDishIds.profileFlag),
    'photoDisclosureSeen': () =>
        _stored(AdaptiveStore.boxName, PhotoDisclosureSeen.key),
  },
  WeightImport.boxName: {
    'enabled': () => _weightImport.isOn(),
    'lastImportAt': () => _weightImport.lastImportAt(),
    'filed': () => _stored(WeightImport.boxName, 'filed'),
  },
  forkFlagsBox: {
    'starterRecipesSeeded': () => _stored(forkFlagsBox, 'starterRecipesSeeded'),
    'movedDishIds': () => _stored(forkFlagsBox, MovedDishIds.installFlag),
    'keepMealPhotos': () => MealPhotoCache().enabled,
  },
  AutoBackup.boxName: {
    'folderUri': () async => AutoBackup.state.value.folderUri,
    'folderName': () async => AutoBackup.state.value.folderName,
    'lastSuccessAt': () async => AutoBackup.state.value.lastSuccessAt,
    'lastErrorAt': () async => AutoBackup.state.value.lastErrorAt,
    'lastError': () async => AutoBackup.state.value.lastError,
    'dismissedErrorAt': () async => AutoBackup.state.value.dismissedErrorAt,
    'restoredWhileOff': () async => AutoBackup.state.value.restoredWhileOff,
    'setAsideOn': () => _stored(AutoBackup.boxName, AutoBackup.setAsideOnKey),
  },
  UpdateNotice.boxName: {
    'seen': () => _stored(UpdateNotice.boxName, UpdateNotice.seenKey),
  },
};

/// The boxes keyed by data, whole.
final _boxReaders = <String, Future<Object?> Function()>{
  OffKinds.boxName: () async => OffKinds.kinds.value,
  MealGroupStore.boxName: () async => {
    for (final MapEntry(:key, :value) in (await MealGroupStore().all()).entries)
      key: value.toJson(),
  },
};

/// Unpacks [fixture] into a temp folder and starts the app's storage on it;
/// returns the facts the release wrote beside its data.
Future<Map<String, dynamic>> _unpackAndBoot(
  File fixture,
  String version,
) async {
  final dir = await Directory.systemTemp.createTemp('upgrade_$version');
  addTearDown(() async {
    await WeightImport.startupRun.catchError((_) {});
    await Hive.close();
    try {
      await Supabase.instance.dispose();
    } catch (_) {
      // The app didn't get as far as starting it: the test has failed already.
    }
    await GetIt.instance.reset();
    // Late writes can land while it goes; the system cleans its own temp.
    await dir.delete(recursive: true).catchError((_) => dir);
  });
  final untar = await Process.run('tar', [
    '-xzf',
    fixture.absolute.path,
    '-C',
    dir.path,
  ]);
  expect(untar.exitCode, 0, reason: '${untar.stderr}');
  final facts =
      jsonDecode(File('${dir.path}/fixture.json').readAsStringSync())
          as Map<String, dynamic>;
  await bootApp(dir);
  return facts;
}
