import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/domain/entity/tracked_day_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_gender_entity.dart';
import 'package:opennutritracker/core/domain/entity/weight_log_entity.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/features/trends/presentation/bloc/trends_bloc.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_service.dart';
import 'package:opennutritracker/fork/body/measurement_store.dart';
import 'package:opennutritracker/fork/body/waist_ratio.dart';
import 'package:opennutritracker/fork/display/display_prefs.dart';
import 'package:opennutritracker/fork/goal/goal_progress.dart';
import 'package:opennutritracker/fork/phases/phases.dart';
import 'package:opennutritracker/fork/report/nutrient_explorer.dart';
import 'package:opennutritracker/fork/report/trends_layout.dart';
import 'package:opennutritracker/fork/trends/trends_overview.dart';
import 'package:opennutritracker/fork/trends/trends_widgets.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:provider/provider.dart';

import 'trends_harness.dart';

// The Trends critique (2026-11-17): six tiles by default, no empty tiles,
// the span said once, tiles spoken in words.

TrackedDayEntity _logged(int offset) => TrackedDayEntity(
  day: day(offset),
  calorieGoal: 2925,
  caloriesTracked: 2572.6,
  carbsTracked: 69.5,
  carbsGoal: 259,
  fatTracked: 81,
  fatGoal: 81,
  proteinTracked: 93,
  proteinGoal: 110,
);

IntakeEntity _ate(
  int offset, {
  double? sugars,
  double? fibre,
  double? sodium,
}) => IntakeEntity(
  id: 'food $offset',
  unit: 'g',
  amount: 100,
  type: IntakeTypeEntity.lunch,
  meal: MealEntity(
    code: 'food',
    name: 'food',
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
      sugars100: sugars,
      saturatedFat100: null,
      fiber100: fibre,
      sodium100: sodium,
    ),
    source: MealSourceEntity.custom,
  ),
  dateTime: day(offset).add(const Duration(hours: 12)),
);

class _Service extends Fake implements AdaptiveService {
  final List<ExpenditureDay> history;
  _Service(this.history);

  @override
  Future<List<ExpenditureDay>> expenditureHistory() async => history;
}

/// The tiles shown, top to bottom and left to right, by metric.
List<String> _shown(WidgetTester tester) => [
  for (final t in tester.widgetList<TrendTile>(
    find.byType(TrendTile, skipOffstage: false),
  ))
    t.id.substring('trends-tile-'.length),
];

TrendTile _tile(WidgetTester tester, String metric) => tester.widget(
  find.byWidgetPredicate(
    (w) => w is TrendTile && w.id == 'trends-tile-$metric',
    skipOffstage: false,
  ),
);

