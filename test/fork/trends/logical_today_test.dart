import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/app_theme_entity.dart';
import 'package:opennutritracker/core/domain/entity/body_weight_unit_entity.dart';
import 'package:opennutritracker/core/domain/entity/config_entity.dart';
import 'package:opennutritracker/core/domain/entity/tracked_day_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_gender_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_pal_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_weight_goal_entity.dart';
import 'package:opennutritracker/core/domain/entity/water_intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/weight_log_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_tracked_day_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_user_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_water_intake_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_weight_log_usecase.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/utils/calc/day_boundary_calc.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/trends/presentation/bloc/trends_bloc.dart';
import 'package:opennutritracker/fork/display/display_prefs.dart';
import 'package:opennutritracker/fork/report/weekly_report.dart';
import 'package:opennutritracker/fork/trends/calories_detail.dart';

import 'trends_harness.dart';

// Trends ends its windows on the Diary's today. At 02:00 on Tuesday the 15th,
// with the day starting at 04:00, today is still Monday the 14th.

final _wallClock = DateTime(2026, 9, 15, 2);
final _logicalToday = DateTime(2026, 9, 14);
const _dayStart = 4 * 60;

class _TrackedDays extends Fake implements GetTrackedDayUsecase {
  final calls = <({DateTime start, DateTime end})>[];

  @override
  Future<List<TrackedDayEntity>> getTrackedDaysByRange(
    DateTime start,
    DateTime end,
  ) async {
    calls.add((start: start, end: end));
    return const [];
  }
}

class _Weights extends Fake implements GetWeightLogUsecase {
  @override
  Future<List<WeightLogEntity>> getAllEntries() async => [];
}

class _User extends Fake implements GetUserUsecase {
  @override
  Future<UserEntity> getUserData() async => UserEntity(
    birthday: DateTime(1990),
    heightCM: 175,
    weightKG: 75,
    gender: UserGenderEntity.female,
    goal: UserWeightGoalEntity.maintainWeight,
    pal: UserPALEntity.active,
  );
}

class _Config extends Fake implements GetConfigUsecase {
  @override
  Future<ConfigEntity> getConfig() async => ConfigEntity(
    true,
    true,
    false,
    AppThemeEntity.system,
    dayStartOffsetHours: 4,
  );
}

class _Water extends Fake implements GetWaterIntakeUsecase {
  @override
  Future<List<WaterIntakeEntity>> getAllEntries() async => [
    // After midnight, before the day starts: Home counts it on the 14th.
    WaterIntakeEntity(id: 'a', dateTime: _wallClock, amountMl: 300),
  ];
}

TrackedDayEntity _row(DateTime date, {double kcal = 1000}) => TrackedDayEntity(
  day: date,
  calorieGoal: 1000,
  caloriesTracked: kcal,
  carbsTracked: 100,
  carbsGoal: 100,
);

