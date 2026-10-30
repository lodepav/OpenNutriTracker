import 'package:opennutritracker/core/domain/entity/user_gender_entity.dart';
import 'package:opennutritracker/fork/body/waist_ratio.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/body_weight_unit_entity.dart';
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
import 'package:opennutritracker/fork/trends/trends_overview.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:provider/provider.dart';

import '../trends/trends_harness.dart';

// Trends' tiles Home can add, off until switched on.

void main() {
  final layout = LayoutStore.current(homeTilesKey);

  tearDown(() async {
    layout.value = (order: const [], hidden: const {});
    TrendsOverview.loadMeasurements = () async => const [];
    loadBodyFrame = () async => null;
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
      (w) => w is HomeTile && w.identifier == 'home-trends-tile-sides',
    );
    expect(sides, findsOne);
    expect(tester.widget<HomeTile>(sides).title, 'Arms · left vs right');
    expect(tester.widget<HomeTile>(sides).value, '1.2');
    expect(tester.widget<HomeTile>(sides).note, 'cm · right bigger');
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
    final waist = tester.widget<HomeTile>(
      find.byWidgetPredicate(
        (w) => w is HomeTile && w.identifier == 'home-trends-tile-waist',
      ),
    );
    expect(waist.value, '0.50');
    expect(waist.note, 'increased risk');
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
      (w) => w is HomeTile && w.identifier == 'home-trends-tile-goal',
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
}
