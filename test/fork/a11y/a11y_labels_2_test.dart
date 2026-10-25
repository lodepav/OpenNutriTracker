import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:provider/provider.dart';
import 'package:opennutritracker/core/domain/entity/recipe_ingredient_entity.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/features/recipes/presentation/widgets/ingredient_list_item.dart';

// Seam S92: an ingredient's remove button is named, and its name wraps at
// 200% text rather than losing what tells foods apart.

const _name = 'Chickpeas, mature seeds, cooked, boiled, without salt, drained';

void main() {
  testWidgets('an ingredient row names its remove button and wraps', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => EnergyUnitProvider(usesKilojoules: false),
        child: MaterialApp(
          localizationsDelegates: const [
            S.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: S.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: Scaffold(
            body: IngredientListItem(
              ingredient: RecipeIngredientEntity(
                snapshotMeal: MealEntity(
                  code: 'c',
                  name: _name,
                  url: null,
                  mealQuantity: null,
                  mealUnit: 'g',
                  servingQuantity: null,
                  servingUnit: 'g',
                  servingSize: null,
                  nutriments: MealNutrimentsEntity.empty(),
                  source: MealSourceEntity.custom,
                ),
                amount: 120,
                unit: 'g',
                convertedAmountG: 120,
              ),
              onRemove: () {},
            ),
          ),
        ),
      ),
    );

    expect(find.byTooltip('Remove ingredient'), findsOneWidget);
    final name = tester.widget<Text>(find.text(_name));
    expect(name.maxLines, greaterThan(1));
    expect(tester.takeException(), isNull);
  });
}
