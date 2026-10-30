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
import 'package:opennutritracker/core/domain/usecase/delete_intake_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_intake_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_kcal_goal_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_macro_goal_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_user_activity_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/log_user_activity_usecase.dart';
import 'package:opennutritracker/core/utils/tracked_day_lock.dart';
import 'package:opennutritracker/fork/copy/copy_entries.dart';
import 'package:opennutritracker/fork/copy/copy_ui.dart';
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
    delete: intakes,
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
    final placed = await copier().placeIntakes([
      oats,
    ], CopyAt(_oct23, time: const TimeOfDay(hour: 2, minute: 0)));

    expect(placed?.day, DateTime(2026, 10, 23));
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

      await copier().placeIntakes(
        [oats, rice],
        CopyAt(now),
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

  test('a move keeps the id, takes the entry off its day and puts it on '
      'the new one, and its undo puts it back', () async {
    final oats = at(
      intakeOf('oats', 50, type: IntakeTypeEntity.breakfast),
      DateTime(2026, 10, 22, 8, 30),
    );
    intakes.stored[oats.id] = oats;
    final from = DateTime(2026, 10, 22);
    final placed = await copier().placeIntakes(
      [oats],
      CopySameTimes(_oct23),
      type: IntakeTypeEntity.lunch,
      movedFrom: from,
    );

    expect(intakes.deleted, [oats.id]);
    expect(days.kcal[from], -oats.totalKcal);
    final moved = intakes.added.single;
    expect(moved.id, oats.id);
    expect(moved.type, IntakeTypeEntity.lunch);
    expect(moved.dateTime, DateTime(2026, 10, 23, 8, 30));
    expect(days.kcal[_oct23], oats.totalKcal);

    expect(
      await copier().undoPlace(
        placed!,
        startedOn: ProfileStamp.now(),
        moved: [oats],
        from: from,
      ),
      isTrue,
    );
    expect(intakes.deleted, [oats.id, oats.id]);
    expect(intakes.added.last, oats);
    expect(days.kcal[from], 0);
    expect(days.kcal[_oct23], 0);
  });

  test('an undo takes off what is stored: a moved entry edited since '
      'leaves both days right', () async {
    final oats = at(
      intakeOf('oats', 50, type: IntakeTypeEntity.breakfast),
      DateTime(2026, 10, 22, 8, 30),
    );
    intakes.stored[oats.id] = oats;
    final from = DateTime(2026, 10, 22);
    final placed = await copier().placeIntakes(
      [oats],
      CopySameTimes(from),
      type: IntakeTypeEntity.lunch,
      movedFrom: from,
    );
    // The edit dialog then doubles its amount, as the Diary would.
    final doubled = intakes.stored[oats.id]!;
    intakes.stored[oats.id] = IntakeEntity(
      id: oats.id,
      unit: oats.unit,
      amount: 100,
      type: doubled.type,
      meal: oats.meal,
      dateTime: doubled.dateTime,
    );
    days.kcal[from] = days.kcal[from]! + oats.totalKcal;

    await copier().undoPlace(
      placed!,
      startedOn: ProfileStamp.now(),
      moved: [oats],
      from: from,
    );
    expect(intakes.stored.values.single, oats);
    // As before the move: the doubled amount's kcal all taken back off.
    expect(days.kcal[from], 0);
  });

  test('an entry deleted since it was picked is not moved', () async {
    final oats = at(intakeOf('oats', 50), DateTime(2026, 10, 22, 8));
    final placed = await copier().placeIntakes(
      [oats],
      CopySameTimes(_oct23),
      movedFrom: DateTime(2026, 10, 22),
    );
    expect(placed!.written, isEmpty);
    expect(intakes.added, isEmpty);
    expect(days.kcal[_oct23], isNull);
  });

  test('a copy\'s undo takes the copies back', () async {
    final oats = at(intakeOf('oats', 50), DateTime(2026, 10, 22, 8));
    final placed = await copier().placeIntakes([oats], CopySameTimes(_oct23));
    await copier().undoPlace(placed!, startedOn: ProfileStamp.now());

    expect(intakes.deleted, ['copy0']);
    expect(days.kcal[_oct23], 0);
  });

  Future<void> openSheet(
    WidgetTester tester, {
    required Set<IntakeTypeEntity> meals,
    int count = 1,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [S.delegate],
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showModalBottomSheet<WhereTo>(
              context: context,
              builder: (_) => WhereToSheet(
                today: _oct23,
                now: DateTime(2026, 10, 23, 12, 30),
                from: _oct23,
                meals: meals,
                count: count,
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('the sheet picks move, tomorrow and lunch with chips', (
    tester,
  ) async {
    WhereTo? picked;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [S.delegate],
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => picked = await showModalBottomSheet<WhereTo>(
              context: context,
              isScrollControlled: true,
              builder: (_) => WhereToSheet(
                today: _oct23,
                now: DateTime(2026, 10, 23, 12, 30),
                from: _oct23,
                meals: const {IntakeTypeEntity.breakfast},
                count: 1,
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Move'));
    await tester.pumpAndSettle();
    // A move to where it is changes nothing.
    final done = find.byKey(const Key('fork-where-done'));
    expect(tester.widget<FilledButton>(done).onPressed, isNull);
    // One food: the button says the verb alone.
    expect(
      find.descendant(of: done, matching: find.text('Move')),
      findsOneWidget,
    );
    // "Now" is today's only.
    expect(find.byKey(const Key('fork-where-now')), findsOneWidget);
    await tester.tap(find.byKey(const Key('fork-where-day1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('fork-where-now')), findsNothing);
    await tester.tap(find.byKey(const Key('fork-where-meal-lunch')));
    await tester.pumpAndSettle();
    await tester.tap(done);
    await tester.pumpAndSettle();

    expect(picked?.move, isTrue);
    expect(picked?.meal, IntakeTypeEntity.lunch);
    expect((picked?.moment as CopySameTimes).day, DateTime(2026, 10, 24));
  });

  testWidgets('foods from several meals can keep their own', (tester) async {
    await openSheet(
      tester,
      meals: const {IntakeTypeEntity.breakfast, IntakeTypeEntity.dinner},
      count: 2,
    );
    final own = tester.widget<ChoiceChip>(
      find.byKey(const Key('fork-where-own-meals')),
    );
    expect(own.selected, isTrue);
    expect(find.text('Copy 2 foods'), findsOneWidget);
  });

  testWidgets('the bar counts several in foods', (tester) async {
    final oats = at(intakeOf('oats', 50), DateTime(2026, 10, 22, 8));
    final rice = at(intakeOf('rice', 80), DateTime(2026, 10, 22, 9));
    intakes.stored[oats.id] = oats;
    intakes.stored[rice.id] = rice;
    final from = DateTime(2026, 10, 22);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [S.delegate],
        home: Scaffold(
          body: Builder(
            builder: (context) => Column(
              children: [
                TextButton(
                  onPressed: () => placeWithUndo(
                    context,
                    [oats, rice],
                    CopySameTimes(from),
                    meal: IntakeTypeEntity.lunch,
                    copier: copier(),
                  ),
                  child: const Text('copy'),
                ),
                TextButton(
                  onPressed: () => placeWithUndo(
                    context,
                    [oats, rice],
                    CopySameTimes(from),
                    meal: IntakeTypeEntity.lunch,
                    movedFrom: from,
                    copier: copier(),
                  ),
                  child: const Text('move'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('copy'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Copied 2 foods to Lunch'), findsOneWidget);

    await tester.tap(find.text('move'));
    await tester.pumpAndSettle();
    expect(find.text('Moved 2 foods to Lunch'), findsOneWidget);
  });

  testWidgets('a move says where, and its Undo puts the entry back', (
    tester,
  ) async {
    final oats = at(
      intakeOf('oats', 50, type: IntakeTypeEntity.breakfast),
      DateTime(2026, 10, 22, 8),
    );
    intakes.stored[oats.id] = oats;
    final from = DateTime(2026, 10, 22);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [S.delegate],
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => placeWithUndo(
                context,
                [oats],
                CopySameTimes(from),
                meal: IntakeTypeEntity.lunch,
                movedFrom: from,
                copier: copier(),
              ),
              child: const Text('move'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('move'));
    await tester.pumpAndSettle();

    expect(find.text('Moved to Lunch'), findsOneWidget);
    expect(intakes.added.single.type, IntakeTypeEntity.lunch);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(intakes.added.last, oats);
    expect(days.kcal[from], 0);
  });
}

final _oct23 = DateTime(2026, 10, 23);

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

class _Intakes extends Fake
    implements AddIntakeUsecase, GetIntakeUsecase, DeleteIntakeUsecase {
  final added = <IntakeEntity>[];
  final deleted = <String>[];
  final stored = <String, IntakeEntity>{};

  @override
  Future<void> deleteIntake(IntakeEntity intake) async {
    deleted.add(intake.id);
    stored.remove(intake.id);
  }

  var byMeal = <IntakeTypeEntity, List<IntakeEntity>>{};

  @override
  Future<void> addIntake(IntakeEntity intake) async {
    added.add(intake);
    stored[intake.id] = intake;
  }

  @override
  Future<IntakeEntity?> getIntakeById(String intakeId) async =>
      stored[intakeId];

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
  Future<void> removeDayCaloriesTracked(DateTime day, double calories) async =>
      kcal[day] = (kcal[day] ?? 0) - calories;

  @override
  Future<void> removeDayMacrosTracked(
    DateTime day, {
    double? carbsTracked,
    double? fatTracked,
    double? proteinTracked,
  }) async {}

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
