import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/body_weight_unit_entity.dart';
import 'package:opennutritracker/core/domain/entity/weight_log_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_tracked_day_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_user_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_water_intake_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_weight_log_usecase.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_store.dart';
import 'package:opennutritracker/fork/adaptive/expenditure.dart';
import 'package:opennutritracker/fork/adaptive/goal_plan.dart';
import 'package:opennutritracker/fork/adaptive/trend.dart';
import 'package:opennutritracker/fork/report/rate_text.dart';
import 'package:opennutritracker/features/trends/presentation/bloc/trends_bloc.dart';
import 'package:opennutritracker/features/trends/presentation/trends_page.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:provider/provider.dart';

// Seam S93: the weight outlook reads the weigh-ins the chart draws, and is
// labelled as the measured trend.

class _FakeGetTrackedDayUsecase extends Fake implements GetTrackedDayUsecase {}

class _FakeGetWeightLogUsecase extends Fake implements GetWeightLogUsecase {}

class _FakeGetUserUsecase extends Fake implements GetUserUsecase {}

class _FakeGetConfigUsecase extends Fake implements GetConfigUsecase {}

class _FakeGetWaterIntakeUsecase extends Fake
    implements GetWaterIntakeUsecase {}

class _SeededTrendsBloc extends TrendsBloc {
  _SeededTrendsBloc(TrendsLoaded seeded)
    : super(
        _FakeGetTrackedDayUsecase(),
        _FakeGetWeightLogUsecase(),
        _FakeGetUserUsecase(),
        _FakeGetConfigUsecase(),
        _FakeGetWaterIntakeUsecase(),
      ) {
    emit(seeded);
  }

  @override
  void add(TrendsEvent event) {}
}

DateTime _day(int offset) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day + offset);
}

Future<void> _pump(WidgetTester tester, List<WeightLogEntity> weight) async {
  // The expenditure card below builds in the list's cache; its reads fail
  // on these and it shows nothing.
  locator
    ..registerSingleton<GetUserUsecase>(_FakeGetUserUsecase())
    ..registerSingleton<GetWeightLogUsecase>(_FakeGetWeightLogUsecase())
    ..registerSingleton<GetTrackedDayUsecase>(_FakeGetTrackedDayUsecase());
  locator.registerSingleton<TrendsBloc>(
    _SeededTrendsBloc(
      TrendsLoaded(
        rangeDays: 7,
        windowDays: 7,
        days: const [],
        priorWeek: const [],
        weight: weight,
        bodyWeightUnit: BodyWeightUnit.kg,
        targetWeightKg: 70,
        waterByDay: const {},
        waterGoalMl: 0,
      ),
    ),
  );
  await tester.pumpWidget(
    ChangeNotifierProvider(
      create: (_) => EnergyUnitProvider(usesKilojoules: false),
      child: const MaterialApp(
        localizationsDelegates: [
          S.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: S.supportedLocales,
        home: Scaffold(body: TrendsPage()),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  tearDown(() async => locator.reset());

  testWidgets('two weigh-ins in the range: the trend, labelled as one', (
    tester,
  ) async {
    await _pump(tester, [
      WeightLogEntity(date: _day(-6), weightKg: 80),
      WeightLogEntity(date: _day(0), weightKg: 79.4),
    ]);
    final outlook = find.textContaining('Trend: ');
    await tester.scrollUntilVisible(
      outlook,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    // The smoothed trend's loss, short of the readings' 0.70 kg a week.
    expect(
      tester.widget<Text>(outlook).data,
      matches(RegExp(r'^Trend: -0\.[0-6]\d kg a week')),
    );
  });

  // Seam S93: the rate is the smoothed trend's, as the Trend weight card's,
  // not a fit of the raw readings, whichever line the chart draws.
  testWidgets('smoothed trend on: the rate follows the trend', (tester) async {
    AdaptiveStore.settings.value = const AdaptiveSettings(smoothedTrend: true);
    addTearDown(() => AdaptiveStore.settings.value = const AdaptiveSettings());
    await _pump(tester, [
      for (var i = 0; i < 30; i++)
        WeightLogEntity(date: _day(i - 30), weightKg: 85 - i * 0.1),
      WeightLogEntity(date: _day(-6), weightKg: 81.8),
      WeightLogEntity(date: _day(0), weightKg: 84),
    ]);
    final outlook = find.textContaining('Trend: ');
    await tester.scrollUntilVisible(
      outlook,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    // A fit of the readings in the range says +1.03 kg a week.
    expect(
      tester.widget<Text>(outlook).data,
      matches(RegExp(r'^Trend: [+-]0\.\d\d kg a week')),
    );
    expect(find.text('Dots: weigh-ins. Dashed: trend.'), findsOneWidget);
  });

  // Seam S93: the rate is the Goal planner's "Last 7 days", to the
  // hundredth: the trend carried on to today past the last weigh-in.
  testWidgets('the rate agrees with the Goal planner\'s', (tester) async {
    final weighIns = {0: 84.0, 9: 83.1, 15: 83.6, 18: 82.4, 21: 82.9};
    const days = 25; // the last weigh-in four days before today
    await _pump(tester, [
      for (final MapEntry(key: d, value: kg) in weighIns.entries)
        WeightLogEntity(date: _day(d - (days - 1)), weightKg: kg),
    ]);
    final planner = smoothedTrend(
      dailyWeights(weighIns, days),
      alpha: const ExpenditureSettings().alpha,
    ).whereType<double>().toList();
    final week = trendChanges(planner)[7]!;
    final outlook = find.textContaining('Trend: ');
    await tester.scrollUntilVisible(
      outlook,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      tester.widget<Text>(outlook).data,
      startsWith('Trend: ${signedRate(week)} kg a week'),
    );
  });

  // Seam S97: a range with nothing logged says so, rather than a flat line
  // and its fill along the bottom under the goal.
  testWidgets('nothing logged: the calorie and water cards say so', (
    tester,
  ) async {
    await _pump(tester, const []);

    expect(find.text('Nothing logged in this range.'), findsOneWidget);
    final water = find.text('No water logged in this range.');
    await tester.scrollUntilVisible(
      water,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(water, findsOneWidget);
  });

  testWidgets('one weigh-in in the range: no rate beside the empty chart', (
    tester,
  ) async {
    await _pump(tester, [
      WeightLogEntity(date: _day(-40), weightKg: 84),
      WeightLogEntity(date: _day(0), weightKg: 80),
      // Written with the clock moved forward.
      WeightLogEntity(date: _day(14), weightKg: 79),
    ]);
    final empty = find.byKey(const Key('weightHistoryChartEmptyState'));
    await tester.scrollUntilVisible(
      empty,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.textContaining('/week'), findsNothing);
  });
}
