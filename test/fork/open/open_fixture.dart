import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:opennutritracker/core/data/data_source/config_data_source.dart';
import 'package:opennutritracker/core/data/data_source/custom_activity_template_dbo.dart';
import 'package:opennutritracker/core/data/data_source/custom_meal_data_source.dart';
import 'package:opennutritracker/core/data/data_source/intake_data_source.dart';
import 'package:opennutritracker/core/data/data_source/recipe_data_source.dart';
import 'package:opennutritracker/core/data/data_source/remote_search_cache_data_source.dart';
import 'package:opennutritracker/core/data/data_source/tracked_day_data_source.dart';
import 'package:opennutritracker/core/data/data_source/user_activity_data_source.dart';
import 'package:opennutritracker/core/data/data_source/user_activity_dbo.dart';
import 'package:opennutritracker/core/data/data_source/user_data_source.dart';
import 'package:opennutritracker/core/data/data_source/weight_log_data_source.dart';
import 'package:opennutritracker/core/data/dbo/config_dbo.dart';
import 'package:opennutritracker/core/data/dbo/fasting_session_dbo.dart';
import 'package:opennutritracker/core/data/dbo/favourite_meal_dbo.dart';
import 'package:opennutritracker/core/data/dbo/intake_dbo.dart';
import 'package:opennutritracker/core/data/dbo/meal_dbo.dart';
import 'package:opennutritracker/core/data/dbo/profile_dbo.dart';
import 'package:opennutritracker/core/data/dbo/recipe_dbo.dart';
import 'package:opennutritracker/core/data/dbo/tracked_day_dbo.dart';
import 'package:opennutritracker/core/data/dbo/user_dbo.dart';
import 'package:opennutritracker/core/data/dbo/water_intake_dbo.dart';
import 'package:opennutritracker/core/data/dbo/weight_log_dbo.dart';
import 'package:opennutritracker/core/data/repository/config_repository.dart';
import 'package:opennutritracker/core/data/repository/intake_repository.dart';
import 'package:opennutritracker/core/data/repository/recipe_repository.dart';
import 'package:opennutritracker/core/data/repository/tracked_day_repository.dart';
import 'package:opennutritracker/core/data/repository/user_activity_repository.dart';
import 'package:opennutritracker/core/data/repository/user_repository.dart';
import 'package:opennutritracker/core/data/repository/weight_log_repository.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/domain/entity/physical_activity_entity.dart';
import 'package:opennutritracker/core/domain/entity/recipe_entity.dart';
import 'package:opennutritracker/core/domain/entity/recipe_ingredient_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_activity_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_gender_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_pal_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_weight_goal_entity.dart';
import 'package:opennutritracker/core/domain/entity/weight_log_entity.dart';
import 'package:opennutritracker/core/domain/usecase/add_intake_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/add_tracked_day_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/add_user_activity_usercase.dart';
import 'package:opennutritracker/core/domain/usecase/add_user_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/compute_recipe_nutrition_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_intake_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_kcal_goal_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_macro_goal_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_tracked_day_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_user_activity_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_user_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_weight_log_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/log_user_activity_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/save_recipe_usecase.dart';
import 'package:opennutritracker/core/utils/calc/day_boundary_calc.dart';
import 'package:opennutritracker/core/utils/hive_db_provider.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/add_meal/data/repository/products_repository.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/features/fasting/data/data_source/fasting_data_source.dart';
import 'package:opennutritracker/features/fasting/data/repository/fasting_repository.dart';
import 'package:opennutritracker/features/fasting/domain/entity/fasting_session_entity.dart';
import 'package:opennutritracker/features/meal_detail/presentation/bloc/meal_detail_bloc.dart';
import 'package:opennutritracker/features/meal_detail/util/meal_quantity_converter.dart';
import 'package:opennutritracker/fork/adaptive/activity.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_service.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_store.dart';
import 'package:opennutritracker/fork/amounts/own_portions.dart';
import 'package:opennutritracker/fork/amounts/remembered_amounts.dart';
import 'package:opennutritracker/fork/body/measurement_store.dart';
import 'package:opennutritracker/fork/display/display_prefs.dart';
import 'package:opennutritracker/fork/goal/goal_progress.dart';
import 'package:opennutritracker/fork/phases/phases.dart';
import 'package:opennutritracker/fork/reminders/reminders.dart';

