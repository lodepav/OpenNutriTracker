import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:opennutritracker/core/data/data_source/user_activity_dbo.dart';
import 'package:opennutritracker/core/data/dbo/physical_activity_dbo.dart';
import 'package:opennutritracker/core/data/dbo/profile_dbo.dart';
import 'package:opennutritracker/core/data/repository/config_repository.dart';
import 'package:opennutritracker/core/data/repository/tracked_day_repository.dart';
import 'package:opennutritracker/core/data/repository/user_activity_repository.dart';
import 'package:opennutritracker/core/data/repository/user_repository.dart';
import 'package:opennutritracker/core/domain/entity/app_theme_entity.dart';
import 'package:opennutritracker/core/domain/entity/physical_activity_entity.dart';
import 'package:opennutritracker/core/domain/entity/config_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_activity_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_gender_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_pal_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_weight_goal_entity.dart';
import 'package:opennutritracker/core/domain/usecase/add_tracked_day_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/add_user_activity_usercase.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_kcal_goal_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_macro_goal_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_tracked_day_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_user_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_weight_log_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/log_user_activity_usecase.dart';
import 'package:opennutritracker/core/utils/calc/day_boundary_calc.dart';
import 'package:opennutritracker/core/utils/hive_db_provider.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_service.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_store.dart';
import 'package:opennutritracker/fork/adaptive/macro_program.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_ui.dart';

import '../../helpers/fake_hive_db_provider.dart';
import '../../helpers/hive_test_setup.dart';

/// A Saturday.
final _saturday = DateTime(2026, 10, 24);

const _weekendUp = [-100.0, -100.0, -100.0, -100.0, -100.0, 250.0, 250.0];

class _Users extends Fake implements UserRepository {
  @override
  Future<UserEntity> getUserData() async => UserEntity(
    birthday: DateTime(1990, 1, 1),
    heightCM: 180,
    weightKG: 80,
    gender: UserGenderEntity.male,
    goal: UserWeightGoalEntity.maintainWeight,
    pal: UserPALEntity.active,
  );
}

class _Config extends Fake implements ConfigRepository {
  final int dayStartHours;

  _Config({this.dayStartHours = 0});

  @override
  Future<ConfigEntity> getConfig() async => ConfigEntity(
    false,
    false,
    false,
    AppThemeEntity.system,
    dayStartOffsetHours: dayStartHours,
  );
}

class _Activities extends Fake implements UserActivityRepository {
  @override
  Future<List<UserActivityEntity>> getAllUserActivityByDate(
    DateTime dateTime, {
    int dayStartOffsetHours = 0,
    int dayStartOffsetMinutes = 0,
  }) async => [];

  /// 300 kcal on Thursday and 100 on Friday, none on Saturday.
  @override
  Future<List<UserActivityDBO>> getAllUserActivityDBO() async => [
    _workoutDbo(DateTime(2026, 10, 22, 8), 300),
    _workoutDbo(DateTime(2026, 10, 23, 8), 100),
  ];
}

UserActivityDBO _workoutDbo(DateTime at, double kcal) => UserActivityDBO(
  'a-$at',
  30,
  kcal,
  at,
  PhysicalActivityDBO.fromPhysicalActivityEntity(PhysicalActivityEntity.custom),
);

/// The active profile's box as a plain box on disk.
class _Provider extends FakeHiveDBProvider {
  _Provider({required super.profileBox}) : super(activeProfileId: 'a');

  @override
  Future<Box<E>> openScopedBox<E>(String baseName, String boxSuffix) =>
      Hive.openBox<E>(HiveDBProvider.boxNameFor(baseName, boxSuffix));
}

class _WeightLog extends Fake implements GetWeightLogUsecase {}

class _TrackedDays extends Fake implements GetTrackedDayUsecase {}

/// Records the goal moves an activity makes.
class _Rows extends Fake implements TrackedDayRepository {
  final moves = <String>[];

  @override
  Future<void> increaseDayCalorieGoal(DateTime day, double amount) async =>
      moves.add('+$amount');

  @override
  Future<void> reduceDayCalorieGoal(DateTime day, double amount) async =>
      moves.add('-$amount');

  @override
  Future<void> increaseDayMacroGoal(
    DateTime day, {
    double? carbGoal,
    double? fatGoal,
    double? proteinGoal,
  }) async => moves.add('+macros');

  @override
  Future<void> reduceDayMacroGoal(
    DateTime day, {
    double? carbGoal,
    double? fatGoal,
    double? proteinGoal,
  }) async => moves.add('-macros');
}

