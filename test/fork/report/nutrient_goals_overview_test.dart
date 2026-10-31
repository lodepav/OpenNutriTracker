import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/domain/entity/tracked_day_entity.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/fork/report/nutrient_explorer.dart';
import 'package:opennutritracker/fork/report/nutrient_goals_overview.dart';

IntakeEntity _eat(int day, double grams, {double? fiber, double? sodium}) =>
    IntakeEntity(
      id: '$day-$grams',
      unit: 'g',
      amount: grams,
      type: IntakeTypeEntity.lunch,
      meal: MealEntity(
        code: 'food-$day',
        name: 'Food $day',
        url: null,
        mealQuantity: null,
        mealUnit: 'g',
        servingQuantity: null,
        servingUnit: 'g',
        servingSize: null,
        nutriments: MealNutrimentsEntity(
          energyKcal100: 100,
          carbohydrates100: 10,
          fat100: 1,
          proteins100: 5,
          sugars100: null,
          saturatedFat100: null,
          fiber100: fiber,
          sodium100: sodium,
        ),
        source: MealSourceEntity.custom,
      ),
      dateTime: DateTime(2026, 10, day, 12),
    );

TrackedDayEntity _day(int day, {double? fibreGoal, double? sodiumGoal}) =>
    TrackedDayEntity(
      day: DateTime(2026, 10, day),
      calorieGoal: 2000,
      caloriesTracked: 1,
      fibreGoal: fibreGoal,
      sodiumGoal: sodiumGoal,
    );

final _intakes = [
  // Today, the 25th: 20 g fibre, 3000 mg sodium.
  _eat(25, 200, fiber: 10, sodium: 1500),
  // Five days ago: 40 g fibre, no sodium.
  _eat(20, 400, fiber: 10, sodium: 0),
];

void main() {
  late List<(DateTime, DateTime)> asked;
  late int edits;

  Widget app() => MaterialApp(
    home: NutrientGoalsOverview(
      today: () async => DateTime(2026, 10, 25),
      load: (first, last) async {
        asked.add((first, last));
        return [
          for (final i in _intakes)
            if (!i.dateTime.isBefore(first) &&
                i.dateTime.isBefore(last.add(const Duration(days: 1))))
              i,
        ];
      },
      days: (first, last) async => [_day(25, fibreGoal: 30, sodiumGoal: 2300)],
      user: () async => null,
      dayStart: () async => 0,
      onEdit: (_) async => edits++,
    ),
  );

  setUp(() {
    asked = [];
    edits = 0;
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.physicalSize = const Size(1080, 2400);
    addTearDown(view.reset);
  });

  String label(WidgetTester tester, String nutrient) => tester
      .getSemantics(find.bySemanticsIdentifier('nutrient-goal-$nutrient'))
      .label;

  test('a limit passed is over; a target is to reach, however far', () {
    NutrientSummary s(String label, double perDay, double goal) =>
        NutrientSummary(
          nutrient: explorerNutrients.firstWhere((n) => n.label == label),
          perDay: perDay,
          goal: goal,
          foods: const [],
          foodsWithout: 0,
        );
    expect(standingOf(s('Salt', 5.76, 5.75)), GoalStanding.over);
    expect(standingOf(s('Salt', 5.75, 5.75)), GoalStanding.under);
    expect(standingOf(s('Fibre', 90, 30)), GoalStanding.toReach);
    expect(standingOf(s('Fibre', 1, 30)), GoalStanding.toReach);
  });

  test('the goals only, targets first, then limits', () {
    final rows = goalRows(summarizeNutrients(const [], const [], null));
    final names = [for (final r in rows) r.nutrient.label];
    expect(names, isNot(contains('Energy')));
    expect(names, isNot(contains('Protein')));
    final firstLimit = rows.indexWhere((r) => r.nutrient.isLimit);
    expect(rows.skip(firstLimit).every((r) => r.nutrient.isLimit), isTrue);
    expect(names.take(firstLimit), contains('Fibre'));
  });

  testWidgets('today against today\'s goals, then the week', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(asked.single, (DateTime(2026, 10, 25), DateTime(2026, 10, 25)));
    expect(label(tester, 'Fibre'), 'Fibre, 20 of 30 g');
    // 3000 mg of sodium is 7.5 g of salt, against 2300 mg's 5.75 g.
    expect(label(tester, 'Salt'), 'Salt, 7.5 of 5.8 g, over the limit');

    await tester.tap(find.bySemanticsIdentifier('nutrient-goals-week'));
    await tester.pumpAndSettle();
    expect(asked.last, (DateTime(2026, 10, 19), DateTime(2026, 10, 25)));
    // A mean over the two days with food: 30 g, 1500 mg of sodium.
    expect(label(tester, 'Fibre'), 'Fibre, 30 of 30 g, reached');
    expect(label(tester, 'Salt'), 'Salt, 3.8 of 5.8 g');
    expect(find.textContaining('days with food logged'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('the bars take their colour from where they stand', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    Color? bar(String nutrient) => tester
        .widget<LinearProgressIndicator>(
          find.descendant(
            of: find.bySemanticsIdentifier('nutrient-goal-$nutrient'),
            matching: find.byType(LinearProgressIndicator),
          ),
        )
        .color;
    final context = tester.element(find.byType(NutrientGoalsOverview));
    expect(bar('Fibre'), AppPalette.light.accent);
    expect(bar('Salt'), Theme.of(context).colorScheme.error);
    expect(bar('Sugars'), AppPalette.light.textMuted);
  });

  testWidgets('Edit opens the goal list, and the bars are read again', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    final before = asked.length;
    await tester.tap(find.bySemanticsIdentifier('nutrient-goals-edit'));
    await tester.pumpAndSettle();
    expect(edits, 1);
    expect(asked.length, before + 1);
  });
}
