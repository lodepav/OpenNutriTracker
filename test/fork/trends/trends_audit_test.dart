import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/tracked_day_entity.dart';
import 'package:opennutritracker/core/domain/entity/weight_log_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_tracked_day_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_user_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_weight_log_usecase.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/app_theme.dart';
import 'package:opennutritracker/core/utils/calc/unit_calc.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/trends/presentation/bloc/trends_bloc.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_service.dart';
import 'package:opennutritracker/fork/display/contrast.dart';
import 'package:opennutritracker/fork/display/display_prefs.dart';
import 'package:opennutritracker/fork/display/macro_foods.dart';
import 'package:opennutritracker/fork/layout/width_cap.dart';
import 'package:opennutritracker/fork/report/nutrient_explorer.dart';
import 'package:opennutritracker/fork/screens/trends/trends_page.dart';
import 'package:opennutritracker/fork/trends/expenditure_detail.dart';
import 'package:opennutritracker/fork/trends/macro_contributors.dart';
import 'package:opennutritracker/fork/trends/nutrient_trends.dart';
import 'package:opennutritracker/fork/trends/trend_stats.dart';
import 'package:opennutritracker/fork/trends/trends_overview.dart';
import 'package:opennutritracker/fork/trends/trends_widgets.dart';
import 'package:opennutritracker/fork/trends/weight_detail.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:provider/provider.dart';

import '../../fixture/intake_entity_fixtures.dart';
import '../../helpers/ux_checks.dart';
import 'trends_harness.dart';

// The Trends audit (2026-11-18): day picking without touch, micro summaries
// once a load, water from Home in fl oz, rows at 2x, the user's accent at
// 3:1, no motion under Remove animations, a width cap.

class _FakeWeights extends Fake implements GetWeightLogUsecase {}

class _FakeDays extends Fake implements GetTrackedDayUsecase {}

class _Service extends Fake implements AdaptiveService {
  @override
  Future<List<ExpenditureDay>> expenditureHistory() async => [
    for (var i = -6; i <= 0; i++)
      ExpenditureDay(
        date: day(i),
        expenditureKcal: 3000,
        intakeKcal: i.isEven ? 2500 : 3300,
        settled: true,
      ),
  ];
}

TrackedDayEntity _logged(int offset) => TrackedDayEntity(
  day: day(offset),
  calorieGoal: 2000,
  caloriesTracked: 2000,
  carbsTracked: 200,
  carbsGoal: 250,
  fatTracked: 60,
  fatGoal: 70,
  proteinTracked: 100,
  proteinGoal: 110,
);

/// A chart's own node, by its name.
SemanticsNode _chart(String label) =>
    find.semantics.byLabel(label).evaluate().single;

/// Yellow, the lightest preset accent: 1.4:1 on the light card.
const _yellow = Color(0xFFFDD835);