void main() {
  setUp(() {
    DayBoundaryCalc.clock = () => _wallClock;
    DisplayPrefs.showWater.value = true;
  });
  tearDown(() async {
    DayBoundaryCalc.clock = DateTime.now;
    DisplayPrefs.showWater.value = false;
    await locator.reset();
  });

  group('the bloc', () {
    test('reads the range and files water by the logical day', () async {
      final tracked = _TrackedDays();
      final bloc = TrendsBloc(
        tracked,
        _Weights(),
        _User(),
        _Config(),
        _Water(),
      );
      addTearDown(bloc.close);
      final done = bloc.stream.firstWhere((s) => s is TrendsLoaded);
      bloc.add(const LoadTrendsEvent(rangeDays: 7));
      final state = await done as TrendsLoaded;

      expect(tracked.calls.first, (
        start: DateTime(2026, 9, 8),
        end: DateTime(2026, 9, 14, 23, 59, 59),
      ));
      expect(state.logicalToday, _logicalToday);
      expect(state.waterByDay, {_logicalToday: 300});
    });

    // Riga's clocks go back on the 25th: the same day in another offset.
    test('counts its windows in calendar days across a clock change', () async {
      DayBoundaryCalc.clock = () => DateTime(2026, 11, 1, 9);
      final tracked = _TrackedDays();
      final bloc = TrendsBloc(
        tracked,
        _Weights(),
        _User(),
        _Config(),
        _Water(),
      );
      addTearDown(bloc.close);
      Future<TrendsLoaded> load(TrendsEvent event) async {
        tracked.calls.clear();
        final done = bloc.stream.firstWhere((s) => s is TrendsLoaded);
        bloc.add(event);
        return await done as TrendsLoaded;
      }

      await load(const LoadTrendsEvent(rangeDays: 7));
      expect(tracked.calls[0].start, DateTime(2026, 10, 26));
      expect(tracked.calls[1].start, DateTime(2026, 10, 19));
      await load(const LoadTrendsEvent(rangeDays: 90));
      expect(tracked.calls[0].start, DateTime(2026, 8, 4));
      await load(const LoadTrendsEvent(rangeDays: 30));
      final again = await load(const RefreshTrendsEvent());
      expect(again.rangeDays, 30);
      expect(tracked.calls[0].start, DateTime(2026, 10, 3));
    });
  });

  group('the pages', () {
    TrendsLoaded state({
      List<TrackedDayEntity> days = const [],
      Map<DateTime, int> water = const {},
    }) => TrendsLoaded(
      rangeDays: 7,
      windowDays: 7,
      days: days,
      priorWeek: const [],
      weight: const [],
      bodyWeightUnit: BodyWeightUnit.kg,
      targetWeightKg: null,
      waterByDay: water,
      waterGoalMl: 2000,
      dayStartMinutes: _dayStart,
    );

    testWidgets('a tile reads the window\'s first logical day', (tester) async {
      // The 8th is in the window ending on the 14th, not in one ending on
      // the 15th.
      await pumpTrends(tester, state(days: [_row(DateTime(2026, 9, 8))]));
      await showTile(tester, 'calories');
      expect(tileText(tester, 'calories'), contains('1000'));
    });

    testWidgets('the streak runs to the logical today', (tester) async {
      await pumpTrends(tester, state(days: [_row(_logicalToday)]));
      expect(find.text('1 day streak'), findsOneWidget);
    });

    testWidgets('the Calories page spans the logical window', (tester) async {
      await pumpTrends(tester, state(days: [_row(DateTime(2026, 9, 8))]));
      await openTile(tester, 'calories');
      expect(find.text('Sep 8 – Sep 14 · 1 of 7 days logged'), findsOneWidget);
    });

    testWidgets('a macro page reads the logical window', (tester) async {
      await pumpTrends(tester, state(days: [_row(DateTime(2026, 9, 8))]));
      await openTile(tester, 'carbs');
      expect(
        tester.getSemantics(find.text('Average')).label,
        contains('100 g'),
      );
    });

    testWidgets('the water card ends where its header does', (tester) async {
      await pumpTrends(tester, state(water: {_logicalToday: 500}));
      await openTile(tester, 'water');
      final chart = tester.widget<LineChart>(find.byType(LineChart)).data;
      expect(chart.lineBarsData.single.spots.last.y, 500);
    });
  });

  testWidgets('the weekday card\'s three months end on the logical today', (
    tester,
  ) async {
    final tracked = _TrackedDays();
    locator.registerSingleton<GetTrackedDayUsecase>(tracked);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: WeekdayCard(dayStartMinutes: _dayStart),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tracked.calls.single, (
      start: DateTime(2026, 9, 14 - 89),
      end: DateTime(2026, 9, 14, 23, 59, 59),
    ));
  });

  testWidgets('the weekly report\'s week ends on the logical today', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WeeklyReportCard(
            days: [_row(_logicalToday)],
            rangeDays: 7,
            palette: AppPalette.light,
            dayStartMinutes: _dayStart,
          ),
        ),
      ),
    );
    // Monday the 14th is all of this week so far; a wall clock says two days.
    expect(find.text('1/1 days'), findsOneWidget);
  });
}
