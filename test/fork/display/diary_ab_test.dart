import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/domain/entity/tracked_day_entity.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/features/add_meal/presentation/add_meal_type.dart';
import 'package:opennutritracker/features/diary/presentation/widgets/diary_table_calendar.dart';
import 'package:opennutritracker/features/home/presentation/bloc/home_bloc.dart';
import 'package:opennutritracker/fork/screens/home/intake_vertical_list.dart';
import 'package:opennutritracker/features/meal_detail/presentation/bloc/meal_detail_bloc.dart';
import 'package:opennutritracker/fork/display/day_ring.dart';
import 'package:opennutritracker/fork/display/day_totals_card.dart';
import 'package:opennutritracker/fork/display/diary_timeline.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:provider/provider.dart';

final _day = DateTime(2026, 10, 25);

class _MealDetailBloc extends Fake implements MealDetailBloc {}

class _HomeBloc extends Fake implements HomeBloc {}

IntakeEntity _intake(
  IntakeTypeEntity type,
  DateTime at, {
  String name = 'Rice',
  double grams = 100,
}) => IntakeEntity(
  id: '$name-$at',
  unit: 'g',
  amount: grams,
  type: type,
  meal: MealEntity(
    code: name,
    name: name,
    url: null,
    mealQuantity: null,
    mealUnit: 'g',
    servingQuantity: null,
    servingUnit: null,
    servingSize: null,
    nutriments: MealNutrimentsEntity(
      energyKcal100: 100,
      carbohydrates100: 20,
      fat100: 10,
      proteins100: 5,
      sugars100: null,
      saturatedFat100: null,
      fiber100: null,
    ),
    source: MealSourceEntity.custom,
  ),
  dateTime: at,
);

TrackedDayEntity _tracked({double eaten = 0, double goal = 2000}) =>
    TrackedDayEntity(
      day: _day,
      calorieGoal: goal,
      caloriesTracked: eaten,
      carbsGoal: 250,
      fatGoal: 70,
      proteinGoal: 120,
    );

Widget _app(Widget child) => ChangeNotifierProvider<EnergyUnitProvider>(
  create: (_) => EnergyUnitProvider(usesKilojoules: false),
  child: MaterialApp(
    localizationsDelegates: const [
      S.delegate,
      ...GlobalMaterialLocalizations.delegates,
    ],
    supportedLocales: S.supportedLocales,
    home: Scaffold(body: SingleChildScrollView(child: child)),
  ),
);

TimelineMeal _meal(IntakeTypeEntity type, List<IntakeEntity> intakes) =>
    (type: type, intakes: intakes, section: Text('section ${type.name}'));

List<String> _shown(List<Widget> widgets) => [
  for (final w in widgets)
    switch (w) {
      Text(:final data?) => data,
      TimelineGap(:final from, :final to) => 'gap ${from.hour}-${to.hour}',
      _ => '$w',
    },
];

