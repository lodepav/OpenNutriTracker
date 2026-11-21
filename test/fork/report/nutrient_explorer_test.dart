import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/domain/entity/tracked_day_entity.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/fork/report/goal_standing.dart';
import 'package:opennutritracker/fork/report/nutrient_explorer.dart';
import 'package:opennutritracker/fork/report/weekly_report.dart';

import '../../helpers/ux_checks.dart';

IntakeEntity _eat(
  String food,
  int day,
  double grams, {
  double? fiber,
  double? sugars,
  int hour = 12,
}) => IntakeEntity(
  id: '$food-$day-$grams',
  unit: 'g',
  amount: grams,
  type: IntakeTypeEntity.lunch,
  meal: MealEntity(
    code: food,
    name: food,
    url: null,
    mealQuantity: null,
    mealUnit: 'g',
    servingQuantity: null,
    servingUnit: 'g',
    servingSize: null,
    nutriments: MealNutrimentsEntity(
      energyKcal100: 200,
      carbohydrates100: 30,
      fat100: 5,
      proteins100: 10,
      sugars100: sugars,
      saturatedFat100: null,
      fiber100: fiber,
    ),
    source: MealSourceEntity.custom,
  ),
  dateTime: DateTime(2026, 10, day, hour),
);

TrackedDayEntity _day(int day, {double? fibreGoal}) => TrackedDayEntity(
  day: DateTime(2026, 10, day),
  calorieGoal: 2000,
  caloriesTracked: 1,
  proteinGoal: 100,
  fibreGoal: fibreGoal,
);

final _intakes = [
  _eat('Oats', 20, 100, fiber: 10),
  _eat('Oats', 21, 50, fiber: 10),
  _eat('Lentils', 21, 200, fiber: 8),
  _eat('Cola', 21, 300),
];

