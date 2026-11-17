import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/body_weight_unit_entity.dart';
import 'package:opennutritracker/core/domain/entity/tracked_day_entity.dart';
import 'package:opennutritracker/core/domain/entity/weight_log_entity.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/features/fasting/domain/entity/fasting_session_entity.dart';
import 'package:opennutritracker/features/fasting/presentation/bloc/fasting_bloc.dart';
import 'package:opennutritracker/fork/screens/home/dashboard_widget.dart';
import 'package:opennutritracker/fork/adaptive/activity_credit.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_service.dart';
import 'package:opennutritracker/fork/display/display_prefs.dart';
import 'package:opennutritracker/fork/display/home_tiles.dart';
import 'package:opennutritracker/fork/layout/home_layout.dart';
import 'package:opennutritracker/fork/layout/layout_store.dart';
import 'package:opennutritracker/fork/trends/trend_stats.dart' show TrendMetric;
import 'package:opennutritracker/fork/trends/trends_widgets.dart'
    show Sparkline, keepUnits;
import 'package:opennutritracker/fork/display/week_bars.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:provider/provider.dart';

import '../../helpers/ux_checks.dart' show pumpOnPhone;

final _today = DateTime(2026, 10, 25);

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

Future<List<WeightLogEntity>> _noWeights() async => const [];

Future<List<ExpenditureDay>> _noExpenditure() async => const [];

Widget _tiles({
  Future<List<WeightLogEntity>> Function() loadWeights = _noWeights,
  Future<List<ExpenditureDay>> Function() loadExpenditure = _noExpenditure,
  void Function(BuildContext, TrendMetric)? openTrend,
}) => HomeTiles(
  weightKg: 81,
  bodyWeightUnit: BodyWeightUnit.kg,
  waterMl: 750,
  waterGoalMl: 2000,
  loadWeights: loadWeights,
  loadExpenditure: loadExpenditure,
  fasting: const FastingTileView(state: FastingIdle()),
  openTrend: openTrend ?? (_, _) {},
);

DashboardWidget _dashboard({
  double burned = 300,
  ActivityCredit credit = ActivityCredit.added,
}) => DashboardWidget(
  totalKcalSupplied: 1800,
  totalKcalBurned: burned,
  totalKcalDaily: 2500,
  totalKcalLeft: 1000,
  totalCarbsIntake: 200,
  totalFatsIntake: 79,
  totalProteinsIntake: 42,
  totalCarbsGoal: 251,
  totalFatsGoal: 70,
  totalProteinsGoal: 120,
  forkDay: _today,
  loadCredit: () async => credit,
);

