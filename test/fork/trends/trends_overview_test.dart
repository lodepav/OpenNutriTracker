import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/tracked_day_entity.dart';
import 'package:opennutritracker/core/domain/entity/weight_log_entity.dart';
import 'package:opennutritracker/core/utils/calc/unit_calc.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/trends/presentation/bloc/trends_bloc.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_service.dart';
import 'package:opennutritracker/fork/display/display_prefs.dart';
import 'package:opennutritracker/fork/trends/detail_widgets.dart';
import 'package:opennutritracker/fork/trends/trends_overview.dart';
import 'package:opennutritracker/generated/l10n.dart';

import 'trends_harness.dart';

// Seam S120: Trends is a grid of tiles (variant A); a tile opens its page
// (variant B), the Calories tile the macro-stacked page (variant C).

TrackedDayEntity _logged(
  int offset, {
  double kcal = 2572.6,
  double goal = 2925,
  double carbs = 69.5,
  double fat = 81,
  double protein = 93,
}) => TrackedDayEntity(
  day: day(offset),
  calorieGoal: goal,
  caloriesTracked: kcal,
  carbsTracked: carbs,
  carbsGoal: 259,
  fatTracked: fat,
  fatGoal: 81,
  proteinTracked: protein,
  proteinGoal: 110,
);

class _Service extends Fake implements AdaptiveService {
  final List<ExpenditureDay> history;
  _Service(this.history);

  @override
  Future<List<ExpenditureDay>> expenditureHistory() async => history;

  @override
  Future<double> formulaKcal() async => 2860;
}

