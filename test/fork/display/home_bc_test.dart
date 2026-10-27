import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/body_weight_unit_entity.dart';
import 'package:opennutritracker/core/domain/entity/tracked_day_entity.dart';
import 'package:opennutritracker/core/domain/entity/weight_log_entity.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/features/fasting/domain/entity/fasting_session_entity.dart';
import 'package:opennutritracker/features/fasting/presentation/bloc/fasting_bloc.dart';
import 'package:opennutritracker/fork/screens/home/dashboard_widget.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_service.dart';
import 'package:opennutritracker/fork/display/display_prefs.dart';
import 'package:opennutritracker/fork/display/home_tiles.dart';
import 'package:opennutritracker/fork/layout/home_layout.dart';
import 'package:opennutritracker/fork/layout/layout_store.dart';
import 'package:opennutritracker/fork/trends/trend_stats.dart' show TrendMetric;
import 'package:opennutritracker/fork/trends/trends_widgets.dart'
    show Sparkline;
import 'package:opennutritracker/fork/display/week_bars.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:provider/provider.dart';

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

DashboardWidget _dashboard() => DashboardWidget(
  totalKcalSupplied: 1800,
  totalKcalBurned: 300,
  totalKcalDaily: 2500,
  totalKcalLeft: 1000,
  totalCarbsIntake: 200,
  totalFatsIntake: 79,
  totalProteinsIntake: 42,
  totalCarbsGoal: 251,
  totalFatsGoal: 70,
  totalProteinsGoal: 120,
  forkDay: _today,
);

void main() {
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
    expect(find.bySemanticsLabel(RegExp(r'^\w+day: ')), findsNWidgets(7));
    expect(find.bySemanticsLabel('Tuesday: 2100 of 2400 kcal'), findsOne);
    expect(find.bySemanticsLabel('Monday: 0 of 0 kcal'), findsOne);
    expect(find.bySemanticsLabel('Sunday: 1800 of 2500 kcal'), findsOne);
  });

  group('the tiles', () {
    testWidgets('before a weigh-in: the weight logged, no expenditure', (
      tester,
    ) async {
      await tester.pumpWidget(_app(_tiles()));
      await tester.pump();
      expect(find.textContaining('81.0 kg'), findsOne);
      expect(find.textContaining('/wk'), findsNothing);
      expect(find.textContaining('after a weigh-in'), findsOne);
      expect(find.textContaining('750 / 2000 ml'), findsOne);
      expect(find.textContaining('Not fasting'), findsOne);
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
      expect(find.textContaining('· 0.00 kg/wk'), findsOne);
      expect(find.textContaining('2712 kcal/day'), findsOne);
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
    tearDown(() {
      DisplayPrefs.showWater.value = true;
      DisplayPrefs.showFasting.value = true;
    });

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

  group('the card', () {
    setUp(() => DisplayPrefs.homeShowsEaten.value = false);
    tearDown(() => DisplayPrefs.homeShowsEaten.value = false);

    testWidgets('the ring counts what is left, or what was eaten', (
      tester,
    ) async {
      await tester.pumpWidget(_app(_dashboard()));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel(RegExp(r'^1000 ')), findsOne);
      expect(find.text('+300'), findsOne);
      expect(find.text('2500'), findsOne);

      DisplayPrefs.homeShowsEaten.value = true;
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('1800 kcal eaten'), findsOne);
    });

    testWidgets('each macro left of its goal, or over it in red', (
      tester,
    ) async {
      await tester.pumpWidget(_app(_dashboard()));
      await tester.pumpAndSettle();
      expect(
        find.bySemanticsLabel(RegExp(r': 200 of 251 g, 51 g left$')),
        findsOne,
      );
      expect(
        find.bySemanticsLabel(RegExp(r': 79 of 70 g, 9 g over$')),
        findsOne,
      );
      expect(
        find.bySemanticsLabel(RegExp(r': 42 of 120 g, 78 g left$')),
        findsOne,
      );

      final error = Theme.of(
        tester.element(find.byType(DashboardWidget)),
      ).colorScheme.error;
      final bars = tester
          .widgetList<LinearProgressIndicator>(
            find.byType(LinearProgressIndicator),
          )
          .map((b) => (b.valueColor as AlwaysStoppedAnimation<Color?>).value);
      expect([for (final c in bars) c == error], [false, true, false]);
    });
  });
}