import '../../helpers/fake_hive_db_provider.dart';
import '../../helpers/hive_test_setup.dart';

/// The snapshot's today: the last Saturday on or before [now]. Monday
/// weeks and weekday shifts then fall the same on any run; the profile is
/// built relative to it, so no absolute date reaches the snapshot.
DateTime openToday([DateTime? now]) {
  final t = now ?? DateTime.now();
  return DateTime(t.year, t.month, t.day - (t.weekday - DateTime.saturday) % 7);
}

/// Monday to Friday 100 kcal under, the weekend 250 over.
const openWeekdayOffsets = [-100.0, -100.0, -100.0, -100.0, -100.0, 250.0, 250.0];

/// The settings the profile was used under: upstream's formula, weekend
/// shifts, the smoothed trend, workouts counted at 80% once activity is.
const openBaseSettings = AdaptiveSettings(
  smoothedTrend: true,
  weekdayOffsets: openWeekdayOffsets,
  workoutSharePct: 80,
);

/// The active profile's fork box as a plain box in the temp dir.
class _Provider extends FakeHiveDBProvider {
  _Provider({
    required super.configBox,
    required super.appConfigBox,
    required super.intakeBox,
    required super.userActivityBox,
    required super.userBox,
    required super.trackedDayBox,
    required super.customMealBox,
    required super.recipeBox,
    required super.weightLogBox,
    required super.fastingBox,
    required super.profileBox,
  }) : super(activeProfileId: 'open');

  @override
  Future<Box<E>> openScopedBox<E>(String baseName, String boxSuffix) =>
      Hive.openBox<E>(HiveDBProvider.boxNameFor(baseName, boxSuffix));
}

class _NoProducts extends Fake implements ProductsRepository {}

/// A recipe's meal has its id as code, so logging it touches the cache.
class _NoSearchCache extends Fake implements RemoteSearchCacheDataSource {
  @override
  Future<void> touch(String code) async {}
}

class _NoContext extends Fake implements BuildContext {}

/// The fixture's reminders never reach the OS.
class _NoOs implements ReminderScheduler {
  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<void> schedule(PlannedReminder reminder, {String? body}) async {}

  @override
  Future<void> cancel(ReminderKind kind) async {}
}

MealEntity _food(
  String name, {
  required double kcal,
  required double carbs,
  required double fat,
  required double protein,
  String unit = 'g',
  double? serving,
  String? servingSize,
  MealSourceEntity source = MealSourceEntity.custom,
}) => MealEntity(
  code: null,
  name: name,
  url: null,
  mealQuantity: '100',
  mealUnit: unit,
  servingQuantity: serving,
  servingUnit: serving == null ? null : unit,
  servingSize: servingSize,
  nutriments: MealNutrimentsEntity(
    energyKcal100: kcal,
    carbohydrates100: carbs,
    fat100: fat,
    proteins100: protein,
    sugars100: null,
    saturatedFat100: null,
    fiber100: null,
  ),
  source: source,
);

RecipeIngredientEntity _part(MealEntity meal, double grams) =>
    RecipeIngredientEntity(
      snapshotMeal: meal,
      amount: grams,
      unit: 'g',
      convertedAmountG: grams,
    );

/// What [fillOpenFixture] made, and the app's use cases over it.
class OpenFixture {
  final Directory dir;
  final DateTime today;
  final HiveDBProvider db;

  final GetConfigUsecase config;
  final ConfigDataSource configSource;
  final GetUserUsecase user;
  final GetKcalGoalUsecase kcalGoal;
  final GetMacroGoalUsecase macroGoal;
  final GetIntakeUsecase intakes;
  final GetUserActivityUsecase activities;
  final GetTrackedDayUsecase trackedDays;
  final AddTrackedDayUsecase addTrackedDay;
  final GetWeightLogUsecase weights;
  final FastingRepository fasting;
  final CustomMealDataSource customMeals;
  final MealDetailBloc mealDetail;

  final MealEntity bread, milk, chicken, rice, apple, bar;
  final RecipeEntity chili, pastaBake;
  final PhasePlan plan;

