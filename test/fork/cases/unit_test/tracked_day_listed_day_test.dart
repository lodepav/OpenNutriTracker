// Fork cases moved out of test/unit_test/tracked_day_listed_day_test.dart (they test the fork's changes).

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:opennutritracker/core/data/data_source/config_data_source.dart';
import 'package:opennutritracker/core/data/data_source/intake_data_source.dart';
import 'package:opennutritracker/core/data/data_source/recipe_data_source.dart';
import 'package:opennutritracker/core/data/data_source/remote_search_cache_data_source.dart';
import 'package:opennutritracker/core/data/data_source/tracked_day_data_source.dart';
import 'package:opennutritracker/core/data/data_source/user_activity_data_source.dart';
import 'package:opennutritracker/core/data/data_source/user_activity_dbo.dart';
import 'package:opennutritracker/core/data/dbo/config_dbo.dart';
import 'package:opennutritracker/core/data/dbo/intake_dbo.dart';
import 'package:opennutritracker/core/data/dbo/tracked_day_dbo.dart';
import 'package:opennutritracker/core/data/repository/intake_repository.dart';
import 'package:opennutritracker/core/data/repository/recipe_repository.dart';
import 'package:opennutritracker/core/data/repository/tracked_day_repository.dart';
import 'package:opennutritracker/core/data/repository/user_activity_repository.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_activity_entity.dart';
import 'package:opennutritracker/core/domain/usecase/add_intake_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/add_tracked_day_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/add_user_activity_usercase.dart';
import 'package:opennutritracker/core/domain/usecase/get_intake_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_kcal_goal_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_macro_goal_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_tracked_day_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_user_activity_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/log_user_activity_usecase.dart';
import 'package:opennutritracker/core/utils/tracked_day_reconciler.dart';
import 'package:opennutritracker/features/add_meal/data/repository/products_repository.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/features/meal_detail/presentation/bloc/meal_detail_bloc.dart';

import '../../../fixture/physical_activity_entity_fixtures.dart';
import '../../../helpers/fake_hive_db_provider.dart';
import '../../../helpers/hive_test_setup.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_store.dart';

/// #1317: the Diary shows "Nothing added" for a day whose entries it lists.
///
/// The summary card is drawn only when the day has a tracked-day row, so
/// every writer has to put an entry's calories on the row of the day the
/// Diary lists that entry under. With a day-start boundary configured the
/// Diary files an entry logged at 02:00 under the previous day; these
/// tests pin that the row follows it. The later groups pin the pass that
/// brings rows written under another keying — by an older build, or
/// before the boundary moved — back in line with the listed entries.
class _FakeKcalGoal extends Fake implements GetKcalGoalUsecase {
  @override
  Future<double> getKcalGoal({
    dynamic userEntity,
    double? totalKcalActivitiesParam,
    double? kcalUserAdjustment,
  }) async => 2000;
}

class _FakeMacroGoal extends Fake implements GetMacroGoalUsecase {
  @override
  Future<double> getCarbsGoal(double totalCalorieGoal) async => 250;

  @override
  Future<double> getFatsGoal(double totalCalorieGoal) async => 70;

  @override
  Future<double> getProteinsGoal(double totalCalorieGoal) async => 100;
}

class _FakeProductsRepository extends Fake implements ProductsRepository {}

class _FakeRemoteSearchCache extends Fake
    implements RemoteSearchCacheDataSource {}

class _FakeContext extends Fake implements BuildContext {}

