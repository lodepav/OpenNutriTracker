import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:opennutritracker/core/data/repository/recipe_repository.dart';
import 'package:opennutritracker/core/domain/entity/recipe_entity.dart';
import 'package:opennutritracker/core/domain/entity/recipe_ingredient_entity.dart';
import 'package:opennutritracker/core/domain/usecase/compute_recipe_nutrition_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/save_recipe_usecase.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/features/recipes/presentation/bloc/recipe_builder_bloc.dart';
import 'package:opennutritracker/features/recipes/presentation/screens/recipe_builder_screen.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:provider/provider.dart';

// S564: a saved duplicate gets its own id, and the builder hands it back
// to the page that opened it.

// Energy that matches the macros, or Save asks about it first
const _per100 = MealNutrimentsEntity(
  energyKcal100: 165,
  carbohydrates100: 20,
  fat100: 5,
  proteins100: 10,
  sugars100: null,
  saturatedFat100: null,
  fiber100: null,
);

final _oats = MealEntity(
  code: 'oats',
  name: 'Oats',
  url: null,
  mealQuantity: '100',
  mealUnit: 'g',
  servingQuantity: null,
  servingUnit: null,
  servingSize: null,
  nutriments: _per100,
  source: MealSourceEntity.custom,
);

/// As Duplicate opens it: the empty id is the sentinel for a new recipe.
final _copy = RecipeEntity(
  id: '',
  name: 'Oat Bowl (copy)',
  description: null,
  ingredients: [
    RecipeIngredientEntity(
      snapshotMeal: _oats,
      amount: 200,
      unit: 'g',
      convertedAmountG: 200,
    ),
  ],
  totalWeightG: 200,
  aggregatedNutrimentsPer100: _per100,
  createdAt: DateTime(2026, 11, 1),
  updatedAt: DateTime(2026, 11, 1),
  servingsCount: 1,
);

class _Recipes extends Fake implements RecipeRepository {
  final saved = <RecipeEntity>[];

  @override
  Future<void> saveRecipe(RecipeEntity recipe) async => saved.add(recipe);
}

void main() {
  late _Recipes recipes;
  late ComputeRecipeNutritionUseCase compute;

  setUp(() {
    recipes = _Recipes();
    compute = ComputeRecipeNutritionUseCase();
  });

  tearDown(GetIt.instance.reset);

  test('saving a duplicate sets the id it was saved under', () async {
    final bloc = RecipeBuilderBloc(
      compute,
      SaveRecipeUseCase(recipes, compute),
    );
    addTearDown(bloc.close);
    bloc.add(InitializeBuilderEvent(existing: _copy));
    await Future<void>.delayed(Duration.zero);
    expect(bloc.state.id, isNull);

    bloc.add(const SaveRecipeEvent());
    await Future<void>.delayed(Duration.zero);

    expect(bloc.state.didSave, isTrue);
    expect(recipes.saved.single.id, isNotEmpty);
    expect(bloc.state.id, recipes.saved.single.id);
  });

  testWidgets('the builder pops with the saved recipe\'s id', (tester) async {
    GetIt.instance.registerFactory<RecipeBuilderBloc>(
      () => RecipeBuilderBloc(compute, SaveRecipeUseCase(recipes, compute)),
    );
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider<EnergyUnitProvider>(
        create: (_) => EnergyUnitProvider(),
        child: MaterialApp(
          localizationsDelegates: const [S.delegate],
          supportedLocales: S.supportedLocales,
          home: const Scaffold(),
        ),
      ),
    );
    final popped = tester
        .state<NavigatorState>(find.byType(Navigator))
        .push(
          MaterialPageRoute<Object?>(
            settings: RouteSettings(
              arguments: RecipeBuilderArguments(existing: _copy),
            ),
            builder: (_) => const RecipeBuilderScreen(),
          ),
        );
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsIdentifier('recipe-builder-save'));
    await tester.pumpAndSettle();

    expect(find.byType(RecipeBuilderScreen), findsNothing);
    expect(await popped, recipes.saved.single.id);
  });
}
