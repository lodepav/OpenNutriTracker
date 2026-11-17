import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/fork/meal_detail/nutrients_table.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:provider/provider.dart';

MealEntity _food({
  String unit = 'g',
  double? fat = 20.8,
  String? servingUnit = 'g',
}) => MealEntity(
  code: 'table',
  name: 'Cheese',
  url: null,
  mealQuantity: null,
  mealUnit: unit,
  servingQuantity: 30,
  servingUnit: servingUnit,
  servingSize: null,
  nutriments: MealNutrimentsEntity(
    energyKcal100: 402,
    carbohydrates100: 25.73,
    fat100: fat,
    proteins100: 4.56,
    sugars100: 0,
    saturatedFat100: 0.02,
    fiber100: 9.96,
  ),
  source: MealSourceEntity.custom,
);

Future<void> _pump(
  WidgetTester tester,
  MealEntity meal, {
  bool imperial = false,
}) => tester.pumpWidget(
  ChangeNotifierProvider(
    create: (_) => EnergyUnitProvider(usesKilojoules: false),
    child: MaterialApp(
      localizationsDelegates: const [S.delegate],
      supportedLocales: S.supportedLocales,
      home: Scaffold(
        body: SingleChildScrollView(
          child: FoodNutrientsTable(
            product: meal,
            usesImperialUnits: imperial,
            servingQuantity: meal.servingQuantity,
            servingUnit: meal.servingUnit,
          ),
        ),
      ),
    ),
  ),
);

void main() {
  group('nutrientAmountText', () {
    test('whole from 10 up, one decimal under it', () {
      expect(nutrientAmountText(25.73, 'g'), '26 g');
      expect(nutrientAmountText(20.8, 'g'), '21 g');
      expect(nutrientAmountText(10, 'g'), '10 g');
      expect(nutrientAmountText(9.96, 'g'), '10 g');
      expect(nutrientAmountText(4.56, 'g'), '4.6 g');
      expect(nutrientAmountText(4.56, 'mg'), '4.6 mg');
    });

    test('mg and µg keep two decimals under 1', () {
      expect(nutrientAmountText(0.04, 'µg'), '0.04 µg');
      expect(nutrientAmountText(0.3, 'mg'), '0.3 mg');
      expect(nutrientAmountText(0.256, 'mg'), '0.26 mg');
      expect(nutrientAmountText(0.002, 'µg'), '<0.01 µg');
      expect(nutrientAmountText(0, 'mg'), '0 mg');
      expect(nutrientAmountText(0.04, 'g'), '<0.1 g');
    });

    test('a whole tenth drops its ".0"', () {
      expect(nutrientAmountText(0, 'g'), '0 g');
      expect(nutrientAmountText(4.0, 'g'), '4 g');
      expect(nutrientAmountText(1.04, 'µg'), '1 µg');
      expect(nutrientAmountText(0.995, 'mg'), '1 mg');
    });

    test('a trace is not shown as none', () {
      expect(nutrientAmountText(0.02, 'g'), '<0.1 g');
      expect(nutrientAmountText(0.05, 'g'), '0.1 g');
    });
  });

  test('nutrientName capitalises the first letter only', () {
    expect(nutrientName('saturated fat'), 'Saturated fat');
    expect(nutrientName('niacin (B3)'), 'Niacin (B3)');
    expect(nutrientName(''), '');
  });

  testWidgets('rows read in words, with a space before the unit', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester, _food());

    expect(find.text('Per 100 g'), findsOneWidget);
    expect(find.text('Nutrition information'), findsOneWidget);
    expect(find.text('Energy'), findsOneWidget);
    expect(find.text('402 kcal'), findsOneWidget);
    expect(find.text('Fat'), findsOneWidget);
    expect(find.text('21 g'), findsOneWidget);
    expect(find.text('Carbohydrate'), findsOneWidget);
    expect(find.text('26 g'), findsOneWidget);
    expect(find.text('4.6 g'), findsOneWidget);
    expect(find.text('0 g'), findsOneWidget);
    expect(find.text('<0.1 g'), findsOneWidget);

    expect(find.bySemanticsLabel('Fat 21 g'), findsOneWidget);
    // set in by padding, not by spaces read aloud
    expect(find.bySemanticsLabel('Saturated fat <0.1 g'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp(r'^\s')), findsNothing);
    expect(find.bySemanticsLabel('Energy 402 kcal'), findsOneWidget);
    // the heading heads the card the table is in
    expect(
      tester.getSemantics(find.text('Nutrition information')),
      isSemantics(label: 'Nutrition information', isHeader: true),
    );
    semantics.dispose();
  });

  testWidgets('a drink is per 100 ml; a missing value is said so', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester, _food(unit: 'ml', fat: null));
    expect(find.text('Per 100 ml'), findsOneWidget);
    expect(find.text('—'), findsOneWidget);
    expect(find.bySemanticsLabel('Fat, not known'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('imperial with a serving: per serving, scaled', (tester) async {
    await _pump(tester, _food(), imperial: true);
    expect(find.text('Per serving (30 g)'), findsOneWidget);
    // 20.8 g a 100 g is 6.24 g in 30 g
    expect(find.text('6.2 g'), findsOneWidget);
  });

  testWidgets('a drink with no serving unit: per serving in ml', (
    tester,
  ) async {
    for (final unit in [null, 'gml']) {
      await _pump(tester, _food(unit: 'ml', servingUnit: unit), imperial: true);
      expect(find.text('Per serving (30 ml)'), findsOneWidget, reason: unit);
    }
  });
}
