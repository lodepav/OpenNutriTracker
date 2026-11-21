import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/tracked_day_entity.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_service.dart';
import 'package:opennutritracker/fork/display/home_tiles.dart';
import 'package:opennutritracker/fork/display/week_bars.dart';
import 'package:opennutritracker/fork/trends/trends_widgets.dart';
import 'package:provider/provider.dart';

// A past day edited in the Diary, or a weigh-in, reaches Home as a Home
// load, not as a change to anything Home passes these widgets.
void main() {
  testWidgets('the 7-day bars read the days again on a Home load', (
    tester,
  ) async {
    final homeLoads = StreamController<Object?>.broadcast();
    addTearDown(homeLoads.close);
    var loads = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WeekBars(
            today: DateTime(2026, 11, 21, 9),
            todayKcal: 1200,
            todayGoalKcal: 2400,
            load: (from, to) async {
              loads++;
              return const <TrackedDayEntity>[];
            },
            homeLoads: homeLoads.stream,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(loads, 1);

    homeLoads.add(null);
    await tester.pumpAndSettle();
    expect(loads, 2);
  });

  testWidgets('the Expenditure tile reads the estimate again on a Home load', (
    tester,
  ) async {
    final homeLoads = StreamController<Object?>.broadcast();
    addTearDown(homeLoads.close);
    var kcal = 2500.0;
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => EnergyUnitProvider(usesKilojoules: false),
        child: MaterialApp(
          home: Scaffold(
            body: ExpenditureTile(
              load: () async => [
                ExpenditureDay(
                  date: DateTime(2026, 11, 21),
                  expenditureKcal: kcal,
                  intakeKcal: 2300,
                  settled: true,
                ),
              ],
              homeLoads: homeLoads.stream,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    String shown() => tester.widget<TrendTile>(find.byType(TrendTile)).value;
    expect(shown(), '2500');

    kcal = 2650;
    homeLoads.add(null);
    await tester.pumpAndSettle();
    expect(shown(), '2650');
  });
}