/// Activities held in memory, each filed under its logical day.
class _DayActivities extends Fake implements UserActivityRepository {
  final all = <UserActivityEntity>[];

  _DayActivities(Map<DateTime, double> kcalAt) {
    for (final MapEntry(key: at, value: kcal) in kcalAt.entries) {
      all.add(_workout(at, kcal));
    }
  }

  @override
  Future<void> addUserActivity(UserActivityEntity activityEntity) async =>
      all.add(activityEntity);

  @override
  Future<List<UserActivityEntity>> getAllUserActivityByDate(
    DateTime dateTime, {
    int dayStartOffsetHours = 0,
    int dayStartOffsetMinutes = 0,
  }) async => [
    for (final a in all)
      if (DateUtils.isSameDay(
        a.date.subtract(
          Duration(hours: dayStartOffsetHours, minutes: dayStartOffsetMinutes),
        ),
        dateTime,
      ))
        a,
  ];

  @override
  Future<List<UserActivityDBO>> getAllUserActivityDBO() async => [
    for (final a in all) UserActivityDBO.fromUserActivityEntity(a),
  ];
}

UserActivityEntity _workout(DateTime at, double kcal) => UserActivityEntity(
  'w-$at-$kcal',
  30,
  kcal,
  at,
  PhysicalActivityEntity.custom,
);

/// One day's row: its calorie goal once made.
class _Row extends Fake implements TrackedDayRepository {
  double? goal;

  @override
  Future<bool> hasTrackedDay(DateTime day) async => goal != null;

  @override
  Future<bool> addNewTrackedDayIfAbsent(
    DateTime day,
    double totalKcalGoal,
    double totalCarbsGoal,
    double totalFatGoal,
    double totalProteinGoal,
  ) async {
    if (goal != null) return false;
    goal = totalKcalGoal;
    return true;
  }

  @override
  Future<void> increaseDayCalorieGoal(DateTime day, double amount) async =>
      goal = goal! + amount;