/// TrendsOverview alone, with [cards] below the grid and [history] for
/// expenditure and balance.
Future<void> _pumpOverview(
  WidgetTester tester,
  TrendsLoaded state, {
  Map<String, Widget> cards = const {},
  List<ExpenditureDay> history = const [],
}) async {
  await tester.pumpWidget(
    ChangeNotifierProvider(
      create: (_) => EnergyUnitProvider(usesKilojoules: false),
      child: MaterialApp(
        localizationsDelegates: const [
          S.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: S.supportedLocales,
        home: Scaffold(
          body: BlocProvider<TrendsBloc>.value(
            value: SeededTrendsBloc(state),
            child: TrendsOverview(
              state: state,
              weightCard: (_) => const SizedBox(),
              waterCard: (_) => const SizedBox(),
              cards: cards,
              service: _Service(history),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    DisplayPrefs.showWater.value = true;
  });
  tearDown(() async {
    DisplayPrefs.showWater.value = false;
    TrendsOverview.loadIntakes = intakesBetween;
    TrendsOverview.loadGoal = () => GoalStartStore().load();
    TrendsOverview.loadPhases = () async => (
      plan: await PhaseStore().plan(),
      history: await PhaseStore().history(),
    );
    TrendsOverview.loadMeasurements = () async => const [];
    TrendsTilesStore.current.value = (order: const [], hidden: const {});
    await locator.reset();
  });

  final measured = [
    Measurement(id: 'l', date: day(-1), metric: BodyMetric.leftArm, value: 36),
    Measurement(id: 'r', date: day(-1), metric: BodyMetric.rightArm, value: 35),
  ];

  testWidgets('a profile that never arranged them: the six default tiles', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(2400, 6000);
    addTearDown(tester.view.reset);
    TrendsOverview.loadMeasurements = () async => measured;
    await pumpTrends(
      tester,
      loaded(
        days: [_logged(0)],
        waterByDay: {day(0): 1200},
        targetWeightKg: 75,
        weight: [WeightLogEntity(date: day(0), weightKg: 80)],
      ),
      allTiles: false,
    );
    expect(_shown(tester), [
      'calories',
      'weight',
      'expenditure',
      'balance',
      'protein',
      'fibre',
    ]);

    // The others wait in Arrange Trends, switched off.
    await tester.tap(find.byKey(const ValueKey('trends-arrange')));
    await tester.pumpAndSettle();
    bool on(String id) => tester
        .widget<SwitchListTile>(find.byKey(ValueKey('arrange-$id')))
        .value;
    expect(on('protein'), isTrue);
    expect(on('fat'), isFalse);
    expect(on('sides'), isFalse);
  });

  testWidgets('a saved tile layout is kept', (tester) async {
    tester.view.physicalSize = const Size(2400, 6000);
    addTearDown(tester.view.reset);
    TrendsTilesStore.current.value = (
      order: allTrendTiles,
      hidden: {'protein'},
    );
    await pumpTrends(tester, loaded(days: [_logged(0)]), allTiles: false);
    expect(_shown(tester), containsAllInOrder(['carbs', 'fat', 'sugars']));
    expect(_shown(tester), isNot(contains('protein')));
  });

  testWidgets('a tile with no data is left out until it has some', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(2400, 6000);
    addTearDown(tester.view.reset);
    await pumpTrends(tester, loaded(days: [_logged(0)]));
    // No goal, no measurements: the cards below invite them.
    expect(_shown(tester), isNot(contains('goal')));
    expect(_shown(tester), isNot(contains('sides')));
    // A tile with nothing logged in the range keeps its place.
    expect(_shown(tester), contains('water'));

    TrendsOverview.loadMeasurements = () async => measured;
    MeasurementStore.changes.value++;
    await tester.pumpAndSettle();
    expect(_shown(tester), contains('sides'));
  });

  testWidgets('titles without "avg", the span said once under the pills', (
    tester,
  ) async {
    await pumpTrends(tester, loaded(days: [_logged(0)]));
    expect(find.textContaining('avg', skipOffstage: false), findsNothing);
    expect(_tile(tester, 'calories').label, 'Calories');
    expect(_tile(tester, 'protein').label, 'Protein');
    final span = find.byKey(const ValueKey('trends-span'));
    expect(
      tester.widget<Text>(span).data,
      'Daily averages · Last 7 days · 1\u00A0logged',
    );
    expect(
      tester.getTopLeft(span).dy,
      greaterThan(tester.getBottomLeft(find.text('1W')).dy),
    );
    expect(
      tester.getBottomLeft(span).dy,
      lessThan(tester.getTopLeft(find.byType(TrendTile).first).dy),
    );
    expect(
      find.bySemanticsLabel('Daily averages, last 7 days, 1 day logged'),
      findsOneWidget,
    );
    expect(find.textContaining('Tap a card'), findsNothing);
  });

  testWidgets('nothing logged: the span leaves the count out', (tester) async {
    await pumpTrends(tester, loaded());
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('trends-span'))).data,
      'Daily averages · Last 7 days',
    );
  });

  testWidgets('Arrange Trends sits under the tiles, over the cards', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(2400, 6000);
    addTearDown(tester.view.reset);
    await _pumpOverview(
      tester,
      loaded(days: [_logged(0)]),
      cards: {for (final id in trendCards.keys) id: Text('card $id')},
    );
    final arrange = tester.getTopLeft(
      find.byKey(const ValueKey('trends-arrange')),
    );
    final lastTile = tester.getBottomLeft(find.byType(TrendTile).last);
    expect(arrange.dy, greaterThan(lastTile.dy));
    expect(
      arrange.dy,
      lessThan(tester.getTopLeft(find.text('card weekly')).dy),
    );
  });

  testWidgets('past 1.5x text the tiles are one column', (tester) async {
    tester.view.physicalSize = const Size(1080, 6000);
    addTearDown(tester.view.reset);
    await pumpTrends(tester, loaded(days: [_logged(0)]));
    Offset at(String m) =>
        tester.getTopLeft(find.byKey(ValueKey('trends-tile-$m')));
    expect(at('weight').dy, at('calories').dy);

    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpAndSettle();
    expect(at('weight').dx, at('calories').dx);
    expect(at('weight').dy, greaterThan(at('calories').dy));
  });

  testWidgets('tiles are spoken in words', (tester) async {
    TrendsOverview.loadIntakes = (first, last) async => [
      _ate(0, sugars: 124, fibre: 40),
    ];
    await pumpTrends(
      tester,
      loaded(
        days: [_logged(0)],
        weight: [
          WeightLogEntity(date: day(-6), weightKg: 80),
          WeightLogEntity(date: day(0), weightKg: 79.4),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(
      _tile(tester, 'calories').spokenLabel,
      'Calories, daily average 2573 of 2925 kcal',
    );
    expect(
      _tile(tester, 'weight').spokenLabel,
      matches(RegExp(r'^Weight trend, \d\d\.\d kg, down 0\.\d\d kg a week$')),
    );
    expect(
      _tile(tester, 'sugars').spokenLabel,
      'Sugars, daily average 124 of 50 g, over limit',
    );
    expect(_tile(tester, 'sugars').note, 'over limit');
    // Fibre past its goal is a target met, no alarm.
    expect(
      _tile(tester, 'fibre').spokenLabel,
      'Fibre, daily average 40 of 30 g',
    );
    expect(_tile(tester, 'fibre').note, isNull);
    // Salt under its limit.
    expect(_tile(tester, 'sodium').note, isNull);
    for (final t in tester.widgetList<TrendTile>(
      find.byType(TrendTile, skipOffstage: false),
    )) {
      expect(t.spokenLabel, isNot(matches(RegExp(r'[/·–]|avg|/wk'))));
    }
  });

  testWidgets('balance and expenditure are spoken in words', (tester) async {
    await _pumpOverview(
      tester,
      loaded(),
      history: [
        for (var i = -6; i <= 0; i++)
          ExpenditureDay(
            date: day(i),
            expenditureKcal: 3000 + i * 10.0,
            intakeKcal: i.isEven ? 2500 : null,
            settled: true,
          ),
      ],
    );
    expect(
      _tile(tester, 'balance').spokenLabel,
      'Energy balance, 470 kcal a day under',
    );
    expect(
      _tile(tester, 'expenditure').spokenLabel,
      'Expenditure, 3000 kcal a day',
    );
  });

  testWidgets('a saved order shows the tiles it does not list', (tester) async {
    tester.view.physicalSize = const Size(2400, 6000);
    addTearDown(tester.view.reset);
    loadBodyFrame = () async =>
        (heightCm: 180.0, gender: UserGenderEntity.male);
    addTearDown(() => loadBodyFrame = () async => null);
    TrendsOverview.loadMeasurements = () async => [
      Measurement(id: 'w', date: day(-1), metric: BodyMetric.waist, value: 90),
    ];
    // Saved before waist to height came, with water off in Settings.
    TrendsTilesStore.current.value = (
      order: [
        for (final id in allTrendTiles)
          if (id != 'waist' && id != 'water') id,
      ],
      hidden: const {},
    );
    await pumpTrends(tester, loaded(days: [_logged(0)]), allTiles: false);
    expect(_shown(tester), containsAll(['waist', 'water', 'carbs', 'fat']));

    // In the editor they are on as well.
    await tester.tap(find.byKey(const ValueKey('trends-arrange')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<SwitchListTile>(find.byKey(const ValueKey('arrange-waist')))
          .value,
      isTrue,
    );
  });

  testWidgets('water switched back on in Settings comes back to the grid', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(2400, 6000);
    addTearDown(tester.view.reset);
    DisplayPrefs.showWater.value = false;
    TrendsTilesStore.current.value = (
      order: [
        for (final id in allTrendTiles)
          if (id != 'water') id,
      ],
      hidden: const {},
    );
    await pumpTrends(tester, loaded(days: [_logged(0)]), allTiles: false);
    expect(_shown(tester), isNot(contains('water')));
    DisplayPrefs.showWater.value = true;
    await tester.pumpAndSettle();
    expect(_shown(tester), contains('water'));
  });

  testWidgets('a tile still loading keeps its place', (tester) async {
    final measurements = Completer<List<Measurement>>();
    TrendsOverview.loadMeasurements = () => measurements.future;
    await pumpTrends(tester, loaded(days: [_logged(0)]));
    expect(_shown(tester), contains('sides'));
    measurements.complete(const []);
    await tester.pumpAndSettle();
    expect(_shown(tester), isNot(contains('sides')));
  });

  testWidgets('the Goal tile and a steady weight in words', (tester) async {
    await pumpTrends(
      tester,
      loaded(
        targetWeightKg: 75,
        weight: [
          WeightLogEntity(date: day(-6), weightKg: 80),
          WeightLogEntity(date: day(0), weightKg: 80),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(
      _tile(tester, 'weight').spokenLabel,
      'Weight trend, 80.0 kg, steady',
    );
    expect(
      _tile(tester, 'goal').spokenLabel,
      matches(RegExp(r'^Goal, \d+\.\d kg to go$')),
    );
  });

  testWidgets('the Goal tile reached, in words', (tester) async {
    TrendsOverview.loadGoal = () async => (
      inputs: null,
      progress: GoalProgress(
        start: GoalStart(date: day(-60), kg: 80, targetKg: 75),
        nowKg: 74,
        paceKgPerWeek: -0.5,
        trend: const [80, 74],
        today: day(0),
      ),
    );
    await pumpTrends(
      tester,
      loaded(
        targetWeightKg: 75,
        weight: [WeightLogEntity(date: day(0), weightKg: 74)],
      ),
    );
    await tester.pumpAndSettle();
    expect(_tile(tester, 'goal').spokenLabel, 'Goal, target reached');
  });

  testWidgets('a goal with no target, in words', (tester) async {
    TrendsOverview.loadPhases = () async => (
      plan: PhasePlan(
        start: day(-7),
        phases: const [
          DietPhase(kind: PhaseKind.maintain, kgPerWeek: 0, weeks: 4),
        ],
      ),
      history: const <GoalRecord>[],
    );
    await pumpTrends(
      tester,
      loaded(weight: [WeightLogEntity(date: day(0), weightKg: 80)]),
    );
    await tester.pumpAndSettle();
    expect(
      _tile(tester, 'goal').spokenLabel,
      matches(RegExp(r'^Goal, Maintain until \w+ \d+$')),
    );
  });

  testWidgets('a limit met as shown is not over it', (tester) async {
    // 2310 mg is 5.775 g of salt, shown 5.8; the limit 2300 mg, 5.75 g,
    // is shown 5.8 too.
    TrendsOverview.loadIntakes = (first, last) async => [_ate(0, sodium: 2310)];
    await pumpTrends(tester, loaded(days: [_logged(0)]));
    await tester.pumpAndSettle();
    expect(
      _tile(tester, 'sodium').spokenLabel,
      'Salt, daily average 5.8 of 5.8 g',
    );
    expect(_tile(tester, 'sodium').note, isNull);
  });
}