Widget _app(Widget home, {ThemeData? theme}) => ChangeNotifierProvider(
  create: (_) => EnergyUnitProvider(usesKilojoules: false),
  child: MaterialApp(
    theme: theme,
    localizationsDelegates: const [
      S.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: S.supportedLocales,
    home: Scaffold(body: home),
  ),
);

Widget _overview(TrendsLoaded state) => BlocProvider<TrendsBloc>.value(
  value: SeededTrendsBloc(state),
  child: TrendsOverview(
    state: state,
    weightCard: (_) => const SizedBox(),
    waterCard: (_) => const SizedBox(),
    cards: const {},
    service: _Service(),
  ),
);

void main() {
  tearDown(() async {
    TrendsOverview.loadIntakes = intakesBetween;
    TrendsOverview.loadAllDays = allTrackedDays;
    summarizeMicros = summarizeNutrients;
    DisplayPrefs.showWater.value = false;
    await locator.reset();
  });

  group('picking a day on a macro chart', () {
    final dates = [for (var d = 20; d <= 26; d++) DateTime(2026, 10, d)];

    Future<SemanticsNode> pump(WidgetTester tester) async {
      await tester.pumpWidget(
        _app(
          ListView(
            children: [
              MacroDaysAndFoods(
                metric: FoodsMetric.carbs,
                series: [for (var i = 0; i < 7; i++) i == 3 ? null : 200.0 + i],
                dates: dates,
                goal: 250,
                color: Colors.orange,
                chartLabel: 'Carbs chart',
                load: (_, _) async => [intakeOf('Rice', 100, carbs100: 70)],
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      return _chart('Carbs chart');
    }

    Future<void> act(WidgetTester tester, SemanticsAction action) async {
      final node = _chart('Carbs chart');
      node.owner!.performAction(node.id, action);
      await tester.pumpAndSettle();
    }

    String value(WidgetTester tester) =>
        _chart('Carbs chart').getSemanticsData().value;

    testWidgets('increase and decrease move the day, its foods follow', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final node = await pump(tester);
      final data = node.getSemanticsData();
      expect(data.hasAction(SemanticsAction.increase), isTrue);
      expect(data.hasAction(SemanticsAction.decrease), isTrue);
      expect(find.text('Last 7 days'), findsOneWidget);

      // From none, up picks the first day.
      await act(tester, SemanticsAction.increase);
      expect(value(tester), 'Oct 20, 200 g');
      expect(find.text('Tue, Oct 20'), findsOneWidget);

      await act(tester, SemanticsAction.increase);
      await act(tester, SemanticsAction.increase);
      await act(tester, SemanticsAction.increase);
      expect(value(tester), 'Oct 23, nothing logged');
      await act(tester, SemanticsAction.decrease);
      expect(value(tester), 'Oct 22, 202 g');
      semantics.dispose();
    });

    testWidgets('at either end the day stays picked', (tester) async {
      final semantics = tester.ensureSemantics();
      await pump(tester);
      // From none, down picks the last day.
      await act(tester, SemanticsAction.decrease);
      expect(value(tester), 'Oct 26, 206 g');
      await act(tester, SemanticsAction.increase);
      expect(value(tester), 'Oct 26, 206 g');
      expect(find.text('Mon, Oct 26'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('a chart with no day to pick has no actions', (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        _app(
          DailyBarChart(
            values: const [1, 2],
            dates: dates.take(2).toList(),
            color: Colors.orange,
            unit: 'g',
            label: 'Fibre chart',
          ),
        ),
      );
      final data = _chart('Fibre chart').getSemanticsData();
      expect(data.hasAction(SemanticsAction.increase), isFalse);
      semantics.dispose();
    });
  });

  testWidgets('micro summaries are worked out once a load, not each build', (
    tester,
  ) async {
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
    TrendsOverview.loadIntakes = (_, _) async => [
      intakeOf('Oats', 100, carbs100: 60),
    ];
    await tester.pumpWidget(_app(_overview(loaded(days: [_logged(0)]))));
    await tester.pumpAndSettle();
    final first = summaries;
    expect(first, greaterThan(0));
    // A rebuild of the grid, as a setting changed.
    DisplayPrefs.showWater.value = true;
    await tester.pumpAndSettle();
    DisplayPrefs.showWater.value = false;
    await tester.pumpAndSettle();
    expect(summaries, first);
    expect(find.byKey(const ValueKey('trends-tile-fibre')), findsOneWidget);
  });

  testWidgets('water opened from a Home tile charts fl oz too', (tester) async {
    final bloc = SeededTrendsBloc(
      loaded(waterByDay: {day(0): 200}, waterGoalMl: 2000, imperial: true),
    );
    locator
      ..registerSingleton<TrendsBloc>(bloc)
      ..registerSingleton<GetUserUsecase>(FakeGetUserUsecase())
      ..registerSingleton<GetWeightLogUsecase>(_FakeWeights())
      ..registerSingleton<GetTrackedDayUsecase>(_FakeDays());
    await tester.pumpWidget(
      _app(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => openTrendFromHome(context, TrendMetric.water),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final chart = tester.widget<LineChart>(find.byType(LineChart));
    expect(
      chart.data.lineBarsData.first.spots.last.y,
      closeTo(UnitCalc.mlToFlOz(200), 0.001),
    );
  });

  testWidgets('at 2x on a 360 dp phone a weigh-in row cuts nothing', (
    tester,
  ) async {
    final state = loaded(
      weight: [
        for (var i = -6; i < 0; i++)
          WeightLogEntity(date: day(i), weightKg: 180.3 + i / 10),
      ],
    );
    final dates = windowDates(day(0), 7);
    await pumpOnPhone(
      tester,
      Builder(
        builder: (context) => ListView(
          padding: const EdgeInsets.all(16),
          children: weighInRows(
            context,
            state,
            dates,
            WeightTrendStats.of(state.weight, dates),
          ),
        ),
      ),
    );
    tester.view
      ..physicalSize = const Size(360, 800)
      ..devicePixelRatio = 1;
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(cutText(tester), isEmpty);
  });

  testWidgets('at 2x on a 360 dp phone a long streak cuts nothing', (
    tester,
  ) async {
    final run = [for (var i = -149; i <= 0; i++) _logged(i)];
    TrendsOverview.loadAllDays = () async => run;
    await pumpOnPhone(
      tester,
      ChangeNotifierProvider(
        create: (_) => EnergyUnitProvider(usesKilojoules: false),
        child: _overview(loaded(days: run.skip(143).toList())),
      ),
    );
    tester.view
      ..physicalSize = const Size(360, 800)
      ..devicePixelRatio = 1;
    await tester.pumpAndSettle();
    expect(find.text('150 day streak'), findsOneWidget);
    final streak = tester.renderObject<RenderParagraph>(
      find.text('150 day streak'),
    );
    expect(streak.didExceedMaxLines, isFalse);
  });

  group('the user\'s accent', () {
    final theme = buildAppTheme(AppPalette.light.withAccent(_yellow));

    testWidgets('every tile drawn in the accent is the chart-safe accent', (
      tester,
    ) async {
      DisplayPrefs.showWater.value = false;
      late BuildContext context;
      late List<TrendTile> tiles;
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (c) {
              context = c;
              tiles = trendTiles(
                c,
                loaded(days: [_logged(0)]),
                dates: windowDates(day(0), 7),
                history: const [],
                micros: null,
                measurements: null,
                open: (_) {},
              );
              return const SizedBox();
            },
          ),
          theme: theme,
        ),
      );
      final accent = chartAccent(context);
      expect(contrastRatio(accent, AppPalette.light.surface), greaterThan(3));
      Sparkline spark(String id) =>
          tiles.firstWhere((t) => t.id == 'trends-tile-$id').chart as Sparkline;
      for (final id in ['calories', 'weight', 'expenditure', 'fibre']) {
        expect(spark(id).color, accent, reason: id);
      }
      expect(spark('balance').negativeColor, accent);
    });

    testWidgets('the expenditure line is the chart-safe accent', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          ExpenditureChart(
            history: await _Service().expenditureHistory(),
            dates: windowDates(day(0), 7),
          ),
          theme: theme,
        ),
      );
      final line = tester
          .widget<LineChart>(find.byType(LineChart))
          .data
          .lineBarsData
          .first;
      expect(line.color, chartAccent(tester.element(find.byType(LineChart))));
    });
  });

  testWidgets('under Remove animations the charts do not move', (tester) async {
    final dates = windowDates(day(0), 7);
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: _app(
          ListView(
            children: [
              DailyBarChart(
                values: const [1, 2, 3, 4, 5, 6, 7],
                dates: dates,
                color: Colors.orange,
                unit: 'g',
                label: 'Fibre chart',
              ),
              ExpenditureChart(
                history: await _Service().expenditureHistory(),
                dates: dates,
              ),
            ],
          ),
        ),
      ),
    );
    expect(
      tester.widget<BarChart>(find.byType(BarChart)).duration,
      Duration.zero,
    );
    expect(
      tester.widget<LineChart>(find.byType(LineChart)).duration,
      Duration.zero,
    );
  });

  testWidgets('under Remove animations the water and Calories charts do '
      'not move', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    DisplayPrefs.showWater.value = true;
    await pumpTrends(
      tester,
      loaded(days: [_logged(0)], waterByDay: {day(0): 500}),
    );
    await openTile(tester, 'water');
    expect(
      tester.widget<LineChart>(find.byType(LineChart)).duration,
      Duration.zero,
    );
    await tester.pageBack();
    await tester.pumpAndSettle();
    await openTile(tester, 'calories');
    expect(
      tester.widget<BarChart>(find.byType(BarChart).first).duration,
      Duration.zero,
    );
  });

  testWidgets('water and the warning note come from the palette', (
    tester,
  ) async {
    for (final palette in [AppPalette.light, AppPalette.dark]) {
      await tester.pumpWidget(
        // A new app each: one theme would ease into the other.
        MaterialApp(
          key: ValueKey(palette.brightness),
          theme: buildAppTheme(palette),
          home: Builder(
            builder: (context) {
              expect(waterColor(context), palette.water);
              expect(noteColor(context), palette.warningText);
              return const SizedBox();
            },
          ),
        ),
      );
    }
    expect(AppPalette.light.water, const Color(0xFF2F7DBF));
    expect(AppPalette.dark.water, const Color(0xFF7DB8E8));
    expect(AppPalette.light.warningText, const Color(0xFF945C0B));
    expect(AppPalette.dark.warningText, AppPalette.dark.carbs);
  });

  testWidgets('the weigh-in button says what it adds', (tester) async {
    await pumpTrends(tester, loaded());
    await openTile(tester, 'weight');
    expect(find.byTooltip('Weigh in'), findsOneWidget);
    expect(find.byTooltip('Add entry'), findsNothing);
  });

  group('on a wide screen', () {
    Future<void> wide(WidgetTester tester) async {
      tester.view
        ..physicalSize = const Size(1200, 2000)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }

    testWidgets('the overview is one centred column', (tester) async {
      await wide(tester);
      await tester.pumpWidget(
        _app(
          MediaQuery(
            data: const MediaQueryData(
              size: Size(1200, 2000),
              padding: EdgeInsets.symmetric(horizontal: 40),
            ),
            child: _overview(loaded(days: [_logged(0)])),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final tile = tester.getRect(
        find.byKey(const ValueKey('trends-tile-calories')),
      );
      expect(tile.left, greaterThanOrEqualTo(300));
      expect(tester.getRect(find.byType(RangePills)).width, WidthCap.maxWidth);
    });

    testWidgets('a detail page is one centred column', (tester) async {
      await wide(tester);
      await pumpTrends(tester, loaded(days: [_logged(0)]));
      await openTile(tester, 'carbs');
      expect(tester.getRect(find.byType(RangePills)).width, WidthCap.maxWidth);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await openTile(tester, 'calories');
      expect(tester.getRect(find.byType(RangePills)).width, WidthCap.maxWidth);
    });

    testWidgets('in landscape the side insets are kept', (tester) async {
      tester.view
        ..physicalSize = const Size(700, 400)
        ..devicePixelRatio = 1
        ..padding = const FakeViewPadding(left: 48, right: 48);
      addTearDown(tester.view.reset);
      await pumpTrends(tester, loaded(days: [_logged(0)]));
      await tester.pumpAndSettle();
      expect(
        tester.getRect(find.byType(RangePills)).left,
        greaterThanOrEqualTo(48),
      );
      expect(
        tester.getRect(find.byType(RangePills)).right,
        lessThanOrEqualTo(700 - 48),
      );
      await openTile(tester, 'carbs');
      expect(
        tester.getRect(find.byType(RangePills)).left,
        greaterThanOrEqualTo(48),
      );
    });
  });
}
