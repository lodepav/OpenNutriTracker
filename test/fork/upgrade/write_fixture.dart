// Writes what a release leaves on a phone: demo data, in that release's own format.
// fork/tools/upgrade_fixture.sh runs this at a release's commit, so it uses only what
// every release has. Synthetic only: the demo seeder's data, never the user's.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:opennutritracker/core/utils/demo/demo_seeder.dart';
import 'package:opennutritracker/core/utils/hive_db_provider.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_store.dart';
import 'package:opennutritracker/fork/startup.dart';

import 'boot_app.dart';

void main() {
  test('write the fixture', () async {
    final out = Directory(Platform.environment['FIXTURE_DIR']!);
    await bootApp(out);
    await forkStartup();
    await seedDemoData(
      const DemoSeedOptions(
        daysOfHistory: 21,
        missedDayProbability: 0.2,
        guaranteedStreakDays: 7,
        startWeightKg: 90,
      ),
    );
    await AdaptiveStore().save(
      const AdaptiveSettings(adaptiveTarget: true, smoothedTrend: true),
    );
    final db = locator<HiveDBProvider>();
    final facts = {
      'intakes': db.intakeBox.length,
      'intakeAmount': db.intakeBox.values.fold<double>(
        0,
        (sum, intake) => sum + intake.amount,
      ),
      'trackedDays': db.trackedDayBox.length,
      'weights': db.weightLogBox.length,
      'activities': db.userActivityBox.length,
      'water': db.waterIntakeBox.length,
      'recipes': db.recipeBox.length,
      'profiles': db.profileBox.length,
    };
    await Hive.close();
    File('${out.path}/fixture.json').writeAsStringSync(jsonEncode(facts));
  }, timeout: const Timeout(Duration(minutes: 5)));
}
