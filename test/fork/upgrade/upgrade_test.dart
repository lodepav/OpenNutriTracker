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
import 'package:opennutritracker/fork/health/weight_import.dart';
import 'package:opennutritracker/fork/startup.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'boot_app.dart';

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
  }

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