void main() {
  tearDown(() async {
    await locator.reset();
    DisplayPrefs.macroOrder.value = DisplayPrefs.upstreamOrder;
  });

  testWidgets('water hidden in Settings: no tile, no row in the table', (
    tester,
  ) async {
    addTearDown(() => DisplayPrefs.showWater.value = true);
    await pumpTrends(
      tester,
      loaded(days: [_logged(0)], waterByDay: {day(0): 1200}),
    );
    expect(find.byKey(const ValueKey('trends-tile-water')), findsOne);

    DisplayPrefs.showWater.value = false;
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('trends-tile-water')), findsNothing);
    await openTile(tester, 'calories');
    expect(find.textContaining('Water'), findsNothing);
  });

  testWidgets('the tiles: averages of the logged days against the goals', (
    tester,
  ) async {
    await pumpTrends(
      tester,
      loaded(
        // One day of the seven: unlogged days are not days of fasting.
        days: [_logged(0), _logged(-3, kcal: 0, goal: 9000)],
        waterByDay: {day(0): 1200, day(-1): 800},
        waterGoalMl: 1900,
      ),
    );

    // Energy cut, as energyValue is everywhere; grams rounded (S114).
    expect(tileText(tester, 'calories'), contains('2572 / 2925 kcal'));
    expect(tileText(tester, 'carbs'), contains('70 / 259 g'));
    expect(tileText(tester, 'fat'), contains('81 / 81 g'));
    expect(tileText(tester, 'protein'), contains('93 / 110 g'));
    expect(tileText(tester, 'water'), contains('1000 / 1900 ml'));
    expect(tileText(tester, 'weight'), contains('–'));
    expect(
      find.textContaining('Last 7 days, 1 logged', skipOffstage: false),
      findsOneWidget,
    );
    expect(find.textContaining('day streak'), findsOneWidget);
  });

  testWidgets('the macro tiles follow the macro order', (tester) async {
    DisplayPrefs.macroOrder.value = [Macro.protein, Macro.carbs, Macro.fat];
    await pumpTrends(tester, loaded(days: [_logged(0)]));
    double y(String m) =>
        tester.getTopLeft(find.byKey(ValueKey('trends-tile-$m'))).dy;
    double x(String m) =>
        tester.getTopLeft(find.byKey(ValueKey('trends-tile-$m'))).dx;
    // Row three is protein, carbs; row four fat, water.
    expect(y('protein'), y('carbs'));
    expect(x('protein'), lessThan(x('carbs')));
    expect(y('fat'), greaterThan(y('protein')));
    expect(y('fat'), y('water'));
  });

  testWidgets('a pill reloads Trends at its range', (tester) async {
    final bloc = await pumpTrends(tester, loaded(days: [_logged(0)]));
    await tester.tap(find.text('1M'));
    await tester.tap(find.text('All'));
    // The range shown is not picked again.
    await tester.tap(find.text('1W'));
    expect(bloc.events, const [
      LoadTrendsEvent(rangeDays: 30),
      LoadTrendsEvent(rangeDays: 0),
    ]);
  });

  testWidgets('Calories: the days stacked by macro, how they went, the '
      'macro shares', (tester) async {
    await pumpTrends(
      tester,
      loaded(
        days: [_logged(0, carbs: 100, fat: 20, protein: 50, kcal: 1560)],
        weight: [
          WeightLogEntity(date: day(-6), weightKg: 80),
          WeightLogEntity(date: day(0), weightKg: 79.4),
        ],
        targetWeightKg: 75,
      ),
    );
    await openTile(tester, 'calories');

    expect(find.widgetWithText(AppBar, 'Calories'), findsOneWidget);
    expect(find.text('1560 kcal'), findsOneWidget);
    expect(find.text('2925 kcal'), findsOneWidget);
    expect(find.textContaining('· 1 of 7 days logged'), findsOneWidget);
    final chart = tester.widget<BarChart>(find.byType(BarChart)).data;
    expect(chart.barGroups, hasLength(7));
    final today = chart.barGroups.last.barRods.single;
    expect(today.toY, 1560);
    // Carbs, fat, protein from the bottom, scaled to the energy logged.
    expect([for (final s in today.rodStackItems) s.toY], [800, 1160, 1560]);
    expect(
      today.rodStackItems.first.color,
      isNot(today.rodStackItems.last.color),
    );
    expect(chart.barGroups.first.barRods.single.toY, 0);
    expect(chart.extraLinesData.horizontalLines.single.y, 2925);
    final tip = chart.barTouchData.touchTooltipData.getTooltipItem(
      chart.barGroups.last,
      6,
      today,
      0,
    )!;
    expect(tip.text, startsWith('1560 kcal\n'));

    String row(String label) {
      final r = find.ancestor(
        of: find.text(label),
        matching: find.byType(TrendRow),
      );
      return tester.widget<TrendRow>(r).value;
    }

    await tester.scrollUntilVisible(
      find.widgetWithText(TrendRow, 'Highest'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(row('On target (within 10%)'), '0 of 1 day');
    expect(row('Under'), '1 day');
    expect(row('Over'), '0 days');
    expect(row('Highest'), startsWith('1560 kcal · '));
    // 400, 180 and 200 kcal of 780; the goals' 1036, 729 and 440 of 2205.
    await tester.scrollUntilVisible(
      find.widgetWithText(TrendRow, 'Protein'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(row('Carbs'), '51% · goal 47%');
    expect(row('Fat'), '23% · goal 33%');
    expect(row('Protein'), '26% · goal 20%');
    // The split bar above the rows is drawn, a segment a macro.
    final segments = find.descendant(
      of: find.byType(ClipRRect),
      matching: find.byType(ColoredBox),
    );
    expect(segments, findsNWidgets(3));
    for (final e in segments.evaluate()) {
      expect(e.size!.height, greaterThan(0));
    }
  });

  testWidgets('kJ: the tile, the bars and the goal in kJ, titled Energy', (
    tester,
  ) async {
    await pumpTrends(
      tester,
      loaded(days: [_logged(0, kcal: 1039, goal: 2000)]),
      kj: true,
    );
    expect(tileText(tester, 'calories'), contains('Energy · avg'));
    expect(tileText(tester, 'calories'), contains('4347 / 8368 kJ'));

    await openTile(tester, 'calories');
    expect(find.widgetWithText(AppBar, 'Energy'), findsOneWidget);
    final chart = tester.widget<BarChart>(find.byType(BarChart)).data;
    expect(
      chart.barGroups.last.barRods.single.toY,
      closeTo(UnitCalc.kcalToKj(1039), 1e-6),
    );
    expect(
      chart.extraLinesData.horizontalLines.single.y,
      closeTo(UnitCalc.kcalToKj(2000), 1e-6),
    );
    expect(find.text('4347 kJ'), findsOneWidget);
  });

  testWidgets('kJ: the macro stack is in kJ too', (tester) async {
    await pumpTrends(
      tester,
      loaded(days: [_logged(0, carbs: 100, fat: 20, protein: 50, kcal: 1560)]),
      kj: true,
    );
    await openTile(tester, 'calories');
    final rod = tester
        .widget<BarChart>(find.byType(BarChart))
        .data
        .barGroups
        .last
        .barRods
        .single;
    expect(
      [for (final s in rod.rodStackItems) s.toY],
      [
        for (final kcal in [800.0, 1160.0, 1560.0])
          closeTo(UnitCalc.kcalToKj(kcal), 1e-6),
      ],
    );
  });

  testWidgets('Calories: top foods, and weekdays against the weekend', (
    tester,
  ) async {
    // A whole week logged has both.
    await pumpTrends(
      tester,
      loaded(days: [for (var i = -6; i <= 0; i++) _logged(i)]),
    );
    await openTile(tester, 'calories');
    await tester.scrollUntilVisible(find.text('Top foods'), 200);
    expect(find.text('No foods logged in this range.'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Weekdays and weekends'), 200);
    await tester.scrollUntilVisible(
      find.text('Weekends run about the same as weekdays.'),
      200,
    );
  });

  testWidgets('a macro\'s page: its days against the goal; protein per kg', (
    tester,
  ) async {
    await pumpTrends(
      tester,
      loaded(
        days: [_logged(-1, protein: 160), _logged(0, protein: 80)],
        weight: [WeightLogEntity(date: day(-1), weightKg: 80)],
      ),
    );
    await openTile(tester, 'protein');
    // 110 g a day: 80 under, 160 over.
    await tester.scrollUntilVisible(find.text('0 of 2 days'), 200);
    await tester.scrollUntilVisible(find.text('1.4 g/kg'), 200);
    expect(find.text('1.5 g/kg'), findsOneWidget);
    expect(find.text('1.4 g/kg'), findsOneWidget);
  });

  testWidgets('a macro\'s page: average, goal and change, bars a day', (
    tester,
  ) async {
    final bloc = await pumpTrends(
      tester,
      loaded(days: [_logged(-6, carbs: 200), _logged(0, carbs: 260)]),
    );
    await openTile(tester, 'carbs');

    expect(find.widgetWithText(AppBar, 'Carbs'), findsOneWidget);
    String stat(String label) {
      final merged = tester.getSemantics(find.text(label));
      return merged.label;
    }

    expect(stat('Average'), contains('230 g'));
    expect(stat('Goal'), contains('259 g'));
    expect(stat('Change'), contains('+60 g'));
    final chart = tester.widget<BarChart>(find.byType(BarChart)).data;
    // From a little under the lowest to a little over the highest: the
    // bars start at the chart's floor, an empty day is none.
    expect(chart.minY, closeTo(200 - 60 * 0.15, 1e-9));
    expect(chart.maxY, closeTo(260 + 60 * 0.15, 1e-9));
    final rods = [for (final g in chart.barGroups) g.barRods.single];
    expect([for (final r in rods) r.fromY], everyElement(chart.minY));
    expect(
      [for (final r in rods) r.toY],
      [200, ...List.filled(5, chart.minY), 260],
    );
    expect(chart.extraLinesData.horizontalLines.single.y, 259);

    // The page's pills move the range too.
    await tester.tap(find.text('3M'));
    expect(bloc.events, const [LoadTrendsEvent(rangeDays: 90)]);
  });

  testWidgets('a page follows the range the bloc loads', (tester) async {
    final bloc = await pumpTrends(tester, loaded(days: [_logged(0)]));
    await openTile(tester, 'fat');
    expect(
      tester.widget<BarChart>(find.byType(BarChart)).data.barGroups,
      hasLength(7),
    );
    bloc.show(loaded(rangeDays: 30, days: [_logged(0)]));
    await tester.pumpAndSettle();
    expect(
      tester.widget<BarChart>(find.byType(BarChart)).data.barGroups,
      hasLength(30),
    );
  });

  testWidgets('Weight: the trend, upstream\'s card and the weigh-ins', (
    tester,
  ) async {
    await pumpTrends(
      tester,
      loaded(
        weight: [
          WeightLogEntity(date: day(-30), weightKg: 81),
          WeightLogEntity(date: day(-6), weightKg: 80),
          WeightLogEntity(date: day(0), weightKg: 79.4),
        ],
      ),
    );
    expect(
      tileText(tester, 'weight'),
      matches(RegExp(r'\d\d\.\d kg · -0\.\d\d/wk')),
    );
    await openTile(tester, 'weight');

    expect(find.text('Trend weight'), findsOneWidget);
    expect(find.textContaining('Trend: '), findsOneWidget);
    expect(find.byTooltip('Add entry'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('79.4 kg'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Weigh-ins'), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);
    // The weigh-in row, and the Highest tile may read the same.
    expect(find.text('80.0 kg'), findsWidgets);
    // Outside the week.
    expect(find.text('81.0 kg'), findsNothing);
  });

  testWidgets('Weight: the change chips, the four tiles, the goal tile', (
    tester,
  ) async {
    await pumpTrends(
      tester,
      loaded(
        targetWeightKg: 75,
        weight: [
          for (var i = -10; i <= 0; i += 2)
            WeightLogEntity(date: day(i), weightKg: 80 - i * 0.1),
        ],
      ),
    );
    expect(tileText(tester, 'goal'), contains('Goal'));
    expect(tileText(tester, 'goal'), contains('kg to go'));
    await openTile(tester, 'weight');
    final scroll = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(
      find.text('Days weighed in'),
      200,
      scrollable: scroll,
    );
    // Within the trend's ten days, a change; past them, none.
    Finder chip(String text) => find.descendant(
      of: find.byType(ChangeChips),
      matching: find.text(text),
    );
    expect(chip('-0.4'), findsOneWidget);
    expect(chip('–'), findsNWidgets(3));
    expect(find.text('Highest'), findsOneWidget);
    expect(find.text('Lowest'), findsOneWidget);
    // Four weigh-ins in the week, more than half: no nudge.
    expect(find.textContaining('4 of 7 days'), findsOneWidget);
    expect(find.text('Daily weigh-ins steady the trend'), findsNothing);
    expect(find.text('To your goal'), findsOneWidget);
    // Ten days of trend: no 30 days' pace to date the goal by.
    expect(find.text('under 30 days of trend'), findsOneWidget);
  });

  testWidgets('Water: its average and goal over upstream\'s chart', (
    tester,
  ) async {
    await pumpTrends(
      tester,
      loaded(waterByDay: {day(0): 1500}, waterGoalMl: 2000),
    );
    await openTile(tester, 'water');
    expect(
      tester.getSemantics(find.text('Average')).label,
      contains('1500 ml'),
    );
    expect(find.byType(LineChart), findsOneWidget);
  });

  testWidgets('nothing logged: the pages say so', (tester) async {
    await pumpTrends(tester, loaded());
    expect(tileText(tester, 'calories'), contains('–'));
    await openTile(tester, 'calories');
    expect(find.text('Nothing logged in this range.'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await openTile(tester, 'water');
    expect(find.text('No water logged in this range.'), findsOneWidget);
  });

  testWidgets('expenditure and balance from the estimate', (tester) async {
    final history = [
      for (var i = -6; i <= 0; i++)
        ExpenditureDay(
          date: day(i),
          expenditureKcal: 3000 + i * 10.0,
          intakeKcal: i.isEven ? 2500 : null,
          settled: true,
        ),
    ];
    final state = loaded();
    final bloc = SeededTrendsBloc(state);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          S.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: S.supportedLocales,
        home: Scaffold(
          body: BlocProvider<TrendsBloc>.value(
            value: bloc,
            child: TrendsOverview(
              state: state,
              weightCard: (_) => const SizedBox(),
              waterCard: (_) => const SizedBox(),
              cards: const {},
              service: _Service(history),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tileText(tester, 'expenditure'), contains('3000 kcal/day'));
    // Logged on days -6, -4, -2 and 0: 2500 less 2940, 2960, 2980, 3000.
    expect(tileText(tester, 'balance'), contains('-470 kcal/day'));

    await openTile(tester, 'balance');
    expect(tester.getSemantics(find.text('Average')).label, contains('-470'));
    expect(tester.getSemantics(find.text('Logged')).label, contains('4'));
    final bars = tester.widget<BarChart>(find.byType(BarChart)).data.barGroups;
    expect(bars.last.barRods.single.toY, -500);
    expect(bars[1].barRods.single.toY, 0);
    // 10000 eaten less 11880 burnt over the four logged days.
    expect(tester.getSemantics(find.text('Total')).label, contains('-1880'));
    final scroll = find.byType(Scrollable).last;
    await tester.scrollUntilVisible(
      find.text('From the balance'),
      200,
      scrollable: scroll,
    );
    String row(String label) =>
        tester.widget<TrendRow>(find.widgetWithText(TrendRow, label)).value;
    expect(row('In deficit'), '4 of 4 days');
    expect(row('In surplus'), '0 days');
    expect(row('Eaten a day'), '2500 kcal');
    expect(row('Burnt a day'), '2970 kcal');
    // -470 a day for the week, at 7700 kcal a kg.
    expect(find.text('-0.4 kg', findRichText: true), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await openTile(tester, 'expenditure');
    final table = find.byKey(const ValueKey('expenditure-changes'));
    String cellOf(String over, int column) {
      final cells = [
        for (final t in tester.widgetList<Text>(
          find.descendant(of: table, matching: find.byType(Text)),
        ))
          t.data!,
      ];
      return cells[cells.indexOf(over) + column];
    }

    expect(cellOf('3 days', 1), '+30 kcal');
    expect(cellOf('3 days', 2), '2970 kcal');
    // TalkBack reads each row as one sentence.
    expect(
      find.bySemanticsLabel('Over 3 days: up 30 kcal, from 2970 kcal'),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel('Over 7 days: not enough history yet'),
      findsOneWidget,
    );
    // The history reaches back only six days.
    expect(cellOf('7 days', 1), '–');

    final scrollable = find.byType(Scrollable).last;
    await tester.scrollUntilVisible(
      find.text('What is expenditure?'),
      200,
      scrollable: scrollable,
    );
    expect(find.text('Last 7 days'), findsOneWidget);
    // Over the four logged days: 2500 eaten, 2970 burnt.
    expect(find.text('2500'), findsOneWidget);
    expect(find.text('470'), findsOneWidget);
    expect(find.text('from weight lost'), findsOneWidget);
    expect(find.text('2970'), findsWidgets);
    expect(find.text('enough for a steady estimate'), findsOneWidget);
    // 3000 against the formula's 2860.
    expect(find.text('yours runs 5% higher'), findsOneWidget);

    await tester.ensureVisible(find.text('What is expenditure?'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('What is expenditure?'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });
}
