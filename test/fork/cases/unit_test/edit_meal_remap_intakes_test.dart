// Fork cases moved out of test/unit_test/edit_meal_remap_intakes_test.dart (they test the fork's changes).

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:opennutritracker/core/data/data_source/custom_meal_data_source.dart';
import 'package:opennutritracker/core/data/data_source/intake_data_source.dart';
import 'package:opennutritracker/core/data/data_source/recipe_data_source.dart';
import 'package:opennutritracker/core/data/data_source/tracked_day_data_source.dart';
import 'package:opennutritracker/core/data/dbo/intake_dbo.dart';
import 'package:opennutritracker/core/data/dbo/intake_type_dbo.dart';
import 'package:opennutritracker/core/data/dbo/meal_dbo.dart';
import 'package:opennutritracker/core/data/dbo/profile_dbo.dart';
import 'package:opennutritracker/core/data/dbo/tracked_day_dbo.dart';
import 'package:opennutritracker/core/data/repository/config_repository.dart';
import 'package:opennutritracker/core/data/repository/favourite_meal_repository.dart';
import 'package:opennutritracker/core/data/repository/intake_repository.dart';
import 'package:opennutritracker/core/data/repository/recipe_repository.dart';
import 'package:opennutritracker/core/data/repository/tracked_day_repository.dart';
import 'package:opennutritracker/core/domain/usecase/add_tracked_day_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/delete_intake_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_intake_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/merge_custom_meals_usecase.dart';
import 'package:opennutritracker/core/utils/hive_db_provider.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/features/edit_meal/presentation/bloc/edit_meal_bloc.dart';
import 'package:opennutritracker/features/settings/presentation/bloc/custom_meals_bloc.dart';

import '../../../helpers/fake_hive_db_provider.dart';
import '../../../helpers/hive_test_setup.dart';

/// Diary entries know a custom meal by its identity — its barcode, or its
/// name when it has none — as it was when they were logged. An edit that
/// changes that identity moves the entries already logged to the new one,
/// in every profile, so they stay linked to the meal and deleting it
/// removes them too (#1417).
void main() {
  final day = DateTime(2026, 10, 1);

  late Box<MealDBO> customMealBox;
  late Box<IntakeDBO> intakeBox;
  late Box<TrackedDayDBO> trackedDayBox;
  late Box<IntakeDBO> otherIntakeBox;
  late Box<ProfileDBO> profileBox;
  late _ProfilesHiveDBProvider db;
  late _RecordingFavouriteMealRepository favourites;
  late EditMealBloc bloc;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    Hive.init('.');
    registerHiveAdaptersOnce();
  });

  setUp(() async {
    final stamp = DateTime.now().microsecondsSinceEpoch;
    customMealBox = await Hive.openBox<MealDBO>('remap_custom_$stamp');
    intakeBox = await Hive.openBox<IntakeDBO>('remap_intake_$stamp');
    trackedDayBox = await Hive.openBox<TrackedDayDBO>('remap_tracked_$stamp');
    otherIntakeBox = await Hive.openBox<IntakeDBO>('remap_other_$stamp');
    profileBox = await Hive.openBox<ProfileDBO>('remap_profiles_$stamp');
    await profileBox.addAll([
      ProfileDBO(
        id: 'me',
        name: 'Me',
        createdAt: DateTime(2026),
        boxSuffix: '',
      ),
      ProfileDBO(
        id: 'partner',
        name: 'Partner',
        createdAt: DateTime(2026),
        boxSuffix: '_partner',
      ),
    ]);
    db = _ProfilesHiveDBProvider(
      profiles: profileBox,
      scopedIntakeBoxes: {'_partner': otherIntakeBox},
      customMealBox: customMealBox,
      intakeBox: intakeBox,
      trackedDayBox: trackedDayBox,
    );
    favourites = _RecordingFavouriteMealRepository();
    bloc = EditMealBloc(
      _FakeGetConfigUsecase(),
      CustomMealDataSource(db),
      _FakeConfigRepository(),
      favourites,
      IntakeRepository(IntakeDataSource(db)),
    );
  });

  tearDown(() async {
    await bloc.close();
    await Hive.deleteFromDisk();
  });

  MealEntity customMeal({
    required String? code,
    required String name,
    double kcal = 89,
    MealSourceEntity source = MealSourceEntity.custom,
  }) => MealEntity(
    code: code,
    name: name,
    url: null,
    mealQuantity: '100',
    mealUnit: 'g',
    servingQuantity: 100,
    servingUnit: 'g',
    servingSize: '',
    nutriments: MealNutrimentsEntity(
      energyKcal100: kcal,
      carbohydrates100: 23,
      fat100: 0.3,
      proteins100: 1.1,
      sugars100: null,
      saturatedFat100: null,
      fiber100: null,
    ),
    source: source,
  );

  IntakeDBO intakeOf(String id, MealEntity meal) => IntakeDBO(
    id: id,
    unit: 'g',
    amount: 100,
    type: IntakeTypeDBO.breakfast,
    meal: MealDBO.fromMealEntity(meal),
    dateTime: day,
  );

  // past entries stay, as a recipe's do
  test('deleting the edited meal keeps the entries logged before the '
      'edit, and their calories', () async {
    final oats = customMeal(code: 'uuid-oats', name: 'Oats', kcal: 370);
    await customMealBox.add(MealDBO.fromMealEntity(oats));
    await intakeBox.addAll([intakeOf('o1', oats), intakeOf('o2', oats)]);
    final addTrackedDay = AddTrackedDayUsecase(
      TrackedDayRepository(TrackedDayDataSource(db)),
    );
    await addTrackedDay.addNewTrackedDay(day, 2000, 250, 70, 100);
    await addTrackedDay.addDayCaloriesTracked(day, 740);

    final edited = customMeal(code: '4006381333931', name: 'Oats', kcal: 370);
    await bloc.saveCustomMeal(edited, previous: oats);
    // The move leaves the day's totals as they were.
    expect(trackedDayBox.values.single.caloriesTracked, 740);

    final intakeRepository = IntakeRepository(IntakeDataSource(db));
    final customMealsBloc = CustomMealsBloc(
      CustomMealDataSource(db),
      GetIntakeUsecase(
        intakeRepository,
        RecipeRepository(RecipeDataSource(db)),
      ),
      DeleteIntakeUsecase(intakeRepository),
      addTrackedDay,
      MergeCustomMealsUseCase(
        CustomMealDataSource(db),
        intakeRepository,
        addTrackedDay,
        favourites,
      ),
      favourites,
    );
    addTearDown(customMealsBloc.close);
    customMealsBloc.add(DeleteCustomMealEvent('4006381333931'));
    await customMealsBloc.stream.firstWhere(
      (state) => state is CustomMealsLoadedState,
    );

    expect(customMealBox.isEmpty, isTrue);
    expect(intakeBox.length, 2);
    expect(trackedDayBox.values.single.caloriesTracked, 740);
  });
}