void main() {
  test('a mean over the logged days, and the foods it came from', () {
    final all = summarizeNutrients(_intakes, [
      _day(19),
      _day(20, fibreGoal: 40),
      _day(21),
    ], null);
    final energy = all.firstWhere((s) => s.nutrient.label == 'Energy');
    // 650 g at 200 kcal per 100 g over the two days logged.
    expect(energy.perDay, 650);
    expect(energy.goal, 2000);

    final fibre = all.firstWhere((s) => s.nutrient.label == 'Fibre');
    expect(fibre.perDay, (15 + 16) / 2);
    // The 20th's own goal, and the 21st, keeping none, takes it too: the
    // latest set (upstream keeps a goal on the day it was set).
    expect(fibre.goal, 40);
    expect(
      [for (final f in fibre.foods) (f.name, f.amount)],
      [('Lentils', 16), ('Oats', 15)],
    );
    expect(fibre.foodsWithout, 1);

    final protein = all.firstWhere((s) => s.nutrient.label == 'Protein');
    expect(protein.goal, 100);
    expect(energy.nutrient.marksMiss, isFalse);
    expect(fibre.nutrient.marksMiss, isTrue);
  });

  test(
    'a snack after midnight, before the day starts, is the day before\'s',
    () {
      final all = summarizeNutrients(
        [_eat('Oats', 20, 100), _eat('Chips', 21, 50, hour: 2)],
        [_day(20), _day(21)],
        null,
        dayStartMinutes: 4 * 60,
      );
      // One logical day, the 20th, with 150 g at 200 kcal per 100 g.
      expect(all.firstWhere((s) => s.nutrient.label == 'Energy').perDay, 300);
    },
  );

  test('with no goal set, the panel\'s reference', () {
    final all = summarizeNutrients(_intakes, [_day(20), _day(21)], null);
    expect(all.firstWhere((s) => s.nutrient.label == 'Fibre').goal, 30);
  });

  test('the latest goal set is found outside the range', () {
    final all = summarizeNutrients(
      _intakes,
      [_day(20), _day(21)],
      null,
      goalHistory: [_day(2, fibreGoal: 25), _day(20), _day(21)],
    );
    expect(all.firstWhere((s) => s.nutrient.label == 'Fibre').goal, 25);
  });

  testWidgets('the explorer\'s goal does not depend on the range', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: NutrientExplorerScreen(
          days: [_day(20), _day(21)],
          first: DateTime(2026, 10, 20),
          last: DateTime(2026, 10, 21),
          load: (first, last) async => _intakes,
          user: () async => null,
          goalHistory: () async => [_day(2, fibreGoal: 25)],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('goal 25 g'), findsOneWidget);
  });

  testWidgets('Edit goals measures against the goals set there', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: NutrientExplorerScreen(
          days: [_day(20), _day(21)],
          first: DateTime(2026, 10, 20),
          last: DateTime(2026, 10, 21),
          load: (first, last) async => _intakes,
          user: () async => null,
          editGoals: (context, first, last) async => [
            _day(20),
            _day(21, fibreGoal: 31),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('goal 30 g'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('nutrient-goals')));
    await tester.pumpAndSettle();
    expect(find.textContaining('goal 31 g'), findsOneWidget);
  });

  testWidgets('opened from the weekly report, a nutrient lists its foods', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: WeeklyReportCard(
              days: [
                TrackedDayEntity(
                  day: DateTime(2026, 10, 21),
                  calorieGoal: 2000,
                  caloriesTracked: 1300,
                ),
              ],
              rangeDays: 7,
              palette: AppPalette.light,
              clock: () => DateTime(2026, 10, 23, 9),
              load: (first, last) async {
                expect((first, last.day), (DateTime(2026, 10, 17), 23));
                return _intakes;
              },
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('nutrient-explorer')));
    await tester.pumpAndSettle();

    expect(find.text('650 kcal a day · goal 2000 kcal'), findsOneWidget);
    expect(find.text('33%'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('nutrient-Fibre')),
      200,
    );
    expect(find.text('1 food without a figure'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('nutrient-Fibre')));
    await tester.pumpAndSettle();

    expect(find.text('Fibre by food'), findsOneWidget);
    expect(find.text('Lentils'), findsOneWidget);
    expect(find.text('16 g fibre'), findsOneWidget);
    expect(find.text('52%'), findsOneWidget);
    expect(find.text('Oct 17 – Oct 23 · 7 days, 2 logged'), findsOneWidget);
  });

  Widget explorer(List<IntakeEntity> intakes) => MaterialApp(
    home: NutrientExplorerScreen(
      days: [_day(20), _day(21)],
      first: DateTime(2026, 10, 20),
      last: DateTime(2026, 10, 21),
      load: (first, last) async => intakes,
      user: () async => null,
      goalHistory: () async => null,
    ),
  );

  testWidgets('the bars colour as Nutrient goals does, with its key', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 7020);
    addTearDown(tester.view.reset);
    // Sugars 60 g a day, over the 50 g limit.
    await tester.pumpWidget(
      explorer([..._intakes, _eat('Jam', 21, 240, sugars: 50)]),
    );
    await tester.pumpAndSettle();
    Color? bar(String nutrient) => tester
        .widget<LinearProgressIndicator>(
          find.descendant(
            of: find.byKey(ValueKey('nutrient-$nutrient')),
            matching: find.byType(LinearProgressIndicator),
          ),
        )
        .color;
    final scheme = Theme.of(
      tester.element(find.byType(NutrientExplorerScreen)),
    ).colorScheme;
    // Fibre at 52% of its goal is not reached yet: grey, not green.
    expect(bar('Fibre'), AppPalette.light.textMuted);
    expect(bar('Energy'), AppPalette.light.textMuted);
    expect(bar('Sugars'), scheme.error);
    expect(bar('Saturated fat'), AppPalette.light.textMuted);
    expect(find.textContaining('· over the limit'), findsOneWidget);
    expect(find.textContaining('· reached'), findsNothing);
    expect(find.textContaining(goalStandingKey), findsOneWidget);
    expect(find.text('Oct 20 – Oct 21 · 2 days, 2 logged'), findsOneWidget);
  });

  testWidgets('a target met is green and says so; energy over its band is '
      'red', (tester) async {
    tester.view.physicalSize = const Size(1080, 7020);
    addTearDown(tester.view.reset);
    // 2 kg at 200 kcal per 100 g over two days: 2000 kcal over the 1300 a
    // day the goal below makes it; fibre 100 g a day against 30.
    await tester.pumpWidget(
      MaterialApp(
        home: NutrientExplorerScreen(
          days: [
            for (final d in [20, 21])
              TrackedDayEntity(
                day: DateTime(2026, 10, d),
                calorieGoal: 1300,
                caloriesTracked: 1,
                carbsGoal: 280,
                fatGoal: 40,
                proteinGoal: 50,
              ),
          ],
          first: DateTime(2026, 10, 20),
          last: DateTime(2026, 10, 21),
          load: (first, last) async => [
            _eat('Bran', 20, 1000, fiber: 10),
            _eat('Bran', 21, 1000, fiber: 10),
          ],
          user: () async => null,
          goalHistory: () async => null,
        ),
      ),
    );
    await tester.pumpAndSettle();
    LinearProgressIndicator bar(String nutrient) =>
        tester.widget<LinearProgressIndicator>(
          find.descendant(
            of: find.byKey(ValueKey('nutrient-$nutrient')),
            matching: find.byType(LinearProgressIndicator),
          ),
        );
    final scheme = Theme.of(
      tester.element(find.byType(NutrientExplorerScreen)),
    ).colorScheme;
    expect(bar('Fibre').color, AppPalette.light.accent);
    expect(find.text('100 g a day · goal 30 g · reached'), findsOneWidget);
    expect(bar('Energy').color, scheme.error);
    expect(find.textContaining('goal 1300 kcal · over'), findsOneWidget);
    // Carbs and fat are bands as Home reads them; protein is a target.
    expect(find.text('300 g a day · goal 280 g · on target'), findsOneWidget);
    expect(bar('Fat').color, scheme.error);
    expect(find.text('50 g a day · goal 40 g · over'), findsOneWidget);
    expect(bar('Protein').color, AppPalette.light.accent);
    expect(find.text('100 g a day · goal 50 g · reached'), findsOneWidget);

    // A full bar ends where the others' tracks end, whatever its share's
    // width (333% against 0%).
    double right(String nutrient) => tester
        .getTopRight(
          find.descendant(
            of: find.byKey(ValueKey('nutrient-$nutrient')),
            matching: find.byType(LinearProgressIndicator),
          ),
        )
        .dx;
    expect(right('Fibre'), right('Saturated fat'));
  });

  testWidgets('TalkBack reads the row, not the bar\'s value', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(explorer(_intakes));
    await tester.pumpAndSettle();
    final node = tester.getSemantics(
      find.byKey(const ValueKey('nutrient-Energy')),
    );
    expect(node.value, isEmpty);
    expect(node.label, startsWith('Energy'));
    semantics.dispose();
  });

  testWidgets('a food that gave none of a nutrient is not listed', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 7020);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      explorer([..._intakes, _eat('Water', 21, 500, fiber: 0)]),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('nutrient-Fibre')));
    await tester.pumpAndSettle();
    expect(find.text('Lentils'), findsOneWidget);
    expect(find.text('Water'), findsNothing);
  });

  testWidgets(
    'the screen at 200% text: nothing cut, the targets and contrast',
    (tester) async {
      await checkScreen(
        tester,
        NutrientExplorerScreen(
          days: [_day(20), _day(21)],
          first: DateTime(2026, 10, 20),
          last: DateTime(2026, 10, 21),
          load: (first, last) async => _intakes,
          user: () async => null,
          editGoals: (context, first, last) async => [_day(20), _day(21)],
        ),
      );
    },
  );
}
