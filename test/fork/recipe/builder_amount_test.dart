import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/recipe_ingredient_entity.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/fork/recipe/recipe_builder.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:provider/provider.dart';

// Seam S127: an ingredient amount cleared or 0 says so under the field, and
// Save waits until it is fixed.

const _per100 = MealNutrimentsEntity(
  energyKcal100: 89,
  carbohydrates100: 23,
  fat100: 0.3,
  proteins100: 1.1,
  sugars100: null,
  saturatedFat100: null,
  fiber100: null,
);

final _banana = RecipeIngredientEntity(
  snapshotMeal: MealEntity(
    code: 'b',
    name: 'Banana',
    url: null,
    mealQuantity: null,
    mealUnit: 'g',
    servingQuantity: null,
    servingUnit: 'g',
    servingSize: null,
    nutriments: _per100,
    source: MealSourceEntity.fdc,
  ),
  amount: 100,
  unit: 'g',
  convertedAmountG: 100,
);

void main() {
  testWidgets('a cleared or 0 amount is an error and Save is off', (
    tester,
  ) async {
    final amounts = <double>[];
    var valid = true;
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => EnergyUnitProvider(),
        child: MaterialApp(
          localizationsDelegates: const [
            S.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: S.supportedLocales,
          home: StatefulBuilder(
            builder: (context, setState) => Scaffold(
              body: BuilderIngredientRow(
                ingredient: _banana,
                onAmount: amounts.add,
                onValid: (ok) => setState(() => valid = ok),
                onEdit: () {},
                onRemove: () {},
              ),
              bottomNavigationBar: BuilderSaveBar(
                per100: _per100,
                totalWeightG: 100,
                saving: false,
                canSave: valid,
                onSave: () {},
              ),
            ),
          ),
        ),
      ),
    );
    final field = find.byType(TextField);
    bool saveOn() =>
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed !=
        null;

    for (final text in ['', '0']) {
      await tester.enterText(field, text);
      await tester.pump();
      // the parent rebuilt; the typed text stays
      expect(tester.widget<TextField>(field).controller!.text, text);
      expect(find.text('More than 0'), findsOneWidget, reason: text);
      expect(saveOn(), isFalse, reason: text);
    }
    expect(amounts, isEmpty);

    await tester.enterText(field, '150');
    await tester.pump();
    expect(find.text('More than 0'), findsNothing);
    expect(saveOn(), isTrue);
    expect(amounts, [150]);
  });

  testWidgets('an amount set by the dialog clears the error', (tester) async {
    var ingredient = _banana;
    var valid = true;
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => EnergyUnitProvider(),
        child: MaterialApp(
          localizationsDelegates: const [
            S.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: S.supportedLocales,
          home: StatefulBuilder(
            builder: (context, setState) => Scaffold(
              body: Column(
                children: [
                  BuilderIngredientRow(
                    ingredient: ingredient,
                    onAmount: (_) {},
                    onValid: (ok) => setState(() => valid = ok),
                    onEdit: () {},
                    onRemove: () {},
                  ),
                  // as the amount dialog's answer
                  TextButton(
                    onPressed: () => setState(
                      () => ingredient = RecipeIngredientEntity(
                        snapshotMeal: _banana.snapshotMeal,
                        amount: 200,
                        unit: 'g',
                        convertedAmountG: 200,
                      ),
                    ),
                    child: const Text('dialog'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), '');
    await tester.pump();
    expect(valid, isFalse);

    await tester.tap(find.text('dialog'));
    await tester.pump();
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '200',
    );
    expect(find.text('More than 0'), findsNothing);
    expect(valid, isTrue);
  });
}
