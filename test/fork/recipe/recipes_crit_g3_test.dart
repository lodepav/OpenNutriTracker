import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:get_it/get_it.dart';
import 'package:opennutritracker/core/data/data_source/custom_meal_data_source.dart';
import 'package:opennutritracker/core/data/dbo/meal_dbo.dart';
import 'package:opennutritracker/core/data/repository/favourite_meal_repository.dart';
import 'package:opennutritracker/core/data/repository/recipe_repository.dart';
import 'package:opennutritracker/core/domain/entity/app_theme_entity.dart';
import 'package:opennutritracker/core/domain/entity/config_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/core/domain/entity/profile_entity.dart';
import 'package:opennutritracker/core/domain/entity/recipe_entity.dart';
import 'package:opennutritracker/core/domain/usecase/add_tracked_day_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/delete_intake_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/delete_recipe_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_all_recipes_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_intake_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_profiles_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/merge_custom_meals_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/send_intake_to_profiles_usecase.dart';
import 'package:opennutritracker/core/presentation/widgets/copy_to_profile_sheet.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/features/recipes/presentation/bloc/recipes_bloc.dart';
import 'package:opennutritracker/features/recipes/presentation/screens/recipes_page.dart';
import 'package:opennutritracker/features/settings/presentation/bloc/custom_meals_bloc.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:provider/provider.dart';

import '../../helpers/test_l10n.dart';

// G3 critique: a search with no hits says so and offers to clear it; Copy to
// profile says why Copy is off, and a failed copy says so and lets go of
// the spinner.

const _per100 = MealNutrimentsEntity(
  energyKcal100: 150,
  carbohydrates100: 20,
  fat100: 5,
  proteins100: 10,
  sugars100: null,
  saturatedFat100: null,
  fiber100: null,
);

final _bowl = RecipeEntity(
  id: 'r',
  name: 'Oat Bowl',
  description: null,
  ingredients: const [],
  totalWeightG: 400,
  aggregatedNutrimentsPer100: _per100,
  createdAt: DateTime(2026, 11, 1),
  updatedAt: DateTime(2026, 11, 2),
  servingsCount: 2,
);

class _Recipes extends Fake implements RecipeRepository {
  @override
  List<RecipeEntity> getAllRecipes() => [_bowl];
}

class _Library extends Fake implements CustomMealDataSource {
  @override
  List<MealDBO> getAllCustomMeals() => [];
}

class _Favourites extends Fake implements FavouriteMealRepository {}

class _Config extends Fake implements GetConfigUsecase {
  @override
  Future<ConfigEntity> getConfig() async =>
      const ConfigEntity(true, true, false, AppThemeEntity.system);
}

class _Intakes extends Fake implements GetIntakeUsecase {}

class _DeleteIntake extends Fake implements DeleteIntakeUsecase {}

class _Tracked extends Fake implements AddTrackedDayUsecase {}

class _Merge extends Fake implements MergeCustomMealsUseCase {}

class _DeleteRecipe extends Fake implements DeleteRecipeUseCase {}

class _CacheManager extends Fake implements CacheManager {}

class _Profiles extends Fake implements GetProfilesUsecase {
  @override
  String get activeProfileId => 'a';

  @override
  List<ProfileEntity> getProfiles() => [
    ProfileEntity(
      id: 'a',
      name: 'Alex',
      createdAt: DateTime(2026),
      boxSuffix: '',
    ),
    ProfileEntity(
      id: 'b',
      name: 'Sam',
      createdAt: DateTime(2026),
      boxSuffix: '_b',
    ),
  ];
}

class _FailingCopy extends Fake implements SendIntakeToProfilesUsecase {
  var calls = 0;

  @override
  Future<void> copyToProfiles(
    List<IntakeEntity> intakes,
    List<ProfileEntity> targets,
  ) async {
    calls++;
    throw StateError('disk full');
  }
}

class _Copy extends Fake implements SendIntakeToProfilesUsecase {
  @override
  Future<void> copyToProfiles(
    List<IntakeEntity> intakes,
    List<ProfileEntity> targets,
  ) async {}
}

