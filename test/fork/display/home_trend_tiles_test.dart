import 'package:opennutritracker/core/domain/entity/user_gender_entity.dart';
import 'package:opennutritracker/fork/body/waist_ratio.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:opennutritracker/core/data/data_source/intake_data_source.dart';
import 'package:opennutritracker/core/data/dbo/intake_dbo.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/body_weight_unit_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_weight_goal_entity.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/fasting/presentation/bloc/fasting_bloc.dart';
import 'package:opennutritracker/features/trends/presentation/bloc/trends_bloc.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_service.dart';
import 'package:opennutritracker/fork/body/measurement_store.dart';
import 'package:opennutritracker/fork/body/side_compare.dart';
import 'package:opennutritracker/fork/display/home_tiles.dart';
import 'package:opennutritracker/fork/layout/home_layout.dart';
import 'package:opennutritracker/fork/layout/layout_store.dart';
import 'package:opennutritracker/fork/phases/phases.dart';
import 'package:opennutritracker/fork/report/nutrient_explorer.dart';
import 'package:opennutritracker/fork/trends/nutrient_trends.dart';
import 'package:opennutritracker/fork/trends/trends_overview.dart';
import 'package:opennutritracker/fork/trends/trends_widgets.dart'
    show TrendTile;
import 'package:opennutritracker/generated/l10n.dart';
import 'package:provider/provider.dart';

import '../../fixture/intake_entity_fixtures.dart';
import '../trends/trends_harness.dart';

// Trends' tiles Home can add, off until switched on.

/// Today's oats, as the database gives them.
class _Intakes extends Fake implements IntakeDataSource {
  @override
  Future<List<IntakeDBO>> getAllIntakes() async => [
    IntakeDBO.fromIntakeEntity(intakeOf('Oats', 100, carbs100: 60)),
  ];
}

