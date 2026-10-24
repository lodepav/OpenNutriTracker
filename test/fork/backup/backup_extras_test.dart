import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:opennutritracker/core/data/data_source/config_data_source.dart';
import 'package:opennutritracker/core/data/data_source/custom_meal_data_source.dart';
import 'package:opennutritracker/core/data/data_source/user_data_source.dart';
import 'package:opennutritracker/core/data/dbo/app_theme_dbo.dart';
import 'package:opennutritracker/core/data/dbo/config_dbo.dart';
import 'package:opennutritracker/core/data/dbo/fasting_session_dbo.dart';
import 'package:opennutritracker/core/data/dbo/meal_dbo.dart';
import 'package:opennutritracker/core/data/dbo/user_dbo.dart';
import 'package:opennutritracker/core/data/dbo/user_gender_dbo.dart';
import 'package:opennutritracker/core/data/dbo/user_pal_dbo.dart';
import 'package:opennutritracker/core/data/dbo/user_weight_goal_dbo.dart';
import 'package:opennutritracker/core/data/dbo/water_intake_dbo.dart';
import 'package:opennutritracker/core/data/repository/water_intake_repository.dart';
import 'package:opennutritracker/features/fasting/data/data_source/fasting_data_source.dart';
import 'package:opennutritracker/features/settings/domain/export_import_failure.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_store.dart';
import 'package:opennutritracker/fork/body/measurement_store.dart';
import 'package:opennutritracker/fork/phases/phases.dart';
import 'package:opennutritracker/fork/photos/photo_store.dart';
import 'package:opennutritracker/fork/plan/plan_store.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
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
    PlanStore plans,
    MeasurementStore measurements,
    PhotoStore photos,
    PhaseStore phases,
    _User user,
    _Config config,
  })
  device() {
    final name = 'adaptive${boxes++}';
    final adaptive = AdaptiveStore(() => Hive.openBox<dynamic>(name));
    final plans = PlanStore(() => Hive.openBox<dynamic>(name));
    final measurements = MeasurementStore(() => Hive.openBox<dynamic>(name));
    final photos = PhotoStore(
      () => Hive.openBox<dynamic>(name),
      () async => Directory('${dir.path}/$name'),
    );
    final phases = PhaseStore(() => Hive.openBox<dynamic>(name));
    final water = _Water();
    final fasting = _Fasting();
    final meals = _Meals();
    final user = _User();
    final config = _Config();
    return (
      extras: BackupExtras(
        water,
        fasting,
        meals,
        adaptive: () => adaptive,
        plans: () => plans,
        measurements: () => measurements,
        photos: () => photos,
        phases: () => phases,
        user: user,
        config: config,
      ),
      water: water,
      fasting: fasting,
      meals: meals,
      adaptive: adaptive,
      plans: plans,
      measurements: measurements,
      photos: photos,
      phases: phases,
      user: user,
      config: config,
    );
  }

  final checkIn = CheckInRecord(
    date: DateTime(2026, 10, 19),
    expenditureKcal: 2600,
    proposedKcal: 2100,
    acceptedKcal: 2100,
  );

  test(
    'the target alone goes first, for the rows to be reconciled under',
    () async {
      final from = device();
      from.water.entries.add(
        WaterIntakeDBO(
          id: 'w1',
          dateTime: DateTime(2026, 10, 20),
          amountMl: 250,
        ),
      );
      await from.adaptive.save(const AdaptiveSettings(adaptiveTarget: true));
      await from.adaptive.addCheckIn(checkIn);
      final archive = Archive();
      await from.extras.addTo(archive);

      final to = device();
      await to.extras.prepareTargetRestore(archive)();

      expect((await to.adaptive.read()).adaptiveTarget, isTrue);
      expect((await to.adaptive.lastCheckIn())?.acceptedKcal, 2100);
      expect(to.water.entries, isEmpty);
    },
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
    await from.plans.add(
      [
        (
          meal: MealEntityFixtures.mealTwo,
          unit: 'g',
          amountText: '120.0',
          kcal: 210,
        ),
      ],
      IntakeTypeEntity.dinner,
      DateTime(2026, 10, 25),
    );
    await from.measurements.addDay(DateTime(2026, 10, 20), {
      BodyMetric.waist: 84,
    });
    final photo = await from.photos.add(DateTime(2026, 10, 21), [1, 2, 3]);
    final plan = PhasePlan(
      start: DateTime(2026, 10, 19),
      phases: const [DietPhase(kind: PhaseKind.cut, kgPerWeek: -0.5, weeks: 8)],
    );
    await from.phases.save(plan);

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
    final planned = await to.plans.forDay(DateTime(2026, 10, 25));
    expect(planned.map((f) => (f.meal.name, f.type, f.kcal)), [
      (MealEntityFixtures.mealTwo.name, IntakeTypeEntity.dinner, 210),
    ]);
    expect((await to.measurements.all()).map((m) => (m.metric, m.value)), [
      (BodyMetric.waist, 84),
    ]);
    expect((await to.phases.plan())?.toJson(), plan.toJson());
    final photos = await to.photos.all();
    expect(photos.map((p) => (p.id, p.date)), [
      (photo.id, DateTime(2026, 10, 21)),
    ]);
    expect(await (await to.photos.file(photos.single)).readAsBytes(), [
      1,
      2,
      3,
    ]);
  });

  test('a photo id that would leave its folder is refused', () async {
    final archive = Archive();
    final bytes = utf8.encode(
      jsonEncode([
        {'id': '../x', 'date': '2026-10-21T00:00:00.000'},
      ]),
    );
    archive.addFile(
      ArchiveFile(BackupExtras.photosFileName, bytes.length, bytes),
    );
    expect(
      () => device().extras.prepareRestore(archive),
      throwsA(isA<ExportImportFailure>()),
    );
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

  test('the profile and the app settings travel; consent, goals and the '
      'reminder switch stay as they are', () async {
    final from = device();
    from.user.saved = UserDBO(
      birthday: DateTime(1990, 5, 2),
      heightCM: 180,
      weightKG: 78.5,
      gender: UserGenderDBO.nonBinary,
      goal: UserWeightGoalDBO.loseWeight,
      pal: UserPALDBO.active,
      targetWeightKg: 72,
      caloriesTaperEnabled: true,
    );
    from.config.saved
      ..selectedAppTheme = AppThemeDBO.dark
      ..usesKilojoules = true
      ..selectedLocale = 'lv'
      ..notificationsEnabled = true
      ..dayStartOffsetHours = 4
      ..userKcalAdjustment = -300;
    final archive = Archive();
    await from.extras.addTo(archive);
    expect(BackupExtras.hasProfile(archive), isTrue);

    final to = device();
    to.config.saved
      ..hasAcceptedPolicy = true
      ..userKcalAdjustment = 100;
    await to.extras.prepareRestore(archive)();

    final user = to.user.saved!;
    expect(user.birthday, DateTime(1990, 5, 2));
    expect(user.weightKG, 78.5);
    expect(user.gender, UserGenderDBO.nonBinary);
    expect(user.pal, UserPALDBO.active);
    expect(user.caloriesProfile, isNull);
    expect(user.targetWeightKg, 72);
    expect(user.caloriesTaperEnabled, isTrue);
    final config = to.config.saved;
    expect(config.selectedAppTheme, AppThemeDBO.dark);
    expect(config.usesKilojoules, isTrue);
    expect(config.selectedLocale, 'lv');
    expect(config.hasAcceptedPolicy, isTrue);
    expect(config.notificationsEnabled, isNull);
    expect(config.dayStartOffsetHours, isNull);
    expect(config.userKcalAdjustment, 100);
  });

  test('without a profile there is no profile file', () async {
    final archive = Archive();
    await device().extras.addTo(archive);
    expect(BackupExtras.hasProfile(archive), isFalse);
  });

  test('an unknown gender or a setting of the wrong type fails before '
      'anything is written', () {
    for (final (name, json) in [
      (
        BackupExtras.profileFileName,
        '{"birthday": "1990-05-02", "heightCM": 180, "weightKG": 78, '
            '"gender": "robot", "goal": "loseWeight", "pal": "active"}',
      ),
      (BackupExtras.appSettingsFileName, '{"usesKilojoules": "yes"}'),
      (BackupExtras.profileFileName, '{"heightCM": 1e400}'),
    ]) {
      final archive = Archive();
      final bytes = utf8.encode(json);
      archive.addFile(ArchiveFile(name, bytes.length, bytes));
      expect(
        () => device().extras.prepareRestore(archive),
        throwsA(isA<ExportImportFailure>()),
        reason: json,
      );
    }
  });

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
  Future<void> saveCustomMeal(MealDBO meal, {MealDBO? previous}) async {
    saved
      ..removeWhere((m) => (m.code ?? m.name) == (meal.code ?? meal.name))
      ..add(meal);
  }
}

class _User extends Fake implements UserDataSource {
  UserDBO? saved;

  @override
  Future<bool> hasUserData() async => saved != null;

  @override
  Future<UserDBO> getUserData() async => saved!;

  @override
  Future<void> saveUserData(UserDBO user) async => saved = user;
}

class _Config extends Fake implements ConfigDataSource {
  var saved = ConfigDBO.empty();

  @override
  Future<ConfigDBO> getConfig() async => ConfigDBO.fromJson(saved.toJson());

  @override
  Future<void> addConfig(ConfigDBO config) async => saved = config;
}
