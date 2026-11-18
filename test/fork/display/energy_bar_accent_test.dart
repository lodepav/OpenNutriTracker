import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/fork/display/week_bars.dart';
import 'package:opennutritracker/core/domain/entity/tracked_day_entity.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/app_theme.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/fork/display/contrast.dart';
import 'package:opennutritracker/fork/display/day_totals_card.dart';
import 'package:opennutritracker/fork/display/macro_foods.dart';
import 'package:opennutritracker/fork/meal_detail/food_page.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:provider/provider.dart';

import '../../fixture/intake_entity_fixtures.dart';

// The energy bar in the picked accent at 3:1 on its own track, the same
// on the Diary, the food page and the foods behind a total.

const _yellow = Color(0xFFFDD835);
final _palette = AppPalette.light.withAccent(_yellow);
final _track = _palette.surfaceMuted;

Widget _app(Widget child) => ChangeNotifierProvider<EnergyUnitProvider>(
  create: (_) => EnergyUnitProvider(usesKilojoules: false),
  child: MaterialApp(
    theme: buildAppTheme(_palette),
    localizationsDelegates: const [
      S.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: S.supportedLocales,
    home: Scaffold(body: SingleChildScrollView(child: child)),
  ),
);

void main() {
  testWidgets('Diary: the energy bar is the picked yellow, at 3:1 on its '
      'track', (tester) async {
    await tester.pumpWidget(
      _app(
        DayTotalsCard(
          trackedDay: TrackedDayEntity(
            day: DateTime(2026, 10, 25),
            calorieGoal: 2000,
            caloriesTracked: 0,
          ),
          intakes: const [],
        ),
      ),
    );
    final energy = tester
        .widgetList<LinearProgressIndicator>(
          find.byType(LinearProgressIndicator),
        )
        .first;
    // one energy colour: the Diary's as the food page's and Home's
    expect(energy.color, weekBarColors(_yellow, _track).today);
    expect(contrastRatio(energy.color!, _track), greaterThanOrEqualTo(3));
  });

  testWidgets('food page: eaten and added energy both at 3:1 on the track, '
      'and apart', (tester) async {
    await tester.pumpWidget(
      _app(
        TodayAfterAdding(
          day: DateTime(2026, 10, 25),
          kcal: 200,
          carbs: 10,
          fat: 2,
          protein: 5,
          load: (_) async => (
            eaten: (kcal: 900.0, carbs: 100.0, fat: 50.0, protein: 60.0),
            goal: (kcal: 2000.0, carbs: 250.0, fat: 70.0, protein: 120.0),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final trackBox = find
        .byWidgetPredicate((w) => w is ColoredBox && w.color == _track)
        .first;
    final fills = tester
        .widgetList<ColoredBox>(
          find.descendant(of: trackBox, matching: find.byType(ColoredBox)),
        )
        .map((b) => Color.alphaBlend(b.color, _track))
        .toList();
    // eaten, added, then what is left of the goal (transparent)
    final eaten = fills[0], added = fills[1];
    expect(contrastRatio(eaten, _track), greaterThanOrEqualTo(3));
    expect(contrastRatio(added, _track), greaterThanOrEqualTo(3));
    expect(contrastRatio(eaten, added), greaterThanOrEqualTo(1.5));
  });

  testWidgets('foods behind the energy total: bars at 3:1 on the track', (
    tester,
  ) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => EnergyUnitProvider(usesKilojoules: false),
        child: MaterialApp(
          theme: buildAppTheme(_palette),
          localizationsDelegates: const [
            S.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: S.supportedLocales,
          home: MacroFoodsPage(
            initial: FoodsMetric.energy,
            intakes: [intakeOf('Oats', 80, protein100: 13, carbs100: 60)],
            totals: const {},
            day: DateTime(2026, 10, 25),
          ),
        ),
      ),
    );
    final bars = tester.widgetList<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(bars, isNotEmpty);
    for (final bar in bars) {
      final color = bar.valueColor!.value!;
      expect(contrastRatio(color, _track), greaterThanOrEqualTo(3));
    }
  });
}