/// The active profile's boxes come from [FakeHiveDBProvider]; the other
/// profiles' intake boxes are handed out by suffix, the way the real
/// provider opens them on demand.
class _ProfilesHiveDBProvider extends FakeHiveDBProvider {
  final Box<ProfileDBO> _profiles;
  final Map<String, Box<IntakeDBO>> scopedIntakeBoxes;
  final openedScopedBoxes = <(String, String)>[];

  /// Makes the next [openScopedBox] fail, as a disk error would.
  bool failNextScopedOpen = false;
  final closedScopedBoxes = <(String, String)>[];

  _ProfilesHiveDBProvider({
    required Box<ProfileDBO> profiles,
    required Map<String, Box<IntakeDBO>> scopedIntakeBoxes,
    super.customMealBox,
    super.intakeBox,
    super.trackedDayBox,
  }) : _profiles = profiles,
       scopedIntakeBoxes = Map.of(scopedIntakeBoxes),
       super(activeProfileId: 'me');

  @override
  Box<ProfileDBO> get profileBox => _profiles;

  @override
  Future<Box<E>> openScopedBox<E>(String baseName, String boxSuffix) async {
    expect(baseName, HiveDBProvider.intakeBoxName);
    if (failNextScopedOpen) {
      failNextScopedOpen = false;
      throw StateError('cannot open $baseName$boxSuffix');
    }
    openedScopedBoxes.add((baseName, boxSuffix));
    return scopedIntakeBoxes[boxSuffix]! as Box<E>;
  }

  // The test keeps reading the box afterwards, so record the close instead.
  @override
  Future<void> closeScopedBox<E>(String baseName, String boxSuffix) async {
    closedScopedBoxes.add((baseName, boxSuffix));
  }
}

/// Records the favourite moves a Save makes; the delete and merge paths
/// find nothing starred.
class _RecordingFavouriteMealRepository implements FavouriteMealRepository {
  final moves = <(String?, String?)>[];

  @override
  Future<void> moveFavourite(MealEntity previous, MealEntity updated) async =>
      moves.add((previous.code, updated.code));

  @override
  Future<void> keepLatestCustomMealSnapshot(String libraryKey) async {}

  @override
  Future<void> mergeCustomMealFavourite(
    String loserLibraryKey,
    MealDBO winner,
  ) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Unexpected call: ${invocation.memberName}');
}

class _FakeGetConfigUsecase implements GetConfigUsecase {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Unexpected call: ${invocation.memberName}');
}

class _FakeConfigRepository implements ConfigRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Unexpected call: ${invocation.memberName}');
}