  OpenFixture({
    required this.dir,
    required this.today,
    required this.db,
    required this.config,
    required this.configSource,
    required this.user,
    required this.kcalGoal,
    required this.macroGoal,
    required this.intakes,
    required this.activities,
    required this.trackedDays,
    required this.addTrackedDay,
    required this.weights,
    required this.fasting,
    required this.customMeals,
    required this.mealDetail,
    required this.bread,
    required this.milk,
    required this.chicken,
    required this.rice,
    required this.apple,
    required this.bar,
    required this.chili,
    required this.pastaBake,
    required this.plan,
  });

  /// [offset] days from today, as a day label.
  DateTime day(int offset) =>
      DateTime(today.year, today.month, today.day + offset);

  /// [offset] days from today at [hour]:[minute].
  DateTime at(int offset, int hour, [int minute = 0]) =>
      DateTime(today.year, today.month, today.day + offset, hour, minute);

  /// The snapshot's "now": two in the afternoon, after lunch.
  DateTime get now => at(0, 14);

  /// The adaptive service as the app builds it, at [moment] (now by
  /// default), over [store] (the active profile's by default).
  AdaptiveService service({DateTime? moment, AdaptiveStore? store}) =>
      AdaptiveService(
        user,
        weights,
        trackedDays,
        store ?? AdaptiveStore(),
        () => moment ?? now,
        MeasurementStore(),
        ActivityCounter.fromLocator(),
      );
}

/// Days of history before today.
const openHistoryDays = 35;

/// Not logged: a break of six days in a row (D27), and two scattered days
/// inside the Trends window, one with a workout on it.
const openUnloggedDays = {-28, -27, -26, -25, -24, -23, -9, -4};

/// Workouts, by day: kcal burned. Today's is long enough that 80% of it
/// passes the daily mode's 800 kcal cap.
const openWorkouts = {-30: 400.0, -16: 450.0, -11: 600.0, -4: 500.0, -2: 400.0, 0: 1250.0};

/// Weigh-ins every two or three days, by day: kg.
const openWeighIns = {
  -35: 86.0,
  -33: 85.8,
  -30: 85.9,
  -28: 85.5,
  -25: 85.9,
  -22: 86.2,
  -20: 85.7,
  -17: 85.4,
  -15: 85.3,
  -12: 85.0,
  -10: 84.9,
  -7: 84.6,
  -5: 84.5,
  -2: 84.2,
  0: 84.0,
};

/// The day the user asked the estimate to leave out (D17).
const openSkippedDay = -15;

/// Check-ins accepted, a week apart, the last yesterday.
const openCheckInDays = [-15, -8, -1];