void main() {
  // Water and fasting are off until switched on; these tests show them.
  setUp(() {
    DisplayPrefs.showWater.value = true;
    DisplayPrefs.showFasting.value = true;
  });
  tearDown(() {
    DisplayPrefs.showWater.value = false;
    DisplayPrefs.showFasting.value = false;
  });

  testWidgets('the week: six stored days, then today as Home has it', (
    tester,
  ) async {
    DateTime? from;
    await tester.pumpWidget(
      _app(
        WeekBars(
          today: _today,
          todayKcal: 1800,
          todayGoalKcal: 2500,
          load: (f, to) async {
            from = f;
            return [
              TrackedDayEntity(
                day: DateTime(2026, 10, 20),
                calorieGoal: 2400,
                caloriesTracked: 2100,
              ),
              // Stale: today comes from Home's figures.
              TrackedDayEntity(
                day: _today,
                calorieGoal: 2400,
                caloriesTracked: 900,
              ),
            ];
          },
        ),
      ),
    );
    await tester.pump();
    expect(from, DateTime(2026, 10, 19));
    // One node for the week; a day with no goal says no "of 0".
    expect(
      find.bySemanticsLabel(
        'Last 7 days: Monday 0 kcal, Tuesday 2100 of 2400 kcal, '
        'Wednesday 0 kcal, Thursday 0 kcal, Friday 0 kcal, Saturday 0 kcal, '
        'Sunday 1800 of 2500 kcal',
      ),
      findsOne,
    );
  });

  group('the tiles', () {
    testWidgets('before a weigh-in: the weight logged, no expenditure', (
      tester,
    ) async {
      await tester.pumpWidget(_app(_tiles()));
      await tester.pump();
      expect(find.textContaining('81.0 kg'), findsOne);
      expect(find.textContaining('a week'), findsNothing);
      expect(find.textContaining('after a weigh-in'), findsOne);
      expect(find.textContaining('750 ${keepUnits('/ 2000 ml')}'), findsOne);
      expect(find.textContaining('Not fasting'), findsOne);
    });

    testWidgets('at 1x on a 360 dp phone the weekly change leaves no word '
        'alone on a line', (tester) async {
      final now = DateTime.now();
      await pumpOnPhone(
        tester,
        ChangeNotifierProvider<EnergyUnitProvider>(
          create: (_) => EnergyUnitProvider(usesKilojoules: false),
          child: _tiles(
            loadWeights: () async => [
              for (var i = 7; i >= 0; i--)
                WeightLogEntity(
                  date: DateTime(now.year, now.month, now.day - i),
                  weightKg: 87.1 + i * 0.03,
                ),
            ],
          ),
        ),
        textScale: 1,
      );
      tester.view.physicalSize = const Size(360 * 2.625, 2340);
      await tester.pumpAndSettle();
      final paragraph = tester
          .renderObjectList<RenderParagraph>(find.byType(RichText))
          .firstWhere((p) => p.text.toPlainText().contains('week'));
      final text = paragraph.text.toPlainText();
      expect(text, contains('\u2212'));
      // The paragraph's text laid out at its width, for its lines.
      final lines = TextPainter(
        text: paragraph.text,
        textDirection: TextDirection.ltr,
        textScaler: paragraph.textScaler,
      )..layout(maxWidth: paragraph.size.width);
      addTearDown(lines.dispose);
      var start = 0;
      while (start < text.length) {
        final line = lines.getLineBoundary(TextPosition(offset: start));
        final words = text
            .substring(line.start, line.end)
            .replaceAll('\u00A0', ' ')
            .trim()
            .split(RegExp(r'\s+'));
        expect(words.length, greaterThan(1), reason: 'a lone word in "$text"');
        if (line.end <= start) break;
        start = line.end;
      }
    });

    testWidgets('the trend, its weekly change, and the expenditure', (
      tester,
    ) async {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      await tester.pumpWidget(
        _app(
          _tiles(
            // The same weight a fortnight: the trend sits on it.
            loadWeights: () async => [
              for (var i = 14; i >= 0; i--)
                WeightLogEntity(
                  date: DateTime(today.year, today.month, today.day - i),
                  weightKg: 79.5,
                ),
            ],
            loadExpenditure: () async => [
              ExpenditureDay(
                date: today.subtract(const Duration(days: 1)),
                expenditureKcal: 2600,
                settled: true,
              ),
              ExpenditureDay(
                date: today,
                expenditureKcal: 2712.4,
                settled: true,
              ),
            ],
          ),
        ),
      );
      await tester.pump();
      expect(find.textContaining('79.5'), findsOne);
      expect(find.textContaining('81 kg'), findsNothing);
      expect(find.textContaining('· 0\u00A0kg\u00A0a\u00A0week'), findsOne);
      expect(find.textContaining('2712 ${keepUnits('kcal/day')}'), findsOne);
      expect(find.byType(Sparkline), findsNWidgets(2));
    });
  });

  testWidgets('a tile opens its Trends page; the + logs (S145)', (
    tester,
  ) async {
    final opened = <TrendMetric>[];
    await tester.pumpWidget(
      _app(_tiles(openTrend: (_, metric) => opened.add(metric))),
    );
    await tester.pumpAndSettle();
    for (final title in ['Weight trend', 'Expenditure', 'Water']) {
      await tester.tap(find.text(title));
    }
    expect(opened, [
      TrendMetric.weight,
      TrendMetric.expenditure,
      TrendMetric.water,
    ]);

    await tester.tap(find.byTooltip('Log water'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOne);
    expect(opened, hasLength(3));
    expect(find.byTooltip('Log a weigh-in'), findsOne);
  });

  testWidgets('a fast under way: the time left and how far along', (
    tester,
  ) async {
    final start = DateTime(2026, 10, 25, 8);
    await tester.pumpWidget(
      _app(
        FastingTileView(
          state: FastingActive(
            session: FastingSessionEntity(
              id: 'f',
              startedAt: start,
              targetDurationMinutes: 16 * 60,
            ),
            now: start.add(const Duration(hours: 4, minutes: 30)),
          ),
        ),
      ),
    );
    expect(find.textContaining('11h 30m left'), findsOne);
    final bar = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(bar.value, closeTo(4.5 / 16, 1e-9));
  });

  group('water and fasting hidden in Settings', () {
    testWidgets('one hidden: the other fills the row; both: no row', (
      tester,
    ) async {
      await tester.pumpWidget(_app(_tiles()));
      await tester.pumpAndSettle();
      final water = find.bySemanticsIdentifier('home-water-chip');
      final fasting = find.bySemanticsIdentifier('home-fasting-chip');
      expect(water, findsOne);
      expect(fasting, findsOne);
      final half = tester.getSize(water).width;

      DisplayPrefs.showWater.value = false;
      await tester.pumpAndSettle();
      expect(water, findsNothing);
      expect(tester.getSize(fasting).width, greaterThan(half * 1.5));

      DisplayPrefs.showFasting.value = false;
      await tester.pumpAndSettle();
      expect(fasting, findsNothing);

      DisplayPrefs.showWater.value = true;
      await tester.pumpAndSettle();
      expect(water, findsOne);
      expect(fasting, findsNothing);
    });
  });

  testWidgets('the tiles as arranged: fasting first, weight hidden (S162)', (
    tester,
  ) async {
    final layout = LayoutStore.current(homeTilesKey);
    addTearDown(() => layout.value = (order: const [], hidden: const {}));
    layout.value = (
      order: ['fasting', 'expenditure', 'water', 'weight'],
      hidden: {'weight'},
    );
    await tester.pumpWidget(_app(_tiles()));
    await tester.pumpAndSettle();
    final fasting = find.bySemanticsIdentifier('home-fasting-chip');
    final water = find.bySemanticsIdentifier('home-water-chip');
    expect(find.byType(WeightTile), findsNothing);
    // Fasting, then expenditure; water alone on the second row.
    expect(tester.getTopLeft(fasting).dx, lessThan(100));
    expect(
      tester.getTopLeft(water).dy,
      greaterThan(tester.getTopLeft(fasting).dy),
    );
    expect(
      tester.getSize(water).width,
      greaterThan(tester.getSize(fasting).width * 1.5),
    );
  });

  group('spoken in words', () {
    test('the weight trend: down, up, steady, or no week yet', () {
      expect(
        weightSpoken('87.1 kg', -0.16, BodyWeightUnit.kg),
        'Weight trend, 87.1 kg, down 0.16 kg a week',
      );
      expect(
        weightSpoken('192.0 lb', 0.16, BodyWeightUnit.lb),
        'Weight trend, 192.0 lb, up 0.35 lb a week',
      );
      expect(
        weightSpoken('87.1 kg', 0.001, BodyWeightUnit.kg),
        'Weight trend, 87.1 kg, steady',
      );
      expect(
        weightSpoken('81.0 kg', null, BodyWeightUnit.kg),
        'Weight trend, 81.0 kg',
      );
    });

    test('expenditure, and fasting in hours and minutes', () {
      expect(expenditureSpoken(3045, 'kcal'), 'Expenditure, 3045 kcal a day');
      expect(expenditureSpoken(null, 'kcal'), 'Expenditure, after a weigh-in');
      expect(
        fastingSpoken(const Duration(hours: 11, minutes: 30)),
        'Fasting, 11 hours 30 minutes left',
      );
      expect(
        fastingSpoken(const Duration(hours: 1, minutes: 1)),
        'Fasting, 1 hour 1 minute left',
      );
      expect(
        fastingSpoken(const Duration(minutes: 5)),
        'Fasting, 5 minutes left',
      );
      expect(fastingSpoken(null), 'Fasting, no fast under way');
    });

    testWidgets('each tile is one node: its words, its hint, its tap', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final opened = <TrendMetric>[];
      await tester.pumpWidget(
        _app(_tiles(openTrend: (_, metric) => opened.add(metric))),
      );
      await tester.pumpAndSettle();
      SemanticsNode node(String id) =>
          tester.getSemantics(find.bySemanticsIdentifier(id));
      expect(node('home-weight-chip').label, 'Weight trend, 81.0 kg');
      expect(node('home-weight-chip').hint, 'Open the weight trend');
      expect(
        node('home-expenditure-tile').label,
        'Expenditure, after a weigh-in',
      );
      expect(node('home-water-chip').label, 'Water, 750 of 2000 milliliters');
      expect(node('home-fasting-chip').label, 'Fasting, no fast under way');
      for (final id in ['home-weight-chip', 'home-water-chip']) {
        expect(node(id).label, isNot(matches(RegExp('[·/]'))));
      }
      final water = node('home-water-chip');
      expect(water, isSemantics(isButton: true, hasTapAction: true));
      water.owner!.performAction(water.id, SemanticsAction.tap);
      expect(opened, [TrendMetric.water]);
      // The + stays a button of its own.
      expect(find.byTooltip('Log water'), findsOne);
      handle.dispose();
    });
  });

  testWidgets('two tiles to a row, one past 1.5x text', (tester) async {
    tester.view.physicalSize = const Size(1080, 6000);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app(_tiles()));
    await tester.pumpAndSettle();
    Offset at(Type tile) => tester.getTopLeft(find.byType(tile));
    expect(at(ExpenditureTile).dy, at(WeightTile).dy);

    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpAndSettle();
    expect(at(ExpenditureTile).dx, at(WeightTile).dx);
    expect(at(ExpenditureTile).dy, greaterThan(at(WeightTile).dy));
  });

  testWidgets('at 2x in the app\'s font a 180-wide tile keeps its units '
      'whole', (tester) async {
    await pumpOnPhone(
      tester,
      Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 180,
          child: Column(
            children: [
              HomeTile(
                identifier: 'w',
                title: 'Weight trend',
                value: '87.1 kg',
                note: '· -0.16 kg/wk',
                onTap: () {},
                onAction: () {},
              ),
              HomeTile(
                identifier: 'e',
                title: 'Expenditure',
                value: '3045',
                note: 'kcal/day',
              ),
            ],
          ),
        ),
      ),
    );
    // Every box of the unit's text on one line.
    void whole(String unit) {
      for (final paragraph in tester.renderObjectList<RenderParagraph>(
        find.byType(RichText),
      )) {
        final text = paragraph.text.toPlainText();
        // The text as read, each character's offset in the text as laid out.
        final offsets = [
          for (final (i, c) in text.split('').indexed)
            if (c != '⁠') i,
        ];
        final read = [
          for (final i in offsets) text[i] == ' ' ? ' ' : text[i],
        ].join();
        final start = read.indexOf(unit);
        if (start < 0) continue;
        final tops = {
          for (final box in paragraph.getBoxesForSelection(
            TextSelection(
              baseOffset: offsets[start],
              extentOffset: offsets[start + unit.length - 1] + 1,
            ),
          ))
            box.top,
        };
        expect(tops, hasLength(1), reason: '"$unit" split in "$text"');
        return;
      }
      fail('"$unit" not shown');
    }

    whole('-0.16 kg/wk');
    whole('kcal/day');
  });

  group('the card', () {
    setUp(() => DisplayPrefs.homeShowsEaten.value = false);
    tearDown(() => DisplayPrefs.homeShowsEaten.value = false);

    testWidgets('the ring counts what is left, or what was eaten', (
      tester,
    ) async {
      await tester.pumpWidget(_app(_dashboard()));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel(RegExp(r'^1000 ')), findsOne);
      expect(find.text('Activity'), findsOne);
      expect(find.text('Burned'), findsNothing);
      expect(find.text('+300'), findsOne);
      expect(find.text('2500'), findsOne);

      DisplayPrefs.homeShowsEaten.value = true;
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('1800 kcal eaten'), findsOne);
    });

    testWidgets('today\'s totals and the week are two nodes, in words', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_app(_dashboard()));
      await tester.pumpAndSettle();
      expect(
        find.bySemanticsLabel(
          'Eaten 1800 kcal, activity adds 300 kcal, goal 2500 kcal',
        ),
        findsOne,
      );
      expect(find.bySemanticsLabel(RegExp(r'\+')), findsNothing);
      expect(find.bySemanticsLabel(RegExp(r'^Last 7 days: ')), findsOne);
      expect(
        find.bySemanticsLabel(RegExp(r'Eaten.*Last 7 days')),
        findsNothing,
      );
      handle.dispose();
    });

    testWidgets('in kilojoules, the totals are spoken in kJ', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        ChangeNotifierProvider<EnergyUnitProvider>(
          create: (_) => EnergyUnitProvider(usesKilojoules: true),
          child: MaterialApp(
            localizationsDelegates: const [
              S.delegate,
              ...GlobalMaterialLocalizations.delegates,
            ],
            supportedLocales: S.supportedLocales,
            home: Scaffold(body: SingleChildScrollView(child: _dashboard())),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.bySemanticsLabel(
          'Eaten 7531 kJ, activity adds 1255 kJ, goal 10460 kJ',
        ),
        findsOne,
      );
      handle.dispose();
    });

    group('activity', () {
      Future<void> pumpKj(WidgetTester tester, Widget child) =>
          tester.pumpWidget(
            ChangeNotifierProvider<EnergyUnitProvider>(
              // A new provider, not the kcal one pumped before.
              key: UniqueKey(),
              create: (_) => EnergyUnitProvider(usesKilojoules: true),
              child: MaterialApp(
                localizationsDelegates: const [
                  S.delegate,
                  ...GlobalMaterialLocalizations.delegates,
                ],
                supportedLocales: S.supportedLocales,
                home: Scaffold(body: SingleChildScrollView(child: child)),
              ),
            ),
          );

      testWidgets('past the daily cap: added up to it', (tester) async {
        final handle = tester.ensureSemantics();
        final capped = _dashboard(
          burned: 1000,
          credit: ActivityCredit.dailyCapped,
        );
        await tester.pumpWidget(_app(capped));
        await tester.pumpAndSettle();
        expect(find.text('Activity, up to'), findsOne);
        expect(find.text('+800'), findsOne);
        expect(
          find.bySemanticsLabel(
            'Eaten 1800 kcal, activity adds up to 800 kcal, goal 2500 kcal',
          ),
          findsOne,
        );

        await pumpKj(tester, capped);
        await tester.pumpAndSettle();
        expect(find.text('+3347'), findsOne);
        expect(
          find.bySemanticsLabel(RegExp('activity adds up to 3347 kJ,')),
          findsOne,
        );
        handle.dispose();
      });

      testWidgets('under the cap, the burn is added in full', (tester) async {
        await tester.pumpWidget(
          _app(_dashboard(credit: ActivityCredit.dailyCapped)),
        );
        await tester.pumpAndSettle();
        expect(find.text('Activity'), findsOne);
        expect(find.text('+300'), findsOne);
      });

      testWidgets('a target that leaves it out: not added, no "+"', (
        tester,
      ) async {
        final handle = tester.ensureSemantics();
        await tester.pumpWidget(
          _app(_dashboard(credit: ActivityCredit.notCounted)),
        );
        await tester.pumpAndSettle();
        expect(find.text('Activity, not added'), findsOne);
        expect(find.text('300'), findsOne);
        expect(find.text('+300'), findsNothing);
        expect(
          find.bySemanticsLabel(
            'Eaten 1800 kcal, activity 300 kcal, not added, goal 2500 kcal',
          ),
          findsOne,
        );
        handle.dispose();
      });
    });

    testWidgets('each macro left of its target, or over it, uncoloured', (
      tester,
    ) async {
      await tester.pumpWidget(_app(_dashboard()));
      await tester.pumpAndSettle();
      expect(
        find.bySemanticsLabel(RegExp(r'^Carbs: 200 of 251 g, 51 g left$')),
        findsOne,
      );
      expect(
        find.bySemanticsLabel(RegExp(r'^Fat: 79 of 70 g, 9 g over$')),
        findsOne,
      );
      expect(
        find.bySemanticsLabel(RegExp(r'^Protein: 42 of 120 g, 78 g left$')),
        findsOne,
      );

      // Each name in Title Case, above its figure and bar.
      final bars = find.byType(LinearProgressIndicator);
      for (final (i, name) in ['Carbs', 'Fat', 'Protein'].indexed) {
        expect(
          tester.getBottomLeft(find.text(name)).dy,
          lessThanOrEqualTo(tester.getTopLeft(bars.at(i)).dy),
        );
      }

      final theme = Theme.of(tester.element(find.byType(DashboardWidget)));
      final colours = tester
          .widgetList<LinearProgressIndicator>(bars)
          .map((b) => (b.valueColor as AlwaysStoppedAnimation<Color?>).value);
      expect(colours, isNot(contains(theme.colorScheme.error)));
      Color? figure(String text) =>
          (tester.widget<RichText>(find.text(text, findRichText: true)).text
                  as TextSpan)
              .children!
              .whereType<TextSpan>()
              .first
              .style
              ?.color;
      expect(figure('9 g over'), figure('51 g left'));
      expect(figure('9 g over'), isNot(theme.colorScheme.error));
    });
  });
}