void main() {
  final getIt = GetIt.instance;
  tearDown(() => getIt.reset());

  Future<void> pump(WidgetTester tester, Widget home) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider<EnergyUnitProvider>(
        create: (_) => EnergyUnitProvider(),
        child: MaterialApp(
          localizationsDelegates: const [S.delegate],
          supportedLocales: S.supportedLocales,
          home: home,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a search with no hits says no recipes match, and Clear '
      'filters brings the list back', (tester) async {
    final library = _Library();
    getIt
      ..registerLazySingleton<RecipesBloc>(
        () => RecipesBloc(GetAllRecipesUseCase(_Recipes())),
      )
      ..registerSingleton<CustomMealDataSource>(library)
      ..registerLazySingleton<CustomMealsBloc>(
        () => CustomMealsBloc(
          library,
          _Intakes(),
          _DeleteIntake(),
          _Tracked(),
          _Merge(),
          _Favourites(),
        ),
      )
      ..registerSingleton<GetConfigUsecase>(_Config())
      ..registerSingleton<DeleteRecipeUseCase>(_DeleteRecipe())
      ..registerSingleton<CacheManager>(_CacheManager());
    await pump(tester, const RecipesPage());

    await tester.enterText(find.byType(TextField).first, 'pizza');
    await tester.pumpAndSettle();
    expect(find.text('No recipes match'), findsOneWidget);
    expect(find.text(l10nEn.recipesEmptyLabel), findsNothing);
    expect(find.byTooltip('Clear search'), findsOneWidget);

    await tester.tap(find.text('Clear filters'));
    await tester.pumpAndSettle();
    expect(find.text('Oat Bowl'), findsOneWidget);
    expect(find.text('No recipes match'), findsNothing);
  });

  testWidgets('Copy to profile says to pick one, and a failed copy says so '
      'and can be tried again', (tester) async {
    final copy = _FailingCopy();
    getIt
      ..registerSingleton<GetProfilesUsecase>(_Profiles())
      ..registerSingleton<SendIntakeToProfilesUsecase>(copy);
    await pump(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showCopyToProfileSheet(context, const []),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Pick a profile to copy to'), findsOneWidget);
    await tester.tap(find.text('Sam'));
    await tester.pumpAndSettle();
    expect(find.text('Pick a profile to copy to'), findsNothing);

    final confirm = find.descendant(
      of: find.bySemanticsIdentifier('copy-to-profile-confirm'),
      matching: find.byType(FilledButton),
    );
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(find.text('Could not copy. Try again.'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);

    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(copy.calls, 2);
  });

  // G3-7: the sheet says what is copied and to which day, and the snackbar
  // names the profile
  testWidgets('Copy to profile names the meal, the day and the profile', (
    tester,
  ) async {
    await initializeDateFormatting('en');
    getIt
      ..registerSingleton<GetProfilesUsecase>(_Profiles())
      ..registerSingleton<SendIntakeToProfilesUsecase>(_Copy());
    final intake = IntakeEntity(
      id: 'i',
      unit: 'g',
      amount: 100,
      type: IntakeTypeEntity.breakfast,
      meal: MealEntity(
        code: 'oats',
        name: 'Oats',
        url: null,
        mealQuantity: null,
        mealUnit: 'g',
        servingQuantity: null,
        servingUnit: null,
        servingSize: null,
        nutriments: MealNutrimentsEntity.empty(),
        source: MealSourceEntity.custom,
      ),
      dateTime: DateTime(2026, 11, 21, 8),
    );
    await pump(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showCopyToProfileSheet(context, [intake]),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(
      find.text('Breakfast of Sat, Nov 21, to the same day'),
      findsOneWidget,
    );

    await tester.tap(find.text('Sam'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsIdentifier('copy-to-profile-confirm'));
    await tester.pumpAndSettle();
    expect(find.text('Copied to Sam'), findsOneWidget);
  });
}