/// Fills a profile in Hive under [dir] as the app would have written it
/// over five weeks of use, today being [today], and registers in the
/// service locator what fork code reads through it. Undo with
/// [disposeOpenFixture].
Future<OpenFixture> fillOpenFixture(Directory dir, DateTime today) async {
  Hive.init(dir.path);
  registerHiveAdaptersOnce();
  final db = _Provider(
    configBox: await Hive.openBox<ConfigDBO>('ConfigBox'),
    appConfigBox: await Hive.openBox<ConfigDBO>('AppConfigBox'),
    intakeBox: await Hive.openBox<IntakeDBO>('IntakeBox'),
    userActivityBox: await Hive.openBox<UserActivityDBO>('UserActivityBox'),
    userBox: await Hive.openBox<UserDBO>('UserBox'),
    trackedDayBox: await Hive.openBox<TrackedDayDBO>('TrackedDayBox'),
    customMealBox: await Hive.openBox<MealDBO>('CustomMealBox'),
    recipeBox: await Hive.openBox<RecipeDBO>('RecipeBox'),
    weightLogBox: await Hive.openBox<WeightLogDBO>('WeightLogBox'),
    fastingBox: await Hive.openBox<FastingSessionDBO>('FastingBox'),
    profileBox: await Hive.openBox<ProfileDBO>('ProfileBox'),
  );
  // Opened for the adapters' sake only; nothing here writes them.
  await Hive.openBox<WaterIntakeDBO>('WaterIntakeBox');
  await Hive.openBox<FavouriteMealDBO>('FavouriteMealBox');
  await Hive.openBox<CustomActivityTemplateDBO>('CustomActivityTemplateBox');

  final configSource = ConfigDataSource(db);
  await configSource.initializeConfig();
  final configRepo = ConfigRepository(configSource);
  final userRepo = UserRepository(UserDataSource(db));
  final intakeRepo = IntakeRepository(IntakeDataSource(db));
  final dayRepo = TrackedDayRepository(TrackedDayDataSource(db));
  final activityRepo = UserActivityRepository(UserActivityDataSource(db));
  final weightRepo = WeightLogRepository(WeightLogDataSource(db));
  final recipeRepo = RecipeRepository(RecipeDataSource(db));
  final config = GetConfigUsecase(configRepo);
  final user = GetUserUsecase(userRepo);
  final kcalGoal = GetKcalGoalUsecase(userRepo, configRepo, activityRepo);
  final macroGoal = GetMacroGoalUsecase(configRepo);
  final addTrackedDay = AddTrackedDayUsecase(dayRepo);
  final trackedDays = GetTrackedDayUsecase(dayRepo);
  final weights = GetWeightLogUsecase(weightRepo);

  locator.registerSingleton<HiveDBProvider>(db);
  locator.registerSingleton<GetConfigUsecase>(config);
  locator.registerSingleton<GetUserUsecase>(user);
  locator.registerSingleton<GetWeightLogUsecase>(weights);
  locator.registerSingleton<GetTrackedDayUsecase>(trackedDays);
  locator.registerSingleton<UserActivityRepository>(activityRepo);
  locator.registerSingleton<WeightLogRepository>(weightRepo);
  locator.registerSingleton<IntakeDataSource>(IntakeDataSource(db));

  OpenFixture? made;
  DateTime day(int offset) =>
      DateTime(today.year, today.month, today.day + offset);
  DateTime at(int offset, int hour, [int minute = 0]) =>
      DateTime(today.year, today.month, today.day + offset, hour, minute);

  await configSource.setConfigCarbGoalPct(0.45);
  await configSource.setConfigFatGoalPct(0.3);
  await configSource.setConfigProteinGoalPct(0.25);
  await AddUserUsecase(userRepo).addUser(
    UserEntity(
      // Always 30: upstream's age reads the real clock.
      birthday: DateTime(today.year - 30, today.month - 6, today.day),
      heightCM: 180,
      weightKG: openWeighIns[0]!,
      gender: UserGenderEntity.male,
      goal: UserWeightGoalEntity.loseWeight,
      pal: UserPALEntity.lowActive,
      weeklyWeightGoalKg: -0.5,
      targetWeightKg: 78,
    ),
  );
  await AdaptiveStore().save(openBaseSettings);

  await DisplayPrefs.setMacroOrder([Macro.protein, Macro.fat, Macro.carbs]);
  await DisplayPrefs.setDiaryByHour(true);
  await DisplayPrefs.setHomeShowsEaten(true);
  await DisplayPrefs.setShowWater(true);
  await DisplayPrefs.setShowFasting(true);

  final bread = _food(
    'Wholegrain bread',
    kcal: 250,
    carbs: 45,
    fat: 3,
    protein: 10,
    serving: 32,
    servingSize: '1 slice (32 g)',
  );
  final milk = _food(
    'Milk',
    kcal: 50,
    carbs: 5,
    fat: 1.5,
    protein: 3.5,
    unit: 'ml',
  );
  final chicken = _food(
    'Chicken breast',
    kcal: 120,
    carbs: 0,
    fat: 2,
    protein: 24,
  );
  final rice = _food('Cooked rice', kcal: 130, carbs: 28, fat: 0.5, protein: 3);
  final apple = _food('Apple', kcal: 50, carbs: 12, fat: 0, protein: 0.5);
  final bar = _food(
    'Protein bar',
    kcal: 400,
    carbs: 35,
    fat: 15,
    protein: 32,
    serving: 60,
    servingSize: '1 bar (60 g)',
  );
  final customMeals = CustomMealDataSource(db);
  await customMeals.saveCustomMeal(MealDBO.fromMealEntity(bar));

  final beans = _food('Kidney beans', kcal: 100, carbs: 15, fat: 0.5, protein: 7);
  final beef = _food('Minced beef', kcal: 250, carbs: 0, fat: 18, protein: 22);
  final tomato = _food('Chopped tomato', kcal: 20, carbs: 3.5, fat: 0, protein: 1);
  final pasta = _food('Cooked pasta', kcal: 150, carbs: 30, fat: 1, protein: 5);
  final cheese = _food('Cheddar', kcal: 400, carbs: 0, fat: 33, protein: 25);
  final saveRecipe = SaveRecipeUseCase(
    recipeRepo,
    ComputeRecipeNutritionUseCase(),
  );
  RecipeEntity recipe(
    String id,
    String name,
    int servings,
    List<RecipeIngredientEntity> parts,
  ) => RecipeEntity(
    id: id,
    name: name,
    description: null,
    ingredients: parts,
    totalWeightG: 0,
    aggregatedNutrimentsPer100: MealNutrimentsEntity.empty(),
    createdAt: day(-40),
    updatedAt: day(-40),
    servingsCount: servings,
  );
  final chili = await saveRecipe.save(
    recipe('open-chili', 'Chili', 2, [
      _part(beans, 400),
      _part(beef, 300),
      _part(tomato, 300),
    ]),
  );
  final pastaBake = await saveRecipe.save(
    recipe('open-pasta-bake', 'Pasta bake', 1, [
      _part(pasta, 350),
      _part(tomato, 120),
      _part(cheese, 30),
    ]),
  );

  final ownPortions = OwnPortions();
  await ownPortions.add(apple, 'medium apple', 180);
  final appleOwn = withOwnPortions(apple, await ownPortions.of(apple));
  final remembered = RememberedAmounts();

  for (final MapEntry(key: offset, value: kg) in openWeighIns.entries) {
    await weightRepo.addEntry(
      WeightLogEntity(date: at(offset, 7), weightKg: kg),
    );
  }
  final measurements = MeasurementStore();
  await measurements.addDay(day(-20), {
    BodyMetric.bodyFat: 22,
    BodyMetric.waist: 92,
  });
  await measurements.addDay(day(-6), {BodyMetric.waist: 90.5});

  final mealDetail = MealDetailBloc(
    AddIntakeUsecase(intakeRepo),
    addTrackedDay,
    kcalGoal,
    macroGoal,
    trackedDays,
    _NoProducts(),
    _NoSearchCache(),
  );
  final logActivity = LogUserActivityUsecase(
    AddUserActivityUsecase(activityRepo),
    addTrackedDay,
    kcalGoal,
    macroGoal,
  );

  // As the bottom sheet logs: the unit picked, the amount in grams.
  Future<void> eat(
    int offset,
    int hour,
    IntakeTypeEntity type,
    MealEntity meal,
    String unit,
    double quantity,
  ) => mealDetail.addIntake(
    _NoContext(),
    unit,
    convertQuantityToBaseUnit(quantity, unit, meal).toString(),
    type,
    meal,
    at(offset, hour),
  );

  try {
    for (var offset = -openHistoryDays; offset <= 0; offset++) {
      // Each day logged as it happened, its goals as they stood that day.
      DayBoundaryCalc.clock = () => at(offset, 14);
      final n = offset + openHistoryDays;
      if (openWorkouts[offset] case final kcal?) {
        await logActivity.logActivity(
          UserActivityEntity(
            'open-workout$offset',
            60,
            kcal,
            at(offset, 7),
            PhysicalActivityEntity.custom,
            userKcal: kcal,
          ),
          day: day(offset),
        );
      }
      if (openUnloggedDays.contains(offset)) continue;
      await eat(offset, 8, IntakeTypeEntity.breakfast, bread, 'serving', 2);
      await eat(offset, 8, IntakeTypeEntity.breakfast, milk, 'ml', 250);
      await eat(offset, 10, IntakeTypeEntity.snack, appleOwn, 'serving', 1);
      await eat(
        offset,
        13,
        IntakeTypeEntity.lunch,
        chicken,
        'g',
        150 + 10.0 * (n % 3),
      );
      await eat(offset, 13, IntakeTypeEntity.lunch, rice, 'g', 200 + 25.0 * (n % 4));
      // Today is logged up to lunch.
      if (offset == 0) continue;
      if (n % 3 == 0) {
        await eat(offset, 16, IntakeTypeEntity.snack, bar, 'serving', 1);
      }
      await eat(
        offset,
        19,
        IntakeTypeEntity.dinner,
        (n.isEven ? chili : pastaBake).toMealEntity(),
        'serving',
        1,
      );
    }
    await remembered.remember(bread, 'serving', '2');
    await remembered.remember(
      appleOwn,
      rememberedUnitOf(appleOwn, 'serving'),
      '1',
    );

    await AdaptiveStore().setSkipped(day(openSkippedDay), true);

    final store = AdaptiveStore();
    for (final offset in openCheckInDays) {
      final service = AdaptiveService(
        user,
        weights,
        trackedDays,
        store,
        () => at(offset, 14),
        MeasurementStore(),
      );
      final checkIn = await service.checkIn();
      await service.accept(checkIn, checkIn.proposedTargetKcal);
    }

    // A cut, a week's diet break, and the cut again to the target.
    final plan = PhasePlan(
      start: day(-28),
      startKg: 85.5,
      targetKg: 78,
      phases: const [
        DietPhase(kind: PhaseKind.cut, kgPerWeek: -0.5, weeks: 3),
        DietPhase(kind: PhaseKind.maintain, kgPerWeek: 0, weeks: 1),
        DietPhase(kind: PhaseKind.cut, kgPerWeek: -0.5, weeks: 12, untilKg: 78),
      ],
    );
    final phases = PhaseStore();
    await phases.save(plan);
    await phases.saveUpcoming([
      PhasePlan(
        start: plan.end,
        startKg: 78,
        phases: const [
          DietPhase(kind: PhaseKind.maintain, kgPerWeek: 0, weeks: 8),
        ],
      ),
    ]);
    await phases.addToHistory([
      GoalRecord(
        kind: PhaseKind.bulk,
        start: day(-200),
        end: day(-60),
        startKg: 80,
        endKg: 86,
        targetKg: 86,
      ),
    ]);
    await GoalStartStore().save(
      GoalStart(
        date: day(-28),
        kg: 85.5,
        targetKg: 78,
        paceKgPerWeek: -0.5,
      ),
    );

    final fasting = FastingRepository(FastingDataSource(db));
    await fasting.addSession(
      FastingSessionEntity(
        id: 'open-fast-1',
        startedAt: at(-3, 20),
        targetDurationMinutes: 16 * 60,
        completedAt: at(-2, 13),
      ),
    );
    await fasting.addSession(
      FastingSessionEntity(
        id: 'open-fast-2',
        startedAt: at(-1, 20),
        targetDurationMinutes: 18 * 60,
        cancelledAt: at(0, 10),
      ),
    );

    final reminders = Reminders(
      scheduler: _NoOs(),
      clock: () => at(0, 14),
      checkInDueDay: () async => null,
      checkInResult: () async => null,
    );
    await reminders.set(ReminderKind.weighIn, (hour: 7, minute: 30));
    await reminders.set(ReminderKind.checkIn, (hour: 9, minute: 0));

    made = OpenFixture(
      dir: dir,
      today: today,
      db: db,
      config: config,
      configSource: configSource,
      user: user,
      kcalGoal: kcalGoal,
      macroGoal: macroGoal,
      intakes: GetIntakeUsecase(intakeRepo, recipeRepo),
      activities: GetUserActivityUsecase(activityRepo),
      trackedDays: trackedDays,
      addTrackedDay: addTrackedDay,
      weights: weights,
      fasting: fasting,
      customMeals: customMeals,
      mealDetail: mealDetail,
      bread: bread,
      milk: milk,
      chicken: chicken,
      rice: rice,
      apple: apple,
      bar: bar,
      chili: chili,
      pastaBake: pastaBake,
      plan: plan,
    );
    return made;
  } finally {
    DayBoundaryCalc.clock = () => at(0, 14);
    if (made == null) await mealDetail.close();
  }
}

/// Closes and deletes what [fillOpenFixture] made, and puts back every
/// static it set, so the bundled suite's next file starts clean.
Future<void> disposeOpenFixture(OpenFixture? fixture) async {
  await fixture?.mealDetail.close();
  AdaptiveStore.settings.value = const AdaptiveSettings();
  AdaptiveStore.skipped.value = const {};
  DayBoundaryCalc.clock = DateTime.now;
  DisplayPrefs.macroOrder.value = DisplayPrefs.upstreamOrder;
  DisplayPrefs.diaryByHour.value = false;
  DisplayPrefs.homeShowsEaten.value = false;
  DisplayPrefs.showWater.value = false;
  DisplayPrefs.showFasting.value = false;
  await locator.reset();
  await Hive.deleteFromDisk();
}
