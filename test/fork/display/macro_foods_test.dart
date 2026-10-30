import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/fork/display/macro_foods.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:provider/provider.dart';

import '../../fixture/intake_entity_fixtures.dart';

// Seam S124: the foods behind a total, with a switch between them.

Future<void> _pump(
  WidgetTester tester, {
  required List<IntakeEntity> intakes,
  FoodsMetric initial = FoodsMetric.protein,
  Map<FoodsMetric, FoodsTotal> totals = const {},
  bool kj = false,
}) => tester.pumpWidget(
  ChangeNotifierProvider(
    create: (_) => EnergyUnitProvider(usesKilojoules: kj),
    child: MaterialApp(
      localizationsDelegates: const [
        S.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: S.supportedLocales,
      home: MacroFoodsPage(
        initial: initial,
        intakes: intakes,
        totals: totals,
        day: DateTime(2026, 10, 25),
      ),
    ),
  ),
);

double _top(WidgetTester tester, String text) =>
    tester.getTopLeft(find.text(text)).dy;

void main() {
  final oats = intakeOf('Oats', 80, protein100: 13, carbs100: 60);
  final chicken = intakeOf(
    'Chicken breast',
    150,
    protein100: 23,
    type: IntakeTypeEntity.dinner,
  );
  final apple = intakeOf('Apple', 150, carbs100: 12);

  testWidgets('a macro: its total against its goal, then each food', (
    tester,
  ) async {
    await _pump(
      tester,
      intakes: [oats, chicken, apple],
      totals: {FoodsMetric.protein: (eaten: 45, goal: 93)},
    );
    expect(find.text('45'), findsOneWidget);
    expect(find.text('of 93 g protein'), findsOneWidget);
    expect(find.text('48 g left'), findsOneWidget);
    // Chicken 34.5 g, oats 10.4 g, the apple none.
    expect(find.text('35 g'), findsOneWidget);
    expect(find.text('77%'), findsOneWidget);
    expect(find.text('10 g'), findsOneWidget);
    expect(find.text('23%'), findsOneWidget);
    expect(find.text('Apple'), findsNothing);
    expect(_top(tester, 'Chicken breast'), lessThan(_top(tester, 'Oats')));
    expect(find.text('Dinner'), findsOneWidget);
  });

  testWidgets('over the goal says so', (tester) async {
    await _pump(
      tester,
      intakes: [chicken],
      totals: {FoodsMetric.protein: (eaten: 120, goal: 100)},
    );
    expect(find.textContaining('over'), findsOneWidget);
    expect(find.textContaining('left'), findsNothing);
  });

  testWidgets('the switch moves to another total and its foods', (
    tester,
  ) async {
    await _pump(
      tester,
      intakes: [oats, chicken, apple],
      totals: {
        FoodsMetric.protein: (eaten: 45, goal: 93),
        FoodsMetric.carbs: (eaten: 66, goal: 250),
      },
    );
    await tester.tap(find.text('Carbs'));
    await tester.pumpAndSettle();
    expect(find.text('of 250 g carbs'), findsOneWidget);
    // Oats 48 g, the apple 18 g, the chicken none.
    expect(find.text('Chicken breast'), findsNothing);
    expect(_top(tester, 'Oats'), lessThan(_top(tester, 'Apple')));
    expect(find.text('73%'), findsOneWidget);
  });

  testWidgets('energy, in kJ when kJ is chosen', (tester) async {
    // 100 kcal per 100 g: 150 g of chicken is 150 kcal, 628 kJ.
    await _pump(
      tester,
      intakes: [chicken, oats],
      initial: FoodsMetric.energy,
      totals: {FoodsMetric.energy: (eaten: 230, goal: 2000)},
      kj: true,
    );
    expect(find.text('962'), findsOneWidget);
    expect(find.text('of 8368 kJ'), findsOneWidget);
    expect(find.text('628 kJ'), findsOneWidget);
    expect(find.text('65%'), findsOneWidget);
  });

  testWidgets('a total not passed in is summed, with no goal', (tester) async {
    await _pump(tester, intakes: [oats, chicken], initial: FoodsMetric.carbs);
    expect(find.text('48'), findsOneWidget);
    expect(find.text('g carbs'), findsOneWidget);
    expect(find.textContaining('left'), findsNothing);
  });

  test('the same food in two meals is one share', () {
    final again = intakeOf('Oats', 40, protein100: 13);
    final shares = FoodShare.of([
      oats,
      intakeOf('Oats', 40, protein100: 13, type: IntakeTypeEntity.dinner),
      again,
    ], FoodsMetric.protein);
    expect(shares.single.value, closeTo(20.8, 1e-9));
    expect(shares.single.meals, [
      IntakeTypeEntity.lunch,
      IntakeTypeEntity.dinner,
    ]);
  });
}
