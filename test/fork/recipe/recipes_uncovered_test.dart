import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:opennutritracker/core/data/data_source/custom_meal_data_source.dart';
import 'package:opennutritracker/core/data/dbo/meal_dbo.dart';
import 'package:opennutritracker/core/data/repository/favourite_meal_repository.dart';
import 'package:opennutritracker/core/data/repository/recipe_repository.dart';
import 'package:opennutritracker/core/domain/entity/app_theme_entity.dart';
import 'package:opennutritracker/core/domain/entity/config_entity.dart';
import 'package:opennutritracker/core/domain/entity/recipe_entity.dart';
import 'package:opennutritracker/core/domain/usecase/add_tracked_day_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/delete_intake_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/delete_recipe_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_all_recipes_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_intake_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/merge_custom_meals_usecase.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/app_theme.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/features/recipes/presentation/bloc/recipes_bloc.dart';
import 'package:opennutritracker/features/recipes/presentation/screens/recipes_page.dart';
import 'package:opennutritracker/features/settings/presentation/bloc/custom_meals_bloc.dart';
import 'package:opennutritracker/fork/display/contrast.dart';
import 'package:opennutritracker/fork/recipe/recipe_builder.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:provider/provider.dart';

import '../../helpers/test_l10n.dart';

// The recipes audit of 2026-11-22: selection mode says which recipes are
// selected, its bar reads with a picked accent, and the builder's macro
// figures reach 4.5:1.

const _yellow = Color(0xFFFDD835);

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
  List<RecipeEntity> getAllRecipes() => [
    _bowl,
    RecipeEntity(
      id: 's',
      name: 'Soup',
      description: null,
      ingredients: const [],
      totalWeightG: 400,
      aggregatedNutrimentsPer100: _per100,
      createdAt: DateTime(2026, 11, 1),
      updatedAt: DateTime(2026, 11, 2),
      servingsCount: 2,
    ),
  ];
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

void main() {
  final getIt = GetIt.instance;
  final p = AppPalette.light.withAccent(_yellow);
  tearDown(() => getIt.reset());

  Future<void> pump(WidgetTester tester, Widget home) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider<EnergyUnitProvider>(
        create: (_) => EnergyUnitProvider(),
        child: MaterialApp(
          theme: buildAppTheme(p),
          localizationsDelegates: const [S.delegate],
          supportedLocales: S.supportedLocales,
          home: home,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> pumpRecipes(WidgetTester tester) async {
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
  }

  testWidgets('in selection mode a recipe says it is selected, and what a '
      'tap does', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpRecipes(tester);
    await tester.longPress(find.text('Oat Bowl'));
    await tester.pumpAndSettle();
    expect(
      tester.getSemantics(find.text('Oat Bowl')),
      isSemantics(
        hasSelectedState: true,
        isSelected: true,
        hasTapAction: true,
        onTapHint: 'Deselect',
      ),
    );
    expect(find.bySemanticsLabel(RegExp('Selected')), findsWidgets);

    expect(
      tester.getSemantics(find.text('Soup')),
      isSemantics(
        hasSelectedState: true,
        isSelected: false,
        onTapHint: 'Select',
      ),
    );
    semantics.dispose();
  });

  testWidgets('the selection bar reads with a yellow accent', (tester) async {
    await pumpRecipes(tester);
    await tester.longPress(find.text('Oat Bowl'));
    await tester.pumpAndSettle();
    final tint = Color.alphaBlend(_yellow.withValues(alpha: 0.12), p.canvas);
    final count = tester.widget<Text>(find.text(l10nEn.selectionCountLabel(1)));
    expect(contrastRatio(count.style!.color!, tint), greaterThanOrEqualTo(4.5));
    for (final icon in [Icons.close_rounded, Icons.delete_outline_rounded]) {
      expect(
        contrastRatio(tester.widget<Icon>(find.byIcon(icon)).color!, tint),
        greaterThanOrEqualTo(3),
        reason: '$icon',
      );
    }
  });

  testWidgets("the builder's macro figures read at 4.5:1 on the card", (
    tester,
  ) async {
    await pump(
      tester,
      Scaffold(
        bottomNavigationBar: BuilderSaveBar(
          per100: _per100,
          totalWeightG: 400,
          saving: false,
          onSave: () {},
        ),
      ),
    );
    // carbs 80 g, fat 20 g, protein 40 g
    for (final figure in ['80', '20', '40']) {
      expect(
        contrastRatio(
          tester.widget<Text>(find.text(figure)).style!.color!,
          AppPalette.light.surface,
        ),
        greaterThanOrEqualTo(4.5),
        reason: figure,
      );
    }
  });
}