void main() {
  final layout = LayoutStore.current(homeTilesKey);
  final readPace = TrendsOverview.loadPace;
  final readPhases = TrendsOverview.loadPhases;

  tearDown(() async {
    layout.value = (order: const [], hidden: const {});
    TrendsOverview.loadPace = readPace;
    TrendsOverview.loadPhases = readPhases;
    TrendsOverview.loadMeasurements = () async => const [];
    loadBodyFrame = () async => null;
    summarizeMicros = summarizeNutrients;
    await locator.reset();
  });

  Future<SeededTrendsBloc> pump(
    WidgetTester tester, {
    Stream<Object?>? homeLoads,
  }) async {
    final bloc = SeededTrendsBloc(loaded(rangeDays: 30));
    locator.registerSingleton<TrendsBloc>(bloc);
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => EnergyUnitProvider(usesKilojoules: false),
        child: MaterialApp(
          localizationsDelegates: const [
            S.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          supportedLocales: S.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: HomeTiles(
                weightKg: 81,
                bodyWeightUnit: BodyWeightUnit.kg,
                waterMl: 750,
                waterGoalMl: 2000,
                loadWeights: () async => const [],
                loadExpenditure: () async => const <ExpenditureDay>[],
                fasting: const FastingTileView(state: FastingIdle()),
                homeLoads: homeLoads,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return bloc;
  }

  testWidgets('a rebuild of Home asks Trends nothing; only a Home load does', (
    tester,
  ) async {
    layout.value = (order: ['goal'], hidden: const {});
    final homeLoads = StreamController<Object?>();
    addTearDown(homeLoads.close);
    final bloc = await pump(tester, homeLoads: homeLoads.stream);
    tester.element(find.byType(HomeTiles)).markNeedsBuild();
    await tester.pump();
    expect(bloc.events, isNot(contains(isA<RefreshTrendsEvent>())));
    homeLoads.add(null);
    await tester.pump();
    expect(bloc.events, contains(isA<RefreshTrendsEvent>()));
  });

  testWidgets('the goal with no target: the profile\'s pace, as on You', (
    tester,
  ) async {
    TrendsOverview.loadPace = () async =>
        (goal: UserWeightGoalEntity.loseWeight, kgPerWeek: -0.4);
    layout.value = (order: ['goal'], hidden: const {});
    await pump(tester);
    final goal = tester.widget<TrendTile>(
      find.byWidgetPredicate(
        (w) => w is TrendTile && w.id == 'home-trends-tile-goal',
      ),
    );
    expect((goal.value, goal.suffix), ('Losing', '0.4 kg a week'));
  });

  testWidgets('a goal kept in the history after the pace reaches the tile', (
    tester,
  ) async {
    TrendsOverview.loadPace = () async =>
        (goal: UserWeightGoalEntity.maintainWeight, kgPerWeek: 0.0);
    final history = <GoalRecord>[];
    TrendsOverview.loadPhases = () async => (plan: null, history: history);
    layout.value = (order: ['goal'], hidden: const {});
    await pump(tester);
    TrendTile goal() => tester.widget<TrendTile>(
      find.byWidgetPredicate(
        (w) => w is TrendTile && w.id == 'home-trends-tile-goal',
      ),
    );
    expect(goal().suffix, isNot(contains('since')));

    // As GoalActions.complete: the history is kept after the pace's change.
    history.add(
      GoalRecord(
        kind: PhaseKind.cut,
        start: DateTime(2026, 1, 5),
        end: DateTime(2026, 4, 6),
        startKg: 88,
        endKg: 81.2,
        targetKg: 81,
      ),
    );
    PhaseStore.changes.value++;
    await tester.pumpAndSettle();
    expect((goal().value, goal().suffix), ('Maintain', 'since Apr 6'));
  });

  testWidgets('none of them until added', (tester) async {
    final bloc = await pump(tester);
    expect(find.text('Goal'), findsNothing);
    expect(find.textContaining('left vs right'), findsNothing);
    // Nothing of Trends' is read for them.
    expect(bloc.events, isEmpty);
  });

  testWidgets('added ones as Home\'s tiles, in the order arranged', (
    tester,
  ) async {
    TrendsOverview.loadMeasurements = () async => [
      for (final (metric, cm) in [
        (BodyMetric.leftArm, 35.0),
        (BodyMetric.rightArm, 36.2),
      ])
        Measurement(id: metric.name, date: day(-1), metric: metric, value: cm),
    ];
    // As the editor saves it: the full order, the rest still off.
    layout.value = (
      order: [
        'sides',
        'weight',
        'expenditure',
        'water',
        'fasting',
        ...homeTrendTileNames.keys.where((id) => id != 'sides'),
      ],
      hidden: {...homeTrendTileNames.keys.where((id) => id != 'sides')},
    );
    await pump(tester);
    final sides = find.byWidgetPredicate(
      (w) => w is TrendTile && w.id == 'home-trends-tile-sides',
    );
    expect(sides, findsOne);
    expect(tester.widget<TrendTile>(sides).label, 'Arms · left vs right');
    expect(tester.widget<TrendTile>(sides).value, '1.2');
    expect(tester.widget<TrendTile>(sides).suffix, 'cm · right bigger');
    // Spoken as on Trends.
    expect(
      find.bySemanticsLabel('Arms left versus right, 1.2 cm, right bigger'),
      findsOne,
    );
    // First, beside the weight.
    expect(
      tester.getTopLeft(sides).dx,
      lessThan(tester.getTopLeft(find.byType(WeightTile)).dx),
    );
    expect(find.text('Goal'), findsNothing);

    await tester.tap(sides);
    await tester.pumpAndSettle();
    expect(find.byType(SideComparePage), findsOne);
  });

  testWidgets('an average says so in its title, Home having no span line', (
    tester,
  ) async {
    layout.value = (
      order: [
        'calories',
        'weight',
        'expenditure',
        'water',
        'fasting',
        ...homeTrendTileNames.keys.where((id) => id != 'calories'),
      ],
      hidden: {...homeTrendTileNames.keys.where((id) => id != 'calories')},
    );
    await pump(tester);
    final calories = find.byWidgetPredicate(
      (w) => w is TrendTile && w.id == 'home-trends-tile-calories',
    );
    expect(tester.widget<TrendTile>(calories).label, 'Calories · avg');
    expect(tester.widget<TrendTile>(calories).hint, 'Open Calories');
    expect(find.bySemanticsLabel('Calories, nothing logged'), findsOne);
  });

  testWidgets('waist to height reads the height it is taken against', (
    tester,
  ) async {
    loadBodyFrame = () async =>
        (heightCm: 170.0, gender: UserGenderEntity.female);
    TrendsOverview.loadMeasurements = () async => [
      Measurement(id: 'w', date: day(-1), metric: BodyMetric.waist, value: 85),
    ];
    layout.value = (
      order: ['weight', 'expenditure', 'water', 'fasting', 'waist'],
      hidden: const {},
    );
    await pump(tester);
    final waist = tester.widget<TrendTile>(
      find.byWidgetPredicate(
        (w) => w is TrendTile && w.id == 'home-trends-tile-waist',
      ),
    );
    expect(waist.value, '0.50');
    expect(waist.suffix, 'increased risk');
  });

  testWidgets('read again after Home reloads, kept in place meanwhile', (
    tester,
  ) async {
    layout.value = (
      order: ['weight', 'expenditure', 'water', 'fasting', 'goal'],
      hidden: const {},
    );
    final homeLoads = StreamController<Object?>();
    addTearDown(homeLoads.close);
    final bloc = await pump(tester, homeLoads: homeLoads.stream);
    final goal = find.byWidgetPredicate(
      (w) => w is TrendTile && w.id == 'home-trends-tile-goal',
    );
    expect(goal, findsOne);

    // Something logged: Home reloads, and the tiles ask Trends again.
    homeLoads.add(null);
    await tester.pump();
    expect(bloc.events, contains(isA<RefreshTrendsEvent>()));

    // While Trends reloads, the tile stays where it was.
    // (A frame for the state to reach the builder, one to build.)
    bloc.show(const TrendsLoading());
    await tester.pump();
    await tester.pump();
    expect(goal, findsOne);
  });

  testWidgets('a micro tile\'s summary is worked out once a load, not each '
      'build', (tester) async {
    var summaries = 0;
    summarizeMicros =
        (intakes, days, user, {dayStartMinutes = 0, goalHistory}) {
          summaries++;
          return summarizeNutrients(
            intakes,
            days,
            user,
            dayStartMinutes: dayStartMinutes,
            goalHistory: goalHistory,
          );
        };
    locator.registerSingleton<IntakeDataSource>(_Intakes());
    layout.value = (
      order: ['weight', 'expenditure', 'water', 'fasting', 'fibre'],
      hidden: const {},
    );
    await pump(tester);
    expect(
      find.byWidgetPredicate(
        (w) => w is TrendTile && w.id == 'home-trends-tile-fibre',
      ),
      findsOne,
    );
    final first = summaries;
    expect(first, greaterThan(0));
    tester.element(find.byType(HomeTiles)).markNeedsBuild();
    await tester.pumpAndSettle();
    expect(summaries, first);
  });
}
