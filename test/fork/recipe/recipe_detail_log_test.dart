import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/domain/entity/recipe_entity.dart';
import 'package:opennutritracker/core/domain/entity/recipe_ingredient_entity.dart';
import 'package:opennutritracker/core/domain/entity/app_theme_entity.dart';
import 'package:opennutritracker/core/domain/entity/config_entity.dart';
import 'package:opennutritracker/core/domain/usecase/delete_recipe_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_recipe_by_id_usecase.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/core/utils/navigation_options.dart';
import 'package:opennutritracker/features/meal_detail/meal_detail_screen.dart';
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

class _Config extends Fake implements GetConfigUsecase {
  @override
  Future<ConfigEntity> getConfig() async =>
      const ConfigEntity(true, true, false, AppThemeEntity.system);
}

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
  final pushed = <RouteSettings>[];

  setUp(() {
    pushed.clear();
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
        onGenerateRoute: (settings) {
          if (settings.name != '/') {
            pushed.add(settings);
            // the builder saves a copy as 'copy-id'
            return MaterialPageRoute(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => Navigator.of(context).pop('copy-id'),
                  child: const Text('save copy'),
                ),
              ),
            );
          }
          return MaterialPageRoute(
            settings: RouteSettings(
              arguments: const RecipeDetailArguments(
                recipeId: 'r',
                meal: IntakeTypeEntity.dinner,
              ),
            ),
            builder: (_) => const RecipeDetailScreen(),
          );
        },
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Add logs the portion picked to the meal picked, once', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.byTooltip('More servings'));
    await tester.pump();
    await tester.tap(find.text('Dinner').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lunch').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('recipe-log')));
    await tester.pump();
    // The write is still running: a second tap adds nothing.
    await tester.tap(
      find.byKey(const ValueKey('recipe-log')),
      warnIfMissed: false,
    );
    await tester.pump();
    expect(log.calls, [('g', '150.0', IntakeTypeEntity.lunch)]);
  });

  // G3-7: Log another amount logs to the meal the page has picked; no
  // second meal sheet repeats the footer's chip
  testWidgets('Log another amount opens the food page for the meal picked', (
    tester,
  ) async {
    locator.registerSingleton<GetConfigUsecase>(_Config());
    await pump(tester);
    await tester.tap(find.byIcon(Icons.more_vert_rounded));
    await tester.pumpAndSettle();
    // The test font's square glyphs overflow "Log another amount"'s row
    tester.takeException();
    await tester.tap(find.text('Log another amount'));
    await tester.pumpAndSettle();
    expect(find.text('Breakfast'), findsNothing, reason: 'no meal sheet');
    final args = pushed.single.arguments as MealDetailScreenArguments;
    expect(pushed.single.name, NavigationOptions.mealDetailRoute);
    expect(args.intakeTypeEntity, IntakeTypeEntity.dinner);
  });

  // G3-7: Duplicate, then Save, says the copy is saved and opens it
  testWidgets('a saved duplicate says so and opens the copy', (tester) async {
    locator.registerSingleton<GetConfigUsecase>(_Config());
    await pump(tester);
    await tester.tap(find.byIcon(Icons.more_vert_rounded));
    await tester.pumpAndSettle();
    tester.takeException();
    await tester.tap(find.text('Duplicate'));
    await tester.pumpAndSettle();
    expect(pushed.single.name, NavigationOptions.recipeBuilderRoute);
    await tester.tap(find.text('save copy'));
    await tester.pumpAndSettle();
    expect(find.text('Copy saved'), findsOneWidget);

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(pushed.last.name, NavigationOptions.recipeDetailRoute);
    expect(
      (pushed.last.arguments as RecipeDetailArguments).recipeId,
      'copy-id',
    );
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
