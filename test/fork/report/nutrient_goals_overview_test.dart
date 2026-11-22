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
import 'package:opennutritracker/fork/report/nutrient_goals_overview.dart';

import '../../helpers/ux_checks.dart';

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

  test('a limit passed is over; a target is reached at its goal; energy '
      'is a band', () {
    GoalStanding s(
      bool isLimit,
      double perDay,
      double? goal, {
      bool isBand = false,
    }) => goalStanding(
      isLimit: isLimit,
      perDay: perDay,
      goal: goal,
      isBand: isBand,
    );
    expect(s(true, 5.76, 5.75), GoalStanding.over);
    expect(s(true, 5.75, 5.75), GoalStanding.under);
    // No limit to be within: grey, not green.
    expect(s(true, 99, null), GoalStanding.toReach);
    expect(s(false, 90, 30), GoalStanding.reached);
    expect(s(false, 30, 30), GoalStanding.reached);
    expect(s(false, 29.9, 30), GoalStanding.toReach);
    expect(s(false, 1, 30), GoalStanding.toReach);
    expect(s(false, 50, null), GoalStanding.toReach);
    // Energy within a tenth of its goal either way is reached.
    expect(s(false, 2400, 2000, isBand: true), GoalStanding.over);
    expect(s(false, 2200, 2000, isBand: true), GoalStanding.reached);
    expect(s(false, 1800, 2000, isBand: true), GoalStanding.reached);
    expect(s(false, 1700, 2000, isBand: true), GoalStanding.toReach);

    final scheme = ThemeData().colorScheme;
    const p = AppPalette.light;
    expect(goalStandingColor(GoalStanding.reached, p, scheme), p.accent);
    expect(goalStandingColor(GoalStanding.toReach, p, scheme), p.textMuted);
    expect(goalStandingColor(GoalStanding.under, p, scheme), p.accent);
    expect(goalStandingColor(GoalStanding.over, p, scheme), scheme.error);

    expect(goalStandingWord(GoalStanding.reached, isLimit: false), 'reached');
    expect(goalStandingWord(GoalStanding.over, isLimit: false), 'over');
    expect(
      goalStandingWord(GoalStanding.over, isLimit: true),
      'over the limit',
    );
    expect(
      goalStandingWord(GoalStanding.reached, isLimit: false, isBand: true),
      'on target',
    );
    expect(goalStandingWord(GoalStanding.toReach, isLimit: false), isNull);
    expect(goalStandingWord(GoalStanding.under, isLimit: true), 'within limit');
    expect(goalStandingKey, isNot(contains('under a limit')));
  });

  test('the range line names its dates, its days and the days logged', () {
    expect(
      nutrientRangeLine(DateTime(2026, 10, 23), DateTime(2026, 11, 21), 28),
      'Oct 23 – Nov 21 · 30 days, 28 logged',
    );
    // A clock change inside the range, and a time of day on the end.
    expect(
      nutrientRangeLine(
        DateTime(2026, 3, 25),
        DateTime(2026, 3, 31, 23, 59, 59),
        7,
      ),
      'Mar 25 – Mar 31 · 7 days, 7 logged',
    );
    expect(
      nutrientRangeLine(DateTime(2026, 10, 25), DateTime(2026, 10, 25), 1),
      'Oct 25 · 1 day, 1 logged',
    );
    expect(
      nutrientRangeLine(DateTime(2026, 12, 20), DateTime(2027, 1, 18), 30),
      'Dec 20, 2026 – Jan 18, 2027 · 30 days, 30 logged',
    );
  });

  test('the goals only, in the editor\'s and Nutrients list\'s order', () {
    final rows = goalRows(summarizeNutrients(const [], const [], null));
    expect(
      [for (final r in rows) goalRowLabel(r.nutrient)],
      [
        'Fibre',
        'Saturated fat',
        'Sugars',
        'Salt (from sodium)',
        'Calcium',
        'Iron',
        'Potassium',
        'Magnesium',
        'Vitamin D',
        'Vitamin B12',
      ],
    );
  });

  testWidgets('today against today\'s goals, then the week', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(asked.single, (DateTime(2026, 10, 25), DateTime(2026, 10, 25)));
    expect(label(tester, 'Fibre'), 'Fibre, 20 of 30 grams');
    // 3000 mg of sodium is 7.5 g of salt, against 2300 mg's 5.75 g.
    expect(
      label(tester, 'Salt'),
      'Salt (from sodium), 7.5 of 5.8 grams, over the limit',
    );

    await tester.tap(find.bySemanticsIdentifier('nutrient-goals-week'));
    await tester.pumpAndSettle();
    expect(asked.last, (DateTime(2026, 10, 19), DateTime(2026, 10, 25)));
    // A mean over the two days with food: 30 g, 1500 mg of sodium.
    expect(label(tester, 'Fibre'), 'Fibre, 30 of 30 grams, reached');
    expect(
      label(tester, 'Salt'),
      'Salt (from sodium), 3.8 of 5.8 grams, within limit',
    );
    // Under the ten bars, past the first screen in the test font.
    await tester.scrollUntilVisible(
      find.textContaining('days with food logged'),
      200,
    );
    expect(find.textContaining('days with food logged'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('today\'s row is read to the end of the day', (tester) async {
    DateTime? end;
    await tester.pumpWidget(
      MaterialApp(
        home: NutrientGoalsOverview(
          today: () async => DateTime(2026, 10, 25),
          load: (first, last) async => _intakes,
          days: (first, last) async {
            end = last;
            return [_day(25, fibreGoal: 30)];
          },
          user: () async => null,
          dayStart: () async => 0,
          onEdit: (_) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    // A row from the Diary is labelled at UTC midnight: past local midnight
    // east of Greenwich.
    expect(end, DateTime(2026, 10, 25, 23, 59, 59));
  });

  testWidgets(
    'the week takes the latest goal from all the days; today its own',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        MaterialApp(
          home: NutrientGoalsOverview(
            today: () async => DateTime(2026, 10, 25),
            load: (first, last) async => _intakes,
            days: (first, last) async => [_day(20), _day(25)],
            goalHistory: () async => [_day(2, fibreGoal: 45), _day(25)],
            user: () async => null,
            dayStart: () async => 0,
            onEdit: (_) async {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      // The Diary's panel: the day's own, else the reference.
      expect(label(tester, 'Fibre'), contains('of 30 g'));

      await tester.tap(find.bySemanticsIdentifier('nutrient-goals-week'));
      await tester.pumpAndSettle();
      expect(label(tester, 'Fibre'), contains('of 45 g'));
      semantics.dispose();
    },
  );

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
    // Fibre at 20 of 30 g is not reached: grey, not green.
    expect(bar('Fibre'), AppPalette.light.textMuted);
    expect(bar('Salt'), Theme.of(context).colorScheme.error);
    // Under its limit: green, as a goal met is.
    expect(bar('Sugars'), AppPalette.light.accent);
    expect(find.textContaining('· reached'), findsNothing);

    await tester.tap(find.bySemanticsIdentifier('nutrient-goals-week'));
    await tester.pumpAndSettle();
    // 30 of 30 g: green, and the word shows as well as is spoken.
    expect(bar('Fibre'), AppPalette.light.accent);
    expect(find.textContaining('· reached'), findsOneWidget);
  });

  testWidgets('a row\'s label keeps a gap before its number', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    final texts = find.descendant(
      of: find.bySemanticsIdentifier('nutrient-goal-Fibre'),
      matching: find.byType(RichText),
    );
    // A wrapped "· reached" ran into "18 / 15 µg" at 200% text.
    expect(
      tester.getRect(texts.at(1)).left - tester.getRect(texts.at(0)).right,
      greaterThanOrEqualTo(8),
    );
  });

  testWidgets('Edit opens the goal list, and the bars are read again', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    final before = asked.length;
    // G5-13: "Edit" alone did not say what it edits.
    expect(find.text('Edit goals'), findsOneWidget);
    await tester.tap(find.bySemanticsIdentifier('nutrient-goals-edit'));
    await tester.pumpAndSettle();
    expect(edits, 1);
    expect(asked.length, before + 1);
  });

  testWidgets(
    'the screen at 200% text: nothing cut, the targets and contrast',
    (tester) async {
      await checkScreen(
        tester,
        NutrientGoalsOverview(
          today: () async => DateTime(2026, 10, 25),
          load: (first, last) async => _intakes,
          days: (first, last) async => [
            _day(25, fibreGoal: 30, sodiumGoal: 2300),
          ],
          user: () async => null,
          dayStart: () async => 0,
          onEdit: (_) async {},
        ),
      );
    },
  );
}
