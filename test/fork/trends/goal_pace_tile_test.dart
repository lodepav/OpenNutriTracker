import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/user_weight_goal_entity.dart';
import 'package:opennutritracker/core/domain/entity/weight_log_entity.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/trends/presentation/bloc/trends_bloc.dart';
import 'package:opennutritracker/fork/goal/goal_progress.dart';
import 'package:opennutritracker/fork/trends/detail_widgets.dart';
import 'package:opennutritracker/fork/trends/trends_overview.dart';
import 'package:provider/provider.dart';

import '../../helpers/ux_checks.dart';
import 'trends_harness.dart';

// With no target and no goal running, Trends says the profile's pace as
// the You tile does, not "No goal".

const ProfilePace _losing = (
  goal: UserWeightGoalEntity.loseWeight,
  kgPerWeek: -0.4,
);

void main() {
  final readPace = TrendsOverview.loadPace;
  tearDown(() async {
    TrendsOverview.loadPace = readPace;
    await locator.reset();
  });

  testWidgets('the Goal tile reads the profile\'s pace, not "No goal"', (
    tester,
  ) async {
    TrendsOverview.loadPace = () async => _losing;
    await pumpTrends(
      tester,
      loaded(weight: [WeightLogEntity(date: day(0), weightKg: 80)]),
    );
    await showTile(tester, 'goal');
    expect(tileText(tester, 'goal'), contains('Losing 0.4 kg a week'));
    expect(
      tester.getSemantics(find.byKey(const ValueKey('trends-tile-goal'))).label,
      'Goal, Losing 0.4 kg a week, No end date',
    );
    expect(
      tester.getSemantics(find.byKey(const ValueKey('trends-tile-goal'))).hint,
      'Plan a goal',
    );
  });

  testWidgets('"To your goal" reads the profile\'s pace, not "No goal"', (
    tester,
  ) async {
    TrendsOverview.loadPace = () async => _losing;
    await pumpTrends(
      tester,
      loaded(weight: [WeightLogEntity(date: day(0), weightKg: 80)]),
    );
    await openTile(tester, 'weight');
    await tester.scrollUntilVisible(
      find.text('To your goal'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    final figure = find.ancestor(
      of: find.text('To your goal'),
      matching: find.byType(FigureTile),
    );
    final tile = tester.widget<FigureTile>(figure);
    expect((tile.value, tile.unit), ('Losing', '0.4 kg a week'));
    // As on every goal tile: no end date, and a goal to plan.
    expect(
      find.descendant(of: figure, matching: find.text('No end date')),
      findsOne,
    );
    expect(
      find.descendant(of: figure, matching: find.text('Plan a goal')),
      findsOne,
    );
  });

  testWidgets('a maintaining pace reads "Maintain", as a plan does', (
    tester,
  ) async {
    TrendsOverview.loadPace = () async =>
        (goal: UserWeightGoalEntity.maintainWeight, kgPerWeek: 0.0);
    await pumpTrends(
      tester,
      loaded(weight: [WeightLogEntity(date: day(0), weightKg: 80)]),
    );
    await openTile(tester, 'weight');
    await tester.scrollUntilVisible(
      find.text('To your goal'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    final tile = tester.widget<FigureTile>(
      find.ancestor(
        of: find.text('To your goal'),
        matching: find.byType(FigureTile),
      ),
    );
    expect(tile.value, 'Maintain');
    expect(tile.unit, isNull);
  });

  /// The Goal tile of [state] and [goal] as Trends lays a row out at 1x on
  /// a 360 dp phone: two tiles across, 12 dp margins.
  Future<void> pumpTile(
    WidgetTester tester,
    TrendsLoaded state,
    TrendsGoal goal,
  ) async {
    await pumpOnPhone(
      tester,
      ChangeNotifierProvider(
        create: (_) => EnergyUnitProvider(usesKilojoules: false),
        child: Builder(
          builder: (context) {
            final tile = trendTiles(
              context,
              state,
              dates: [day(0)],
              history: const [],
              micros: null,
              measurements: null,
              goal: goal,
              open: (_) {},
            ).firstWhere((t) => t.id == 'trends-tile-goal');
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: tile),
                  const SizedBox(width: 8),
                  const Expanded(child: SizedBox()),
                ],
              ),
            );
          },
        ),
      ),
      textScale: 1,
    );
    tester.view
      ..physicalSize = const Size(360, 800)
      ..devicePixelRatio = 1;
    await tester.pump();
  }

  testWidgets('at 1x on a 360 dp phone the pace shows whole', (tester) async {
    await pumpTile(tester, loaded(), (
      progress: null,
      nowKg: null,
      plan: null,
      history: const [],
      pace: _losing,
    ));
    expect(tileText(tester, 'goal'), contains('Losing 0.4 kg a week'));
    expect(cutText(tester), isEmpty);
  });

  testWidgets('at 1x on a 360 dp phone the tallest goal tile shows whole', (
    tester,
  ) async {
    // A target with no plan: the way, the day at the 30-day pace and the
    // bar; no offer of a goal, as its tap opens Goal progress.
    final trend = [for (var i = 0; i <= 30; i++) 89.4 - 0.05 * i];
    await pumpTile(
      tester,
      loaded(
        targetWeightKg: 80,
        weight: [WeightLogEntity(date: day(0), weightKg: trend.last)],
      ),
      (
        progress: GoalProgress(
          start: GoalStart(date: day(-30), kg: 89.4, targetKg: 80),
          nowKg: trend.last,
          paceKgPerWeek: -0.4,
          trend: trend,
          today: day(0),
        ),
        nowKg: trend.last,
        plan: null,
        history: const [],
        pace: _losing,
      ),
    );
    expect(tileText(tester, 'goal'), contains('kg to go'));
    expect(tileText(tester, 'goal'), contains('at your 30-day pace'));
    expect(tileText(tester, 'goal'), isNot(contains('Plan a goal')));
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(cutText(tester), isEmpty);
  });
}