void main() {
  group('the timeline', () {
    test('a meal sits at its first timed food, else at its usual hour', () {
      expect(
        mealTime(_day, IntakeTypeEntity.lunch, [
          _intake(IntakeTypeEntity.lunch, DateTime(2026, 10, 25, 13, 40)),
          _intake(IntakeTypeEntity.lunch, DateTime(2026, 10, 25, 12, 5)),
          // No time: at midnight, which is not when it was eaten.
          _intake(IntakeTypeEntity.lunch, _day),
        ]),
        DateTime(2026, 10, 25, 12, 5),
      );
      expect(
        mealTime(_day, IntakeTypeEntity.dinner, [
          _intake(IntakeTypeEntity.dinner, _day),
        ]),
        DateTime(2026, 10, 25, 19),
      );
      expect(
        mealTime(_day, IntakeTypeEntity.breakfast, const []),
        DateTime(2026, 10, 25, 8),
      );
    });

    test('the meals in the order eaten, the empty hours between', () {
      final shown = _shown(
        diaryTimeline(_day, [
          _meal(IntakeTypeEntity.breakfast, const []),
          _meal(IntakeTypeEntity.lunch, [
            _intake(IntakeTypeEntity.lunch, DateTime(2026, 10, 25, 12)),
          ]),
          _meal(IntakeTypeEntity.dinner, [
            _intake(IntakeTypeEntity.dinner, DateTime(2026, 10, 25, 19)),
          ]),
          _meal(IntakeTypeEntity.snack, [
            _intake(IntakeTypeEntity.snack, DateTime(2026, 10, 25, 9, 30)),
            _intake(IntakeTypeEntity.snack, DateTime(2026, 10, 25, 10, 15)),
          ]),
        ]),
      );
      expect(shown, [
        'section breakfast',
        'section snack',
        // From the hour after the snack's last food.
        'gap 11-11',
        'section lunch',
        'gap 13-18',
        'section dinner',
      ]);
    });

    test('meals at the same time keep the usual order', () {
      final at = DateTime(2026, 10, 25, 12);
      expect(
        _shown(
          diaryTimeline(_day, [
            _meal(IntakeTypeEntity.lunch, [
              _intake(IntakeTypeEntity.lunch, at),
            ]),
            _meal(IntakeTypeEntity.snack, [
              _intake(IntakeTypeEntity.snack, at),
            ]),
          ]),
        ),
        ['section lunch', 'section snack'],
      );
    });

    testWidgets('a meal on the timeline leads with its time and adds from '
        'its header', (tester) async {
      GetIt.instance
        ..registerSingleton<MealDetailBloc>(_MealDetailBloc())
        ..registerSingleton<HomeBloc>(_HomeBloc());
      addTearDown(GetIt.instance.reset);
      await tester.pumpWidget(
        _app(
          IntakeVerticalList(
            day: _day,
            title: 'Lunch',
            listIcon: Icons.lunch_dining_outlined,
            addMealType: AddMealType.lunchType,
            intakeList: [
              _intake(IntakeTypeEntity.lunch, DateTime(2026, 10, 25, 13)),
            ],
            usesImperialUnits: false,
            onDeleteIntakeCallback: (_, _) {},
            forkTime: DateTime(2026, 10, 25, 13),
          ),
        ),
      );
      // The phone's clock: 12 hours in the test's en-US
      expect(find.text('1:00 PM'), findsOneWidget);
      // The summary on one line under the title.
      expect(find.text('100 kcal · C 20 · F 10 · P 5'), findsOneWidget);
      expect(find.byIcon(Icons.lunch_dining_outlined), findsNothing);
      expect(find.byKey(const ValueKey('timeline-add')), findsOneWidget);
      expect(find.bySemanticsIdentifier('add-meal-placeholder'), findsNothing);
    });
  });

  testWidgets('the day card: the counts, and each total against its goal, '
      'past it in red', (tester) async {
    await tester.pumpWidget(
      _app(
        DayTotalsCard(
          trackedDay: _tracked(),
          intakes: [
            _intake(
              IntakeTypeEntity.lunch,
              DateTime(2026, 10, 25, 12),
              grams: 300,
            ),
            _intake(
              IntakeTypeEntity.lunch,
              DateTime(2026, 10, 25, 12),
              name: 'Oil',
              grams: 500,
            ),
            _intake(
              IntakeTypeEntity.dinner,
              DateTime(2026, 10, 25, 19),
              name: 'Beans',
            ),
          ],
        ),
      ),
    );
    expect(find.text('2 meals · 3 foods'), findsOneWidget);
    // 900 g at 100 kcal, 20 g carbs and 10 g fat per 100 g.
    expect(find.bySemanticsLabel('900 of 2000 kcal'), findsOneWidget);
    expect(find.bySemanticsLabel('180 of 250 carbs g'), findsOneWidget);
    expect(find.bySemanticsLabel('90 of 70 fat g, over'), findsOneWidget);

    final error = Theme.of(
      tester.element(find.byType(DayTotalsCard)),
    ).colorScheme.error;
    final bars = tester
        .widgetList<LinearProgressIndicator>(
          find.byType(LinearProgressIndicator),
        )
        .toList();
    expect(
      [for (final b in bars) b.color == error],
      [false, false, true, false],
    );
  });

  test('a ring fills with the energy eaten against the goal', () {
    expect(DayRing.fill(null), 0);
    expect(DayRing.fill(_tracked(eaten: 500)), 0.25);
    expect(DayRing.fill(_tracked(eaten: 2600)), 1);
    expect(DayRing.fill(_tracked(eaten: 500, goal: 0)), 0);
  });

  testWidgets('the calendar shows a week until its title is tapped', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        DiaryTableCalendar(
          onDateSelected: (_, _) {},
          calendarDurationDays: const Duration(days: 365),
          focusedDate: _day,
          currentDate: _day,
          selectedDate: _day,
          trackedDaysMap: const {},
        ),
      ),
    );
    expect(find.byType(DayRing), findsNWidgets(7));

    await tester.tap(find.text('October 2026'));
    await tester.pumpAndSettle();
    expect(find.byType(DayRing).evaluate().length, greaterThanOrEqualTo(28));
  });
}