  @override
  Future<void> increaseDayMacroGoal(
    DateTime day, {
    double? carbGoal,
    double? fatGoal,
    double? proteinGoal,
  }) async {}
}

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('targets');
    Hive.init(dir.path);
    AdaptiveStore.settings.value = const AdaptiveSettings();
  });

  tearDown(() async {
    AdaptiveStore.settings.value = const AdaptiveSettings();
    DayBoundaryCalc.clock = DateTime.now;
    await Hive.deleteFromDisk();
    await dir.delete(recursive: true);
  });

  group('the kcal goal', () {
    test(
      'a fixed target replaces the formula and wins over adaptive',
      () async {
        AdaptiveStore.settings.value = const AdaptiveSettings(
          adaptiveTarget: true,
          fixedTarget: true,
          fixedKcal: 1800,
        );
        expect((await forkKcalGoal(_saturday)).target, 1800);
      },
    );

    test('grams set the fixed target to their energy', () async {
      AdaptiveStore.settings.value = const AdaptiveSettings(
        fixedTarget: true,
        fixedMacros: FixedMacros(proteinG: 150, carbsG: 200, fatG: 60),
      );
      expect((await forkKcalGoal(_saturday)).target, 4 * 150 + 4 * 200 + 540);
    });

    test("the weekday's shift lands on the fixed target", () async {
      AdaptiveStore.settings.value = const AdaptiveSettings(
        fixedTarget: true,
        fixedKcal: 2000,
        weekdayOffsets: _weekendUp,
      );
      expect((await forkKcalGoal(_saturday)).target, 2250);
      expect((await forkKcalGoal(DateTime(2026, 10, 26))).target, 1900);
    });

    test(
      'on the formula, the shift is added to what upstream computes',
      () async {
        DayBoundaryCalc.clock = () => _saturday.add(const Duration(hours: 12));
        final usecase = GetKcalGoalUsecase(_Users(), _Config(), _Activities());
        final formula = await usecase.getKcalGoal();

        AdaptiveStore.settings.value = const AdaptiveSettings(
          weekdayOffsets: _weekendUp,
        );
        expect(await usecase.getKcalGoal(), formula + 250);
      },
    );

    test("another profile's fixed target is read from its own box", () async {
      final other = AdaptiveStore.otherProfile(
        () => Hive.openBox<dynamic>('other'),
      );
      await other.save(
        const AdaptiveSettings(fixedTarget: true, fixedKcal: 1500),
      );

      expect(AdaptiveStore.settings.value.fixedTarget, isFalse);
      expect((await forkKcalGoal(_saturday, other)).target, 1500);
      expect((await forkKcalGoal(_saturday)).target, isNull);
    });
  });

  test('a macro program keeps a reconciled row\'s macros', () async {
    final other = AdaptiveStore.otherProfile(
      () => Hive.openBox<dynamic>('shifts'),
    );
    await other.save(
      const AdaptiveSettings(
        weekdayOffsets: _weekendUp,
        macroProgram: MacroProgram(),
      ),
    );
    final shifts = await forkReconcileTarget(other);
    expect(shifts.offsets, _weekendUp);
    expect(shifts.scaleMacros, isFalse);

    // Fixed grams win over the program, and they scale.
    await other.save(
      const AdaptiveSettings(
        fixedTarget: true,
        fixedMacros: FixedMacros(proteinG: 100, carbsG: 250, fatG: 100),
        macroProgram: MacroProgram(),
      ),
    );
    expect((await forkReconcileTarget(other)).scaleMacros, isTrue);
  });

  test('fixed grams scale with a shifted day', () async {
    AdaptiveStore.settings.value = const AdaptiveSettings(
      fixedTarget: true,
      fixedMacros: FixedMacros(proteinG: 100, carbsG: 250, fatG: 100),
    );
    final macros = GetMacroGoalUsecase(_Config());
    // 2,300 kcal of grams; a day at 2,530 is 10% more of each.
    expect(await macros.getProteinsGoal(2530), closeTo(110, 0.001));
    expect(await macros.getFatsGoal(2530), closeTo(110, 0.001));

    AdaptiveStore.settings.value = const AdaptiveSettings();
    expect(await macros.getProteinsGoal(2000), isNot(closeTo(110, 1)));
  });

  test('settings round-trip, and an older box reads with defaults', () {
    const settings = AdaptiveSettings(
      smoothedTrend: true,
      fixedTarget: true,
      fixedKcal: 1700,
      fixedMacros: FixedMacros(proteinG: 1, carbsG: 2, fatG: 3),
      weekdayOffsets: _weekendUp,
    );
    final back = AdaptiveSettings.fromJson(settings.toJson());
    expect(back.toJson(), settings.toJson());

    final old = AdaptiveSettings.fromJson({'adaptiveTarget': true});
    expect(old.adaptiveTarget, isTrue);
    expect(old.fixedTarget, isFalse);
    expect(old.weekdayOffsets, AdaptiveSettings.noOffsets);
    expect(
      () => AdaptiveSettings.fromJson({
        'weekdayOffsets': [1, 2],
      }),
      throwsFormatException,
    );
  });

  testWidgets('the settings dialog sets a fixed target and a weekend shift', (
    tester,
  ) async {
    final memory = _MemoryStore();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: AdaptiveSettingsTile(store: memory)),
      ),
    );
    await tester.tap(find.byType(ListTile));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Fixed'));
    await tester.pumpAndSettle();
    expect(memory.saved.fixedTarget, isTrue);
    expect(memory.saved.adaptiveTarget, isFalse);

    await tester.tap(find.byKey(const ValueKey('fixed-target')));
    await tester.pumpAndSettle();
    // A pasted "Infinity" would break every later backup's JSON.
    for (final bad in ['Infinity', 'NaN']) {
      await tester.enterText(find.byKey(const ValueKey('fixed-kcal')), bad);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(memory.saved.fixedKcal.isFinite, isTrue, reason: bad);
      expect(find.byKey(const ValueKey('fixed-kcal')), findsOneWidget);
    }
    await tester.enterText(find.byKey(const ValueKey('fixed-kcal')), '1800');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(memory.saved.fixedKcal, 1800);
    expect(find.text('Fixed target: 1800 kcal'), findsOneWidget);

    // Below the fold now that every mode shows the expenditure row.
    await tester.ensureVisible(find.byKey(const ValueKey('weekday-targets')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('weekday-targets')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('weekday-5')), '300');
    await tester.pumpAndSettle();
    expect(
      find.text('The week is +300 kcal on the usual total.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(memory.saved.weekdayOffsets, [0, 0, 0, 0, 0, 300, 0]);
    expect(find.text('Sat +300 kcal'), findsOneWidget);
  });

  testWidgets('the goal note shows today\'s goal with its weekday shift', (
    tester,
  ) async {
    locator.registerSingleton<GetConfigUsecase>(GetConfigUsecase(_Config()));
    addTearDown(() => locator.unregister<GetConfigUsecase>());
    DayBoundaryCalc.clock = () => _saturday.add(const Duration(hours: 9));
    AdaptiveStore.settings.value = const AdaptiveSettings(
      fixedTarget: true,
      fixedKcal: 2000,
      weekdayOffsets: _weekendUp,
    );
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: AdaptiveGoalNote())),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Your goal today is 2250 kcal (+250 kcal'),
      findsOneWidget,
    );
  });

  group('a day\'s stored goal', () {
    Future<List<String>> logRunAndDeleteIt() async {
      final rows = _Rows();
      final usecase = AddTrackedDayUsecase(rows);
      await usecase.increaseDayCalorieGoal(_saturday, 400);
      await usecase.increaseDayMacroGoals(_saturday, carbsAmount: 50);
      await usecase.reduceDayCalorieGoal(_saturday, 400);
      await usecase.reduceDayMacroGoals(_saturday, carbsAmount: 50);
      return rows.moves;
    }

    test('an activity moves it under the formula', () async {
      expect(await logRunAndDeleteIt(), [
        '+400.0',
        '+macros',
        '-400.0',
        '-macros',
      ]);
    });

    test('an activity leaves a fixed target\'s alone', () async {
      AdaptiveStore.settings.value = const AdaptiveSettings(
        fixedTarget: true,
        fixedKcal: 1800,
      );
      expect(await logRunAndDeleteIt(), isEmpty);
    });

    test('a row made for another day takes that day\'s weekday shift', () async {
      locator.registerSingleton<GetConfigUsecase>(GetConfigUsecase(_Config()));
      addTearDown(() => locator.unregister<GetConfigUsecase>());
      AdaptiveStore.settings.value = const AdaptiveSettings(
        weekdayOffsets: _weekendUp,
      );
      // Friday, writing Saturday's row: Friday's -100 out, Saturday's +250 in.
      DayBoundaryCalc.clock = () => DateTime(2026, 10, 23, 12);
      expect(await forkGoalOnDay(2000, _saturday), 2350);
      expect(await forkGoalOnDay(2000, DateTime(2026, 10, 22)), 2000);
    });

    test(
      'a moment before the day starts takes its logical day\'s shift',
      () async {
        locator.registerSingleton<GetConfigUsecase>(
          GetConfigUsecase(_Config(dayStartHours: 4)),
        );
        addTearDown(() => locator.unregister<GetConfigUsecase>());
        AdaptiveStore.settings.value = const AdaptiveSettings(
          weekdayOffsets: _weekendUp,
        );
        // 01:30 on Saturday is still Friday: Friday's row keeps Friday's goal.
        final early = DateTime(2026, 10, 24, 1, 30);
        DayBoundaryCalc.clock = () => early;
        expect(await forkGoalOnDay(2000, early), 2000);
      },
    );

    group('under the formula, a row made for another day', () {
      final thursday = DateTime(2026, 10, 22);
      final friday = DateTime(2026, 10, 23);
      late _DayActivities activities;

      /// [day]'s own goal, as upstream computes it on that day.
      Future<double> ownGoal(DateTime day, [int dayStartHours = 0]) async {
        final clock = DayBoundaryCalc.clock;
        DayBoundaryCalc.clock = () => day.add(const Duration(hours: 12));
        try {
          return await GetKcalGoalUsecase(
            _Users(),
            _Config(dayStartHours: dayStartHours),
            activities,
          ).getKcalGoal();
        } finally {
          DayBoundaryCalc.clock = clock;
        }
      }

      Future<double> todaysGoal([int dayStartHours = 0]) => GetKcalGoalUsecase(
        _Users(),
        _Config(dayStartHours: dayStartHours),
        activities,
      ).getKcalGoal();

      void register(Map<DateTime, double> kcalAt, [int dayStartHours = 0]) {
        activities = _DayActivities(kcalAt);
        locator.registerSingleton<UserActivityRepository>(activities);
        locator.registerSingleton<GetConfigUsecase>(
          GetConfigUsecase(_Config(dayStartHours: dayStartHours)),
        );
        addTearDown(locator.reset);
      }

      setUp(() => DayBoundaryCalc.clock = () => DateTime(2026, 10, 23, 12));

      test(
        'leaves today\'s activity on today, with no weekday shift',
        () async {
          register({DateTime(2026, 10, 23, 8): 1250});
          final today = await todaysGoal();
          expect(
            await forkGoalOnDay(today, thursday),
            closeTo(await ownGoal(thursday), 1e-6),
          );
          expect(
            await forkGoalOnDay(today, thursday),
            closeTo(today - 1250, 1e-6),
          );
          // Today's own row keeps today's goal.
          expect(await forkGoalOnDay(today, friday), today);
        },
      );

      test('carries the day\'s own activity, with its weekday shift', () async {
        register({DateTime(2026, 10, 22, 8): 300});
        AdaptiveStore.settings.value = const AdaptiveSettings(
          weekdayOffsets: _weekendUp,
        );
        // Friday writing Saturday's row: Saturday has its own 200.
        activities.all.add(_workout(DateTime(2026, 10, 24, 9), 200));
        expect(
          await forkGoalOnDay(await todaysGoal(), _saturday),
          closeTo(await ownGoal(_saturday), 1e-6),
        );
        expect(
          await forkGoalOnDay(await todaysGoal(), thursday),
          closeTo(await ownGoal(thursday), 1e-6),
        );
      });

      test('reads activities by the logical day', () async {
        // 01:30 on Saturday is still Friday, and so is the 01:00 workout.
        register({
          DateTime(2026, 10, 23, 8): 100,
          DateTime(2026, 10, 24, 1): 50,
          DateTime(2026, 10, 22, 8): 300,
        }, 4);
        DayBoundaryCalc.clock = () => DateTime(2026, 10, 24, 1, 30);
        final today = await todaysGoal(4);
        expect(
          await forkGoalOnDay(today, thursday),
          closeTo(today - 150 + 300, 1e-6),
        );
      });

      test('a goal said to hold no activity is left alone', () async {
        register({DateTime(2026, 10, 23, 8): 1250});
        expect(
          await forkGoalOnDay(2000, thursday, holdsTodayActivities: false),
          2000,
        );
      });

      test('a fixed target is left alone', () async {
        register({
          DateTime(2026, 10, 23, 8): 1250,
          DateTime(2026, 10, 22, 8): 300,
        });
        AdaptiveStore.settings.value = const AdaptiveSettings(
          fixedTarget: true,
          fixedKcal: 1800,
        );
        expect(await forkGoalOnDay(1800, thursday), 1800);
      });

      for (final (name, todayKcal) in [
        ('with an activity today', 400.0),
        ('with none today', 0.0),
      ]) {
        test('an activity logged into a past day with no row counts once, '
            '$name', () async {
          register({if (todayKcal > 0) DateTime(2026, 10, 23, 8): todayKcal});
          final row = _Row();
          final kcalGoal = GetKcalGoalUsecase(_Users(), _Config(), activities);
          await LogUserActivityUsecase(
            AddUserActivityUsecase(activities),
            AddTrackedDayUsecase(row),
            kcalGoal,
            GetMacroGoalUsecase(_Config()),
          ).logActivity(
            _workout(DateTime(2026, 10, 22, 8), 300),
            day: thursday,
          );
          // Thursday's own goal holds its 300 once.
          expect(row.goal, closeTo(await ownGoal(thursday), 1e-6));
          expect(
            row.goal,
            closeTo(
              await kcalGoal.getKcalGoal(totalKcalActivitiesParam: 300),
              1e-6,
            ),
          );
        });
      }

      test('in another profile, takes that profile\'s activities', () async {
        register({});
        final other = AdaptiveStore.otherProfile(
          () => Hive.openBox<dynamic>('other'),
        );
        await other.save(const AdaptiveSettings());
        final theirs = _DayActivities({DateTime(2026, 10, 23, 8): 500});
        Future<double> onThursday(double goal) => forkGoalOnDay(
          goal,
          thursday,
          store: other,
          config: () => _Config().getConfig(),
          activities: theirs,
        );
        expect(await onThursday(2500), 2000);
        // Under its fixed target, nothing moves.
        await other.save(
          const AdaptiveSettings(fixedTarget: true, fixedKcal: 1800),
        );
        expect(await onThursday(1800), 1800);
      });
    });

    group('in the daily activity mode', () {
      const daily = AdaptiveSettings(
        adaptiveTarget: true,
        activityMode: ActivityMode.daily,
        countSteps: false,
        workoutSharePct: 100,
      );
      final thursday = DateTime(2026, 10, 22);
      final friday = DateTime(2026, 10, 23);

      setUp(() async {
        registerHiveAdaptersOnce();
        locator.registerSingleton<HiveDBProvider>(
          _Provider(profileBox: await Hive.openBox<ProfileDBO>('profiles')),
        );
        locator.registerSingleton<GetConfigUsecase>(
          GetConfigUsecase(_Config()),
        );
        locator.registerSingleton<GetUserUsecase>(GetUserUsecase(_Users()));
        locator.registerSingleton<GetWeightLogUsecase>(_WeightLog());
        locator.registerSingleton<GetTrackedDayUsecase>(_TrackedDays());
        locator.registerSingleton<UserActivityRepository>(_Activities());
        addTearDown(locator.reset);
        // Friday noon, its goal 2000 with 100 of activity.
        DayBoundaryCalc.clock = () => DateTime(2026, 10, 23, 12);
      });

      Future<void> checkedIn() => AdaptiveStore().addCheckIn(
        CheckInRecord(
          date: thursday,
          expenditureKcal: 2500,
          proposedKcal: 2000,
          acceptedKcal: 2000,
        ),
      );

      test('a row for another day carries that day\'s activity', () async {
        await checkedIn();
        AdaptiveStore.settings.value = daily;
        expect((await forkKcalGoal(friday)).target, 2100);
        expect(await forkGoalOnDay(2100, friday), 2100);
        expect(await forkGoalOnDay(2100, thursday), 2300);
        expect(await forkGoalOnDay(2100, _saturday), 2000);
      });

      test('with the weekday\'s shift too', () async {
        await checkedIn();
        AdaptiveStore.settings.value = daily.copyWith(
          weekdayOffsets: _weekendUp,
        );
        // Friday's -100 and 100 of activity out, Saturday's +250 in.
        expect(await forkGoalOnDay(2000, _saturday), 2250);
      });

      test('a goal holding no activity is left alone', () async {
        await checkedIn();
        // A fixed target adds none.
        AdaptiveStore.settings.value = daily.copyWith(
          fixedTarget: true,
          fixedKcal: 1800,
        );
        expect(await forkGoalOnDay(1800, thursday), 1800);
        // Nor does another profile's.
        AdaptiveStore.settings.value = const AdaptiveSettings();
        final other = AdaptiveStore.otherProfile(
          () => Hive.openBox<dynamic>('other'),
        );
        await other.save(daily);
        expect(
          await forkGoalOnDay(
            2100,
            thursday,
            store: other,
            config: () => _Config().getConfig(),
          ),
          2100,
        );
      });

      test('an accepted target moves no logged activity', () async {
        await checkedIn();
        locator.unregister<UserActivityRepository>();
        locator.registerSingleton<UserActivityRepository>(
          _DayActivities({
            DateTime(2026, 10, 22, 8): 300,
            DateTime(2026, 10, 23, 8): 100,
          }),
        );
        AdaptiveStore.settings.value = daily;
        expect(await forkGoalOnDay(2100, thursday), 2300);
        AdaptiveStore.settings.value = daily.copyWith(
          activityMode: ActivityMode.weekly,
        );
        expect(await forkGoalOnDay(2000, thursday), 2000);
      });

      test('nor before the first check-in, under the formula', () async {
        AdaptiveStore.settings.value = daily;
        expect(await forkGoalOnDay(2847, thursday), 2847);
      });
    });

    test('a row made in another profile takes that profile\'s shift', () async {
      final other = AdaptiveStore.otherProfile(
        () => Hive.openBox<dynamic>('other'),
      );
      await other.save(const AdaptiveSettings(weekdayOffsets: _weekendUp));
      DayBoundaryCalc.clock = () => DateTime(2026, 10, 23, 12);

      // This profile shifts nothing; the other's Friday -100 out, Saturday
      // +250 in.
      expect(
        await forkGoalOnDay(
          2000,
          _saturday,
          store: other,
          config: () => _Config().getConfig(),
        ),
        2350,
      );
    });

    test('fixed grams that add up to nothing leave the typed target', () async {
      AdaptiveStore.settings.value = const AdaptiveSettings(
        fixedTarget: true,
        fixedKcal: 1800,
        fixedMacros: FixedMacros(proteinG: 0, carbsG: 0, fatG: 0),
      );
      expect((await forkKcalGoal(_saturday)).target, 1800);
    });
  });
}

class _MemoryStore extends Fake implements AdaptiveStore {
  AdaptiveSettings saved = const AdaptiveSettings();

  @override
  Future<void> save(AdaptiveSettings value) async {
    saved = value;
    AdaptiveStore.settings.value = value;
  }
}
