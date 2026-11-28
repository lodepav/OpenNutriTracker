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

import '../../helpers/ux_checks.dart';

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
    // the bar runs to what was eaten, the goal a tick at 100 of 120
    final tick = tester.getRect(find.byType(PositionedDirectional));
    final bar = tester.getRect(
      find
          .ancestor(
            of: find.byType(PositionedDirectional),
            matching: find.byType(Stack),
          )
          .first,
    );
    expect(tick.center.dx - bar.left, closeTo(bar.width * 100 / 120, 0.5));
    // the part past the goal in a second, paler colour
    final colours = {
      for (final box in tester.widgetList<ColoredBox>(
        find.descendant(
          of: find.byType(ClipRRect).first,
          matching: find.byType(ColoredBox),
        ),
      ))
        box.color,
    };
    expect(colours, hasLength(2));
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('every food\'s bar ends at one place, at ${scale}x', (
      tester,
    ) async {
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await _pump(
        tester,
        intakes: [oats, chicken, intakeOf('Egg', 3, protein100: 13)],
        totals: {FoodsMetric.protein: (eaten: 45, goal: 93)},
      );
      final bars = find.descendant(
        of: find.byType(FoodShareRow),
        matching: find.byType(LinearProgressIndicator),
      );
      expect(bars, findsNWidgets(3));
      final ends = {
        for (var i = 0; i < 3; i++) tester.getRect(bars.at(i)).right,
      };
      // "35 g", "10 g" and "<1 g" took different widths before
      expect(ends, hasLength(1));
      expect(tester.takeException(), isNull);
    });
  }

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

  testWidgets('the page at 200% text: nothing cut, the targets and contrast', (
    tester,
  ) async {
    await checkScreen(
      tester,
      MacroFoodsPage(
        initial: FoodsMetric.protein,
        intakes: [oats, chicken, apple],
        totals: const {},
        day: DateTime(2026, 10, 25),
      ),
    );
  });
}
