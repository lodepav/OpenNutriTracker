// A phone updated from any release keeps its data: the current code starts on
// what each release left on disk (test/fork/upgrade/fixtures/, written by
// fork/tools/upgrade_fixture.sh; each release adds its own).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:hive_ce/hive.dart';
import 'package:opennutritracker/core/data/repository/config_repository.dart';
import 'package:opennutritracker/core/data/repository/user_repository.dart';
import 'package:opennutritracker/core/utils/hive_db_provider.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_store.dart';
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
      final dir = await Directory.systemTemp.createTemp('upgrade_$version');
      addTearDown(() async {
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
}
