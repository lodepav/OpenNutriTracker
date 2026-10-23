import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:opennutritracker/core/data/data_source/custom_meal_data_source.dart';
import 'package:opennutritracker/core/data/dbo/fasting_session_dbo.dart';
import 'package:opennutritracker/core/data/dbo/meal_dbo.dart';
import 'package:opennutritracker/core/data/dbo/water_intake_dbo.dart';
import 'package:opennutritracker/core/data/repository/water_intake_repository.dart';
import 'package:opennutritracker/features/fasting/data/data_source/fasting_data_source.dart';
import 'package:opennutritracker/features/settings/domain/export_import_failure.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_store.dart';
import 'package:opennutritracker/fork/backup/backup_extras.dart';

import '../../fixture/meal_entity_fixtures.dart';

void main() {
  late Directory dir;
  var boxes = 0;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('backup_extras');
    Hive.init(dir.path);
  });

  tearDown(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  ({
    BackupExtras extras,
    _Water water,
    _Fasting fasting,
    _Meals meals,
    AdaptiveStore adaptive,
  })
  device() {
    final name = 'adaptive${boxes++}';
    final adaptive = AdaptiveStore(() => Hive.openBox<dynamic>(name));
    final water = _Water();
    final fasting = _Fasting();
    final meals = _Meals();
    return (
      extras: BackupExtras(water, fasting, meals, adaptive: () => adaptive),
      water: water,
      fasting: fasting,
      meals: meals,
      adaptive: adaptive,
    );
  }

  final checkIn = CheckInRecord(
    date: DateTime(2026, 10, 19),
    expenditureKcal: 2600,
    proposedKcal: 2100,
    acceptedKcal: 2100,
  );

  test('what one device backs up, another restores, twice without '
      'duplicates', () async {
    final from = device();
    from.water.entries.add(
      WaterIntakeDBO(id: 'w1', dateTime: DateTime(2026, 10, 20), amountMl: 250),
    );
    from.fasting.sessions['f1'] = FastingSessionDBO(
      id: 'f1',
      startedAt: DateTime(2026, 10, 20, 20),
      targetDurationMinutes: 960,
    );
    from.meals.saved.add(MealDBO.fromMealEntity(MealEntityFixtures.mealOne));
    await from.adaptive.save(
      const AdaptiveSettings(smoothedTrend: true, adaptiveTarget: true),
    );
    await from.adaptive.addCheckIn(checkIn);

    final archive = Archive();
    await from.extras.addTo(archive);

    final to = device();
    await to.extras.prepareRestore(archive)();
    await to.extras.prepareRestore(archive)();

    expect(to.water.entries.map((e) => e.id), ['w1']);
    expect(to.fasting.sessions.keys, ['f1']);
    expect(to.meals.saved.map((m) => m.name), [
      MealEntityFixtures.mealOne.name,
    ]);
    final settings = await to.adaptive.read();
    expect(settings.adaptiveTarget, isTrue);
    expect(settings.smoothedTrend, isTrue);
    expect(settings.cycleWindow, isFalse);
    expect((await to.adaptive.history()).map((c) => c.acceptedKcal), [2100]);
  });

  test(
    'a zip without the fork files restores nothing and fails nothing',
    () async {
      final to = device();
      await to.extras.prepareRestore(Archive())();
      expect(to.water.entries, isEmpty);
      expect(await to.adaptive.history(), isEmpty);
    },
  );

  test('a malformed file fails before anything is written', () {
    final archive = Archive();
    final bytes = utf8.encode('{"not": "a list"}');
    archive.addFile(
      ArchiveFile(BackupExtras.waterFileName, bytes.length, bytes),
    );
    expect(
      () => device().extras.prepareRestore(archive),
      throwsA(isA<ExportImportFailure>()),
    );
  });
}

class _Water extends Fake implements WaterIntakeRepository {
  final entries = <WaterIntakeDBO>[];

  @override
  Future<List<WaterIntakeDBO>> getAllEntriesDBO() async => entries;

  @override
  Future<void> addAllEntries(List<WaterIntakeDBO> added) async {
    for (final entry in added) {
      entries
        ..removeWhere((e) => e.id == entry.id)
        ..add(entry);
    }
  }
}

class _Fasting extends Fake implements FastingDataSource {
  final sessions = <String, FastingSessionDBO>{};

  @override
  Future<List<FastingSessionDBO>> allSessions() async =>
      sessions.values.toList();

  @override
  Future<void> updateSession(FastingSessionDBO session) async =>
      sessions[session.id] = session;
}

class _Meals extends Fake implements CustomMealDataSource {
  final saved = <MealDBO>[];

  @override
  List<MealDBO> getAllCustomMeals() => saved;

  @override
  Future<void> saveCustomMeal(MealDBO meal) async {
    saved
      ..removeWhere((m) => (m.code ?? m.name) == (meal.code ?? meal.name))
      ..add(meal);
  }
}
