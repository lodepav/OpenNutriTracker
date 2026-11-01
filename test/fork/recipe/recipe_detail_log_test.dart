import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/domain/entity/recipe_entity.dart';
import 'package:opennutritracker/core/domain/entity/recipe_ingredient_entity.dart';
import 'package:opennutritracker/core/domain/usecase/delete_recipe_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_recipe_by_id_usecase.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/features/meal_detail/presentation/bloc/meal_detail_bloc.dart';
import 'package:opennutritracker/features/recipes/presentation/bloc/recipe_detail_bloc.dart';
import 'package:opennutritracker/features/recipes/presentation/screens/recipe_detail_screen.dart';
import 'package:opennutritracker/generated/l10n.dart';

final _oats = MealEntity(
  code: 'o',
  name: 'Oats',
  url: null,
  mealQuantity: null,
  mealUnit: 'g',
  servingQuantity: null,
  servingUnit: 'g',
  servingSize: null,
  nutriments: MealNutrimentsEntity(
    energyKcal100: 400,
    carbohydrates100: 60,
    fat100: 7,
    proteins100: 13,
    sugars100: null,
    saturatedFat100: null,
    fiber100: null,
  ),
  source: MealSourceEntity.custom,
);

final _recipe = RecipeEntity(
  id: 'r',
  name: 'Bowl',
  description: null,
  ingredients: [
    RecipeIngredientEntity(
      snapshotMeal: _oats,
      amount: 100,
      unit: 'g',
      convertedAmountG: 100,
    ),
  ],
  totalWeightG: 100,
  aggregatedNutrimentsPer100: _oats.nutriments,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  servingsCount: 1,
);

class _Get extends Fake implements GetRecipeByIdUseCase {
  @override
  RecipeEntity? getById(String id) => _recipe;
}

class _Delete extends Fake implements DeleteRecipeUseCase {}

class _Log extends Fake implements MealDetailBloc {
  final calls = <(String, String, IntakeTypeEntity)>[];
  Completer<IntakeEntity?> next = Completer();

  @override
  Future<IntakeEntity?> addIntake(
    BuildContext context,
    String unit,
    String amountText,
    IntakeTypeEntity type,
    MealEntity meal,
    DateTime day,
  ) {
    calls.add((unit, amountText, type));
    return next.future;
  }
}

void main() {
  late _Log log;

  setUp(() {
    log = _Log();
    locator
      ..registerFactory<RecipeDetailBloc>(
        () => RecipeDetailBloc(_Get(), _Delete()),
      )
      ..registerSingleton<MealDetailBloc>(log);
  });

  tearDown(locator.reset);

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 2400);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          S.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: S.supportedLocales,
        onGenerateRoute: (settings) => MaterialPageRoute(
          settings: RouteSettings(
            arguments: const RecipeDetailArguments(
              recipeId: 'r',
              meal: IntakeTypeEntity.dinner,
            ),
          ),
          builder: (_) => const RecipeDetailScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Add logs the portion picked to the meal picked, once', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.byKey(const ValueKey('recipe-log')));
    await tester.pump();
    // The write is still running: a second tap adds nothing.
    await tester.tap(
      find.byKey(const ValueKey('recipe-log')),
      warnIfMissed: false,
    );
    await tester.pump();
    expect(log.calls, [('g', '100.0', IntakeTypeEntity.dinner)]);
  });

  testWidgets('a failed write says so and Add works again', (tester) async {
    // In the test's zone, which pump drives.
    log.next = Completer();
    await pump(tester);
    await tester.tap(find.byKey(const ValueKey('recipe-log')));
    await tester.pump();
    expect(log.calls, hasLength(1));
    log.next.completeError(StateError('disk'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text("Not added: it couldn't be saved."), findsOneWidget);
    log.next = Completer();
    await tester.tap(find.byKey(const ValueKey('recipe-log')));
    await tester.pump();
    expect(log.calls, hasLength(2));
  });
}