/// 200 kcal per 100 g, and no barcode, so logging it never reaches the
/// remote-cache refresh.
final _meal = MealEntity(
  code: null,
  name: 'Toast',
  url: null,
  mealQuantity: '100',
  mealUnit: 'g',
  servingQuantity: 100,
  servingUnit: 'g',
  servingSize: null,
  nutriments: MealNutrimentsEntity(
    energyKcal100: 200,
    carbohydrates100: 40,
    fat100: 2,
    proteins100: 6,
    sugars100: null,
    saturatedFat100: null,
    fiber100: null,
  ),
  source: MealSourceEntity.custom,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Box<ConfigDBO> configBox;
  late Box<IntakeDBO> intakeBox;
  late Box<TrackedDayDBO> trackedDayBox;
  late Box<UserActivityDBO> activityBox;
  late FakeHiveDBProvider db;

  late GetIntakeUsecase getIntake;
  late GetUserActivityUsecase getActivities;
  late GetTrackedDayUsecase getTrackedDay;
  late MealDetailBloc mealDetailBloc;
  late LogUserActivityUsecase logActivity;
  late IntakeRepository intakeRepository;
  late UserActivityRepository activityRepository;

  setUpAll(() {
    Hive.init('.');
    registerHiveAdaptersOnce();
  });

  setUp(() async {
    final tag = DateTime.now().microsecondsSinceEpoch;
    configBox = await Hive.openBox<ConfigDBO>('listed_day_config_$tag');
    intakeBox = await Hive.openBox<IntakeDBO>('listed_day_intake_$tag');
    trackedDayBox = await Hive.openBox<TrackedDayDBO>('listed_day_day_$tag');
    activityBox = await Hive.openBox<UserActivityDBO>('listed_day_act_$tag');
    db = FakeHiveDBProvider(
      configBox: configBox,
      intakeBox: intakeBox,
      trackedDayBox: trackedDayBox,
      userActivityBox: activityBox,
    );
    await ConfigDataSource(db).initializeConfig();

    intakeRepository = IntakeRepository(IntakeDataSource(db));
    final trackedDayRepository = TrackedDayRepository(TrackedDayDataSource(db));
    activityRepository = UserActivityRepository(UserActivityDataSource(db));
    final addTrackedDay = AddTrackedDayUsecase(trackedDayRepository);
    getIntake = GetIntakeUsecase(
      intakeRepository,
      RecipeRepository(RecipeDataSource(db)),
    );
    getActivities = GetUserActivityUsecase(activityRepository);
    getTrackedDay = GetTrackedDayUsecase(trackedDayRepository);
    mealDetailBloc = MealDetailBloc(
      AddIntakeUsecase(intakeRepository),
      addTrackedDay,
      _FakeKcalGoal(),
      _FakeMacroGoal(),
      getTrackedDay,
      _FakeProductsRepository(),
      _FakeRemoteSearchCache(),
    );
    logActivity = LogUserActivityUsecase(
      AddUserActivityUsecase(activityRepository),
      addTrackedDay,
      _FakeKcalGoal(),
      _FakeMacroGoal(),
    );
  });

  tearDown(() async {
    await mealDetailBloc.close();
    await configBox.deleteFromDisk();
    await intakeBox.deleteFromDisk();
    await trackedDayBox.deleteFromDisk();
    await activityBox.deleteFromDisk();
  });

  Future<void> setBoundary(int hours) =>
      ConfigDataSource(db).setConfigDayStartOffsetHours(hours);

  /// What the Diary's CalendarDayBloc loads for the cell [label].
  Future<({int intakes, int activities, TrackedDayDBO? row})> diaryDay(
    DateTime label, {
    int boundaryHours = 0,
  }) async {
    final intakes = await getIntake.getBreakfastIntakeByDay(
      label,
      dayStartOffsetHours: boundaryHours,
    );
    final activities = await getActivities.getUserActivityByDay(
      label,
      dayStartOffsetHours: boundaryHours,
    );
    final row = await getTrackedDay.getTrackedDay(label);
    return (
      intakes: intakes.length,
      activities: activities.length,
      row: row == null ? null : TrackedDayDBO.fromTrackedDayEntity(row),
    );
  }

  Future<void> addFood(DateTime day) => mealDetailBloc.addIntake(
    _FakeContext(),
    'g',
    '100',
    IntakeTypeEntity.breakfast,
    _meal,
    day,
  );

  UserActivityEntity activityAt(DateTime at) => UserActivityEntity(
    'walk-${at.microsecondsSinceEpoch}',
    30,
    150,
    at,
    PhysicalActivityFixtures.moderateBicycling,
  );

  /// An intake as an older build left it: in the box, with no row
  /// written for it here.
  Future<void> addLoggedIntake(String id, DateTime at) =>
      intakeRepository.addIntake(
        IntakeEntity(
          id: id,
          unit: 'g',
          amount: 100,
          type: IntakeTypeEntity.breakfast,
          meal: _meal,
          dateTime: at,
        ),
      );

  /// A row as an older build keyed it, holding one 200 kcal toast.
  TrackedDayDBO legacyRow(DateTime day, {double kcal = 200}) => TrackedDayDBO(
    day: day,
    calorieGoal: 1800,
    caloriesTracked: kcal,
    carbsGoal: 225,
    carbsTracked: kcal / 5,
    fatGoal: 60,
    fatTracked: kcal / 100,
    proteinGoal: 90,
    proteinTracked: kcal * 3 / 100,
    fibreGoal: 35,
  );

  test('under a fixed target, moving the boundary moves no activity '
      'credit', () async {
    const fixed = AdaptiveSettings(fixedTarget: true, fixedKcal: 2000);
    // The active profile's settings, as logging reads them, and its box,
    // which the reconciler reads.
    AdaptiveStore.settings.value = fixed;
    addTearDown(() => AdaptiveStore.settings.value = const AdaptiveSettings());
    final box = await Hive.openBox<dynamic>('listed_day_adaptive');
    addTearDown(box.deleteFromDisk);
    final adaptive = AdaptiveStore.otherProfile(() async => box);
    await adaptive.save(fixed);
    Future<int> reconcileFixed() => ensureTrackedDaysMatchEntries(
      db,
      ConfigDataSource(db),
      adaptiveStore: adaptive,
    );
    await reconcileFixed();
    final at = DateTime(2026, 10, 5, 2);
    await addFood(DateTime(2026, 10, 4, 12));
    await logActivity.logActivity(activityAt(at), day: at);
    final goal = (await diaryDay(DateTime.utc(2026, 10, 4))).row!.calorieGoal;
    await setBoundary(4);

    await reconcileFixed();

    final day = await diaryDay(DateTime.utc(2026, 10, 4), boundaryHours: 4);
    expect(day.activities, 1);
    expect(day.row!.calorieGoal, goal);
  });

  group('writers running alongside the pass', () {
    test(
      'a new row takes its own weekday shift, not the nearest row\'s',
      () async {
        await setBoundary(4);
        await addLoggedIntake('toast', DateTime(2026, 10, 5, 2));
        // Monday's row, its goal shifted +300 for the weekday.
        await trackedDayBox.put(
          '2026-10-05',
          legacyRow(DateTime(2026, 10, 5, 2)),
        );

        await reconcileTrackedDays(
          db,
          offsetMinutes: 4 * 60,
          weekdayOffsets: const [300, 0, 0, 0, 0, 0, 0],
        );

        // Sunday the 4th, unshifted, its macros scaled with the energy.
        final row = trackedDayBox.get('2026-10-04')!;
        expect(row.calorieGoal, 1500);
        expect(row.carbsGoal, closeTo(187.5, 1e-9));
        expect(row.proteinGoal, closeTo(75, 1e-9));
      },
    );

    test('under a macro program a new row moves only carbs and fat', () async {
      await setBoundary(4);
      await addLoggedIntake('toast', DateTime(2026, 10, 5, 2));
      await trackedDayBox.put(
        '2026-10-05',
        legacyRow(DateTime(2026, 10, 5, 2)),
      );

      await reconcileTrackedDays(
        db,
        offsetMinutes: 4 * 60,
        weekdayOffsets: const [300, 0, 0, 0, 0, 0, 0],
        scaleMacros: false,
      );

      final row = trackedDayBox.get('2026-10-04')!;
      expect(row.calorieGoal, 1500);
      // Protein follows the body; the shift comes off carbs and fat.
      expect(row.proteinGoal, 90);
      expect(row.carbsGoal, closeTo(225 * 1140 / 1440, 1e-9));
      expect(row.fatGoal, closeTo(60 * 1140 / 1440, 1e-9));
    });
  });
}
