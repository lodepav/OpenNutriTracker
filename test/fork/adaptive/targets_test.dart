import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:opennutritracker/core/data/repository/config_repository.dart';
import 'package:opennutritracker/core/data/repository/tracked_day_repository.dart';
import 'package:opennutritracker/core/data/repository/user_activity_repository.dart';
import 'package:opennutritracker/core/data/repository/user_repository.dart';
import 'package:opennutritracker/core/domain/entity/app_theme_entity.dart';
import 'package:opennutritracker/core/domain/entity/config_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_activity_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_gender_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_pal_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_weight_goal_entity.dart';
import 'package:opennutritracker/core/domain/usecase/add_tracked_day_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_kcal_goal_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_macro_goal_usecase.dart';
import 'package:opennutritracker/core/utils/calc/day_boundary_calc.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_service.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_store.dart';
import 'package:opennutritracker/fork/adaptive/macro_program.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_ui.dart';

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
}

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
