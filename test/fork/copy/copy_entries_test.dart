import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/app_theme_entity.dart';
import 'package:opennutritracker/core/domain/entity/config_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_activity_entity.dart';
import 'package:opennutritracker/core/domain/usecase/add_intake_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/add_tracked_day_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_intake_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_kcal_goal_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_macro_goal_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_user_activity_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/log_user_activity_usecase.dart';
import 'package:opennutritracker/core/utils/tracked_day_lock.dart';
import 'package:opennutritracker/fork/copy/copy_entries.dart';
import 'package:opennutritracker/fork/copy/select_entries_screen.dart';
import 'package:opennutritracker/generated/l10n.dart';

import '../../fixture/intake_entity_fixtures.dart';

void main() {
  late _Intakes intakes;
  late _TrackedDays days;
  late _Config config;
  var ids = 0;

  CopyEntries copier() => CopyEntries(
    intakes,
    days,
    _Kcal(),
    _Macros(),
    config,
    intakes,
    _Activities(),
    _Log(),
    newId: () => 'copy${ids++}',
  );

  IntakeEntity at(IntakeEntity intake, DateTime when) => IntakeEntity(
    id: intake.id,
    unit: intake.unit,
    amount: intake.amount,
    type: intake.type,
    meal: intake.meal,
    dateTime: when,
  );

  setUp(() {
    intakes = _Intakes();
    days = _TrackedDays();
    config = _Config(0);
    ids = 0;
  });

  test('a copy gets a new id, the target meal, the same time of the target '
      'day, and adds to that day\'s totals', () async {
    final oats = at(
      intakeOf('oats', 50, type: IntakeTypeEntity.breakfast),
      DateTime(2026, 10, 22, 8, 30),
    );
    await copier().copyIntakes(
      [oats, oats],
      DateTime(2026, 10, 23, 15),
      type: IntakeTypeEntity.snack,
    );

    expect(intakes.added.map((i) => i.id), ['copy0', 'copy1']);
    expect(intakes.added.first.type, IntakeTypeEntity.snack);
    expect(intakes.added.first.dateTime, DateTime(2026, 10, 23, 8, 30));
    expect(intakes.added.first.meal, oats.meal);
    expect(days.created, [DateTime(2026, 10, 23)]);
    expect(days.kcal[DateTime(2026, 10, 23)], 2 * oats.totalKcal);
  });

  test(
    'a restore writes the entries back as they were, on their day',
    () async {
      final oats = at(intakeOf('oats', 50), DateTime(2026, 10, 22, 8, 30));
      await copier().restoreIntakes([oats], DateTime(2026, 10, 22, 13));

      expect(intakes.added, [oats]);
      expect(days.kcal[DateTime(2026, 10, 22)], oats.totalKcal);
    },
  );

  test('with a 4 am day start, a 1 am entry stays after midnight of the '
      'target day', () async {
    config = _Config(4);
    final lateSnack = at(intakeOf('chips', 30), DateTime(2026, 10, 22, 1));
    // 1 am on the 22nd belongs to the logical day of the 21st.
    await copier().copyIntakes([lateSnack], DateTime(2026, 10, 23));
    expect(intakes.added.single.dateTime, DateTime(2026, 10, 24, 1));
    expect(intakes.added.single.type, lateSnack.type);
  });

  test('with a 4 am day start, a date-only entry (an import\'s) stays a '
      'date-only entry of the target day', () async {
    config = _Config(4);
    final imported = at(intakeOf('soup', 300), DateTime(2026, 10, 20));
    await copier().copyIntakes([imported], DateTime(2026, 10, 23));
    expect(intakes.added.single.dateTime, DateTime(2026, 10, 23));
    expect(days.created, [DateTime(2026, 10, 23)]);
  });

  test('copied to a picked time before the day starts, they go on the '
      'night of the day picked', () async {
    config = _Config(4);
    final oats = at(intakeOf('oats', 50), DateTime(2026, 10, 20, 8));
    final day = await copier().copyIntakesAt(
      [oats],
      DateTime(2026, 10, 23),
      time: const TimeOfDay(hour: 2, minute: 0),
    );

    expect(day, DateTime(2026, 10, 23));
    expect(intakes.added.single.dateTime, DateTime(2026, 10, 24, 2));
    expect(days.created, [DateTime(2026, 10, 23)]);
  });

  test('a profile switch stops a copy before it reads or writes', () async {
    final oats = at(intakeOf('oats', 50), DateTime(2026, 10, 22, 8));
    final switched = Completer<void>();
    final switching = withProfileSwitchLock(() => switched.future);
    final copies = [
      copier().copyIntakes([oats], DateTime(2026, 10, 23)),
      copier().copyDay(DateTime(2026, 10, 22), DateTime(2026, 10, 23)),
    ];
    switched.complete();
    await switching;

    expect(await Future.wait(copies), [false, false]);
    expect(intakes.added, isEmpty);
  });

  test(
    'copied to a moment, all go at it, on the logical day it falls in',
    () async {
      config = _Config(4);
      final oats = at(intakeOf('oats', 50), DateTime(2026, 10, 20, 8));
      final rice = at(intakeOf('rice', 150), DateTime(2026, 10, 20, 19));
      final now = DateTime(2026, 10, 23, 1, 15);

      await copier().copyIntakesAt(
        [oats, rice],
        now,
        type: IntakeTypeEntity.snack,
      );

      expect(intakes.added.map((i) => i.dateTime), [now, now]);
      expect(
        intakes.added.map((i) => i.type),
        everyElement(IntakeTypeEntity.snack),
      );
      // 1:15 am with a 4 am day start is still the 22nd.
      expect(days.created, [DateTime(2026, 10, 22)]);
      expect(
        days.kcal[DateTime(2026, 10, 22)],
        oats.totalKcal + rice.totalKcal,
      );
    },
  );

  test('a day copies all four meals, each in its own, oldest first', () async {
    intakes.byMeal = {
      IntakeTypeEntity.breakfast: [
        at(
          intakeOf('oats', 50, type: IntakeTypeEntity.breakfast),
          DateTime(2026, 10, 22, 8),
        ),
      ],
      IntakeTypeEntity.dinner: [
        at(
          intakeOf('rice', 150, type: IntakeTypeEntity.dinner),
          DateTime(2026, 10, 22, 19),
        ),
      ],
      IntakeTypeEntity.snack: [
        at(
          intakeOf('apple', 100, type: IntakeTypeEntity.snack),
          DateTime(2026, 10, 22, 11),
        ),
      ],
    };
    await copier().copyDay(DateTime(2026, 10, 22), DateTime(2026, 10, 23));
    expect(intakes.added.map((i) => (i.meal.name, i.type)), [
      ('oats', IntakeTypeEntity.breakfast),
      ('apple', IntakeTypeEntity.snack),
      ('rice', IntakeTypeEntity.dinner),
    ]);
  });

  testWidgets('entries picked by meal and by hour are copied to now', (
    tester,
  ) async {
    final oats = at(
      intakeOf('oats', 50, type: IntakeTypeEntity.breakfast),
      DateTime(2026, 10, 22, 8, 10),
    );
    final coffee = at(
      intakeOf('coffee', 200, type: IntakeTypeEntity.breakfast),
      DateTime(2026, 10, 22, 8, 40),
    );
    final apple = at(
      intakeOf('apple', 100, type: IntakeTypeEntity.snack),
      DateTime(2026, 10, 22, 11),
    );
    final rice = at(
      intakeOf('rice', 150, type: IntakeTypeEntity.dinner),
      DateTime(2026, 10, 22, 19),
    );
    intakes.byMeal = {
      IntakeTypeEntity.breakfast: [oats, coffee],
      IntakeTypeEntity.snack: [apple],
      IntakeTypeEntity.dinner: [rice],
    };
    final now = DateTime(2026, 10, 23, 12, 30);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [S.delegate],
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => SelectEntriesScreen(
                    day: DateTime(2026, 10, 22),
                    copier: copier(),
                    now: () => now,
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // The 8 o'clock hour, then dinner by its chip; apple stays out.
    await tester.tap(find.byKey(const Key('fork-select-hour-8')));
    await tester.tap(find.byKey(const Key('fork-select-meal-dinner')));
    await tester.pump();
    expect(find.text('3 selected'), findsOneWidget);
    // Unticking coffee leaves its hour half ticked.
    await tester.tap(find.byKey(Key('fork-select-${coffee.id}')));
    await tester.pump();
    final hour = tester.widget<CheckboxListTile>(
      find.byKey(const Key('fork-select-hour-8')),
    );
    expect(hour.value, isNull);

    await tester.tap(find.byKey(const Key('fork-copy-selected')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('fork-copy-now')));
    await tester.pumpAndSettle();

    expect(intakes.added.map((i) => (i.meal.name, i.dateTime, i.type)), [
      ('oats', now, IntakeTypeEntity.breakfast),
      ('rice', now, IntakeTypeEntity.dinner),
    ]);
    expect(find.text('open'), findsOneWidget);
    expect(find.text('Copied 2 entries to Fri, Oct 23'), findsOneWidget);
  });
}

class _Config extends Fake implements GetConfigUsecase {
  final int hours;

  _Config(this.hours);

  @override
  Future<ConfigEntity> getConfig() async => ConfigEntity(
    true,
    true,
    false,
    AppThemeEntity.system,
    dayStartOffsetHours: hours,
  );
}

class _Intakes extends Fake implements AddIntakeUsecase, GetIntakeUsecase {
  final added = <IntakeEntity>[];
  var byMeal = <IntakeTypeEntity, List<IntakeEntity>>{};

  @override
  Future<void> addIntake(IntakeEntity intake) async => added.add(intake);

  Future<List<IntakeEntity>> _of(IntakeTypeEntity meal) async =>
      byMeal[meal] ?? const [];

  @override
  Future<List<IntakeEntity>> getBreakfastIntakeByDay(
    DateTime day, {
    int dayStartOffsetHours = 0,
    int dayStartOffsetMinutes = 0,
  }) => _of(IntakeTypeEntity.breakfast);

  @override
  Future<List<IntakeEntity>> getLunchIntakeByDay(
    DateTime day, {
    int dayStartOffsetHours = 0,
    int dayStartOffsetMinutes = 0,
  }) => _of(IntakeTypeEntity.lunch);

  @override
  Future<List<IntakeEntity>> getDinnerIntakeByDay(
    DateTime day, {
    int dayStartOffsetHours = 0,
    int dayStartOffsetMinutes = 0,
  }) => _of(IntakeTypeEntity.dinner);

  @override
  Future<List<IntakeEntity>> getSnackIntakeByDay(
    DateTime day, {
    int dayStartOffsetHours = 0,
    int dayStartOffsetMinutes = 0,
  }) => _of(IntakeTypeEntity.snack);
}

class _TrackedDays extends Fake implements AddTrackedDayUsecase {
  final created = <DateTime>[];
  final kcal = <DateTime, double>{};

  @override
  Future<bool> hasTrackedDay(DateTime day) async => created.contains(day);

  @override
  Future<void> addNewTrackedDay(
    DateTime day,
    double totalKcalGoal,
    double totalCarbsGoal,
    double totalFatGoal,
    double totalProteinGoal,
  ) async => created.add(day);

  @override
  Future<void> addDayCaloriesTracked(DateTime day, double calories) async =>
      kcal[day] = (kcal[day] ?? 0) + calories;

  @override
  Future<void> addDayMacrosTracked(
    DateTime day, {
    double? carbsTracked,
    double? fatTracked,
    double? proteinTracked,
  }) async {}
}

class _Kcal extends Fake implements GetKcalGoalUsecase {
  @override
  Future<double> getKcalGoal({
    userEntity,
    double? totalKcalActivitiesParam,
    double? kcalUserAdjustment,
  }) async => 2000;
}

class _Macros extends Fake implements GetMacroGoalUsecase {
  @override
  Future<double> getCarbsGoal(double kcal) async => 250;

  @override
  Future<double> getFatsGoal(double kcal) async => 70;

  @override
  Future<double> getProteinsGoal(double kcal) async => 100;
}

class _Activities extends Fake implements GetUserActivityUsecase {}

class _Log extends Fake implements LogUserActivityUsecase {
  final logged = <UserActivityEntity>[];

  @override
  Future<void> logActivity(
    UserActivityEntity activity, {
    required DateTime day,
  }) async => logged.add(activity);
}
