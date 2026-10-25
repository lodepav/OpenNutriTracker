import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/domain/entity/recipe_entity.dart';
import 'package:opennutritracker/core/domain/entity/recipe_ingredient_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/fork/recipe/recipe_page.dart';
import 'package:opennutritracker/generated/l10n.dart';

// Seam S126: the recipe page logs a portion chosen with a stepper, and
// lists each ingredient with its kind and macros.

MealNutrimentsEntity _per100(double kcal, double c, double f, double p) =>
    MealNutrimentsEntity(
      energyKcal100: kcal,
      carbohydrates100: c,
      fat100: f,
      proteins100: p,
      sugars100: null,
      saturatedFat100: null,
      fiber100: null,
    );

RecipeEntity _recipe({int? servings}) => RecipeEntity(
  id: 'r',
  name: 'Morning Oat Bowl',
  description: null,
  ingredients: [
    RecipeIngredientEntity(
      snapshotMeal: MealEntity(
        code: 'b',
        name: 'Banana',
        url: null,
        mealQuantity: null,
        mealUnit: 'g',
        servingQuantity: null,
        servingUnit: 'g',
        servingSize: null,
        nutriments: _per100(89, 23, 0.3, 1.1),
        source: MealSourceEntity.fdc,
      ),
      amount: 100,
      unit: 'g',
      convertedAmountG: 100,
    ),
  ],
  totalWeightG: 400,
  aggregatedNutrimentsPer100: _per100(150, 20, 5, 4),
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  servingsCount: servings,
);

Widget _app(Widget child) => MaterialApp(
  localizationsDelegates: const [
    S.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ],
  supportedLocales: S.supportedLocales,
  home: Scaffold(body: child),
);

void main() {
  test('a portion is a serving when the recipe has servings', () {
    final r = _recipe(servings: 4);
    expect(RecipePortion(r, 1).grams, 100);
    expect(RecipePortion(r, 1).label, '1 serving');
    expect(RecipePortion(r, 1.5).grams, 150);
    expect(RecipePortion(r, 1.5).label, '1½ servings');
  });

  test('else a portion is the whole recipe', () {
    final r = _recipe();
    expect(RecipePortion(r, 0.5).grams, 200);
    expect(RecipePortion(r, 0.5).label, '½ recipe');
    expect(RecipePortion(r, 2).label, '2 recipes');
  });

  testWidgets('the totals and Log follow the portion; Less stops at a half', (
    tester,
  ) async {
    final r = _recipe(servings: 4);
    var count = 1.0;
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) => _app(
          Column(
            children: [
              RecipeTotalsStrip(portion: RecipePortion(r, count)),
              RecipeLogBar(
                portion: RecipePortion(r, count),
                onCount: (c) => setState(() => count = c),
                meal: IntakeTypeEntity.lunch,
                onMeal: (_) {},
                onLog: () {},
              ),
            ],
          ),
        ),
      ),
    );
    // 100 g at 150 kcal per 100 g
    expect(find.text('Add 150 kcal to Lunch'), findsOneWidget);
    expect(find.text('1 serving, 100 g · per 100 g 150 kcal'), findsOneWidget);

    await tester.tap(find.byTooltip('More'));
    await tester.pump();
    expect(find.text('Add 225 kcal to Lunch'), findsOneWidget);
    expect(find.text('30'), findsOneWidget); // carbs in 150 g

    await tester.tap(find.byTooltip('Less'));
    await tester.pump();
    await tester.tap(find.byTooltip('Less'));
    await tester.pump();
    expect(find.text('½ serving'), findsOneWidget);
    final less = tester.widget<IconButton>(
      find.ancestor(
        of: find.byIcon(Icons.remove_rounded),
        matching: find.byType(IconButton),
      ),
    );
    expect(less.onPressed, isNull);
  });

  testWidgets('an ingredient shows its kind, macros, energy and amount', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(RecipeIngredientRow(ingredient: _recipe().ingredients.single)),
    );
    expect(find.text('🍌'), findsOneWidget);
    expect(find.text('89 kcal'), findsOneWidget);
    expect(find.text('100 g'), findsOneWidget);
    expect(
      find.textContaining(RegExp(r'C 23 · F 0 · P 1|P 1 · F 0 · C 23')),
      findsOneWidget,
    );
  });
}
