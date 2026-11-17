import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/fork/display/display_prefs.dart';
import 'package:opennutritracker/fork/display/meal_macros_line.dart';

MealEntity _meal({double? kcal = 120.4, String unit = 'g'}) => MealEntity(
  code: 'x',
  name: 'Yogurt',
  url: null,
  mealQuantity: null,
  mealUnit: unit,
  servingQuantity: null,
  servingUnit: unit,
  servingSize: null,
  nutriments: MealNutrimentsEntity(
    energyKcal100: kcal,
    carbohydrates100: 20.4,
    fat100: 3.2,
    proteins100: null,
    sugars100: null,
    saturatedFat100: null,
    fiber100: null,
  ),
  source: MealSourceEntity.custom,
);

Future<void> _pump(WidgetTester tester, MealEntity meal) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(body: MealMacrosLine(meal: meal)),
  ),
);

void main() {
  tearDown(() => DisplayPrefs.macroOrder.value = DisplayPrefs.upstreamOrder);

  testWidgets('energy, then the macros in the user\'s order, per 100 g', (
    tester,
  ) async {
    DisplayPrefs.macroOrder.value = [Macro.protein, Macro.fat, Macro.carbs];
    await _pump(tester, _meal());

    expect(
      find.text(
        '120 kcal · P\u00a0– · F\u00a03 · C\u00a020 per 100\u00a0g',
      ),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(
        '120 kcal, – grams protein, 3 grams fat, 20 grams carbs, per 100 g',
      ),
      findsOneWidget,
    );
  });

  testWidgets('a drink is per 100 ml', (tester) async {
    await _pump(tester, _meal(unit: 'ml'));

    expect(find.textContaining('per 100\u00a0ml'), findsOneWidget);
  });

  testWidgets('nothing without energy', (tester) async {
    await _pump(tester, _meal(kcal: null));

    expect(find.byType(Text), findsNothing);
  });

  testWidgets('a source wraps between its words at a large font', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MacrosLine(
            carbs: 0,
            fat: 21,
            protein: 26,
            tail: '· FDC Survey',
          ),
        ),
      ),
    );
    expect(find.textContaining(' · FDC Survey'), findsOneWidget);
  });
}
