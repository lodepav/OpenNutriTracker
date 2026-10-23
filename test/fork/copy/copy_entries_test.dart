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
import 'package:opennutritracker/fork/copy/copy_entries.dart';

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

  test('with a 4 am day start, a 1 am entry stays after midnight of the '
      'target day', () async {
    config = _Config(4);
    final lateSnack = at(intakeOf('chips', 30), DateTime(2026, 10, 22, 1));
    // 1 am on the 22nd belongs to the logical day of the 21st.
    await copier().copyIntakes([lateSnack], DateTime(2026, 10, 23));
    expect(intakes.added.single.dateTime, DateTime(2026, 10, 24, 1));
    expect(intakes.added.single.type, lateSnack.type);
  });

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
