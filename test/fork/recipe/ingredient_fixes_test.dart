import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/recipe_ingredient_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/features/recipes/presentation/widgets/ingredient_quantity_dialog.dart';
import 'package:opennutritracker/fork/recipe/recipe_page.dart';
import 'package:opennutritracker/generated/l10n.dart';

// Seam S300 and the shared ingredient emoji: the amount sheet prefills a
// serving and previews the typed amount; the recipe page draws an
// ingredient as the builder does.

MealEntity _banana({
  MealSourceEntity source = MealSourceEntity.fdc,
  double? servingQuantity,
}) => MealEntity(
  code: 'b',
  name: 'Banana',
  url: null,
  mealQuantity: null,
  mealUnit: 'g',
  servingQuantity: servingQuantity,
  servingUnit: 'g',
  servingSize: null,
  nutriments: MealNutrimentsEntity(
    energyKcal100: 89,
    carbohydrates100: 23,
    fat100: 0.3,
    proteins100: 1.1,
    sugars100: null,
    saturatedFat100: null,
    fiber100: null,
  ),
  source: source,
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

Future<void> _openSheet(WidgetTester tester, MealEntity meal) async {
  await tester.pumpWidget(
    _app(
      Builder(
        builder: (context) => ElevatedButton(
          onPressed: () => showIngredientQuantityDialog(context, meal: meal),
          child: const Text('Open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

String _amountText(WidgetTester tester) =>
    tester.widget<TextFormField>(find.byType(TextFormField)).controller!.text;

void main() {
  testWidgets('a custom ingredient shows the emoji the builder shows', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        RecipeIngredientRow(
          ingredient: RecipeIngredientEntity(
            snapshotMeal: _banana(source: MealSourceEntity.custom),
            amount: 100,
            unit: 'g',
            convertedAmountG: 100,
          ),
        ),
      ),
    );
    expect(find.text('🍌'), findsOneWidget);
    expect(find.byIcon(Icons.eco_rounded), findsNothing);
  });

  testWidgets('a food with a serving weight starts at one serving', (
    tester,
  ) async {
    await _openSheet(tester, _banana(servingQuantity: 120));
    expect(_amountText(tester), '1');
    // 120 g at 89 kcal per 100 g
    expect(find.textContaining('107 kcal'), findsOneWidget);
  });

  // G3-12: Add never meets an empty field
  testWidgets('a food without one starts at 100 g, with its preview', (
    tester,
  ) async {
    await _openSheet(tester, _banana());
    expect(_amountText(tester), '100');
    expect(find.textContaining('89 kcal'), findsOneWidget);
  });

  testWidgets('the typed amount shows its energy and macros', (tester) async {
    await _openSheet(tester, _banana());
    await tester.enterText(find.byType(TextFormField), '200');
    await tester.pump();
    final preview = tester.widget<Text>(
      find.byKey(const ValueKey('ingredient-amount-preview')),
    );
    expect(
      preview.textSpan!.toPlainText(includeSemanticsLabels: false),
      startsWith('178 kcal · '),
    );
    expect(find.bySemanticsLabel(RegExp('46 grams carbs')), findsOneWidget);
    // A comma decimal reads as the sheet's Add reads it
    await tester.enterText(find.byType(TextFormField), '50,5');
    await tester.pump();
    expect(find.textContaining('45 kcal'), findsOneWidget);
  });

  // G3-7: the unit menu stays on the screen
  testWidgets('the unit menu opens inside the screen', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    await _openSheet(tester, _banana(servingQuantity: 120));
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    final width = tester.view.physicalSize.width / tester.view.devicePixelRatio;
    final items = find.byType(DropdownMenuItem<String>);
    expect(items, findsWidgets);
    for (var i = 0; i < items.evaluate().length; i++) {
      final rect = tester.getRect(items.at(i));
      expect(rect.right, lessThanOrEqualTo(width), reason: '$rect');
      expect(rect.left, greaterThanOrEqualTo(0));
    }
  });
}
