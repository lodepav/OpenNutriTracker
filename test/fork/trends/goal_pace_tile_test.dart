import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/user_weight_goal_entity.dart';
import 'package:opennutritracker/core/domain/entity/weight_log_entity.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/core/utils/locator.dart';
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
      'Goal, Losing 0.4 kg a week',
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
    expect((tile.value, tile.note), ('Losing', '0.4 kg a week'));
  });

  testWidgets('at 1x on a 360 dp phone the pace shows whole', (tester) async {
    await pumpOnPhone(
      tester,
      ChangeNotifierProvider(
        create: (_) => EnergyUnitProvider(usesKilojoules: false),
        child: Builder(
          builder: (context) {
            final goal = trendTiles(
              context,
              loaded(),
              dates: [day(0)],
              history: const [],
              micros: null,
              measurements: null,
              goal: (progress: null, plan: null, since: null, pace: _losing),
              open: (_) {},
            ).firstWhere((t) => t.id == 'trends-tile-goal');
            // As Trends lays a row out: two tiles across, 12 dp margins.
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: goal),
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
    expect(tileText(tester, 'goal'), contains('Losing 0.4 kg a week'));
    expect(cutText(tester), isEmpty);
  });
}
