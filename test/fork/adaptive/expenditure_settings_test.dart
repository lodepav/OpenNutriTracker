import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:opennutritracker/core/domain/entity/physical_activity_entity.dart';
import 'package:opennutritracker/core/domain/entity/tracked_day_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_activity_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_gender_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_pal_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_weight_goal_entity.dart';
import 'package:opennutritracker/core/domain/entity/weight_log_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_tracked_day_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_user_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_weight_log_usecase.dart';
import 'package:opennutritracker/fork/adaptive/activity.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_service.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_store.dart';
import 'package:opennutritracker/fork/adaptive/check_in.dart';
import 'package:opennutritracker/fork/adaptive/expenditure.dart';
import 'package:opennutritracker/fork/adaptive/expenditure_settings_ui.dart';
import 'package:opennutritracker/fork/adaptive/skip_day.dart';
import 'package:opennutritracker/fork/health/steps.dart';

final _today = DateTime(2026, 10, 22);

UserEntity _user() => UserEntity(
  birthday: DateTime(1990, 1, 1),
  heightCM: 180,
  weightKG: 80,
  gender: UserGenderEntity.male,
  goal: UserWeightGoalEntity.maintainWeight,
  pal: UserPALEntity.active,
  weeklyWeightGoalKg: 0,
);

class _User extends Fake implements GetUserUsecase {
  @override
  Future<UserEntity> getUserData() async => _user();
}

/// 60 days at a steady 80 kg.
class _Weights extends Fake implements GetWeightLogUsecase {
  @override
  Future<List<WeightLogEntity>> getAllEntries() async => [
    for (var d = 59; d >= 0; d--)
      WeightLogEntity(date: _today.subtract(Duration(days: d)), weightKg: 80),
  ];
}

/// 2,500 kcal a day, but 900 on [partDay].
class _TrackedDays extends Fake implements GetTrackedDayUsecase {
  final DateTime? partDay;

  _TrackedDays([this.partDay]);

  @override
  Future<List<TrackedDayEntity>> getTrackedDaysByRange(
    DateTime start,
    DateTime end,
  ) async => [
    for (var d = 0; d < 60; d++)
      TrackedDayEntity(
        day: _today.subtract(Duration(days: d)),
        calorieGoal: 2500,
        caloriesTracked: _today.subtract(Duration(days: d)) == partDay
            ? 900
            : 2500,
      ),
  ];
}

class _Steps implements StepSource {
  final Map<DateTime, int> perDay;
  final int duringWorkout;

  _Steps(this.perDay, {this.duringWorkout = 0});

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<int> stepsBetween(DateTime from, DateTime to) async =>
      // A day is read from its midnight; a workout from its start.
      from.hour == 0 && from.minute == 0
      ? perDay[DateTime(from.year, from.month, from.day)] ?? 0
      : duringWorkout;
}

UserActivityEntity _workout(
  DateTime at, {
  double reported = 500,
  String? externalId,
}) => UserActivityEntity(
  'a-${at.toIso8601String()}',
  60,
  reported * 0.7,
  at,
  PhysicalActivityEntity.custom,
  externalId: externalId,
  sourceReportedKcal: externalId == null ? null : reported,
);

void main() {
  tearDown(() {
    AdaptiveStore.settings.value = const AdaptiveSettings();
    AdaptiveStore.skipped.value = const {};
  });

  group('responsiveness', () {
    test('the presets move only the blend, and the cycle the window', () {
      final steady = ExpenditureSettings.of(Responsiveness.steady);
      final standard = ExpenditureSettings.of(Responsiveness.standard);
      final responsive = ExpenditureSettings.of(Responsiveness.responsive);
      expect(
        [steady.blend, standard.blend, responsive.blend],
        [0.03, 0.05, 0.1],
      );
      expect(standard.window, const ExpenditureSettings().window);
      expect(
        ExpenditureSettings.of(Responsiveness.steady, cycleWindow: true).window,
        28,
      );
    });
  });

  group('activity in the estimate', () {
    List<AdaptiveDay> days({double? activity}) => [
      for (var d = 0; d < 90; d++)
        AdaptiveDay(intakeKcal: 2500, weightKg: 80, activityKcal: activity),
    ];

    test('steady activity is taken off, leaving the base', () {
      final whole = estimateExpenditure(days(), priorKcal: 2500).last;
      final base = estimateExpenditure(
        days(activity: 400),
        priorKcal: 2100,
      ).last;
      expect(whole, closeTo(2500, 1));
      expect(base, closeTo(2100, 1));
    });

    test('an overstated activity leaves base plus activity the same', () {
      // Whatever share of it is real, base + mean activity is what was
      // eaten at a steady weight.
      for (final overstated in [300.0, 600.0]) {
        final base = estimateExpenditure(
          days(activity: overstated),
          priorKcal: 2500 - overstated,
        ).last;
        expect(base + overstated, closeTo(2500, 1));
      }
    });
  });

  group('check-in', () {
    CheckIn checkIn({
      required ActivityMode mode,
      double? cap = 200,
      double previous = 2000,
      double activity = 300,
    }) => computeCheckIn(
      CheckInInputs(
        days: [
          for (var d = 0; d < 90; d++)
            AdaptiveDay(
              intakeKcal: 2500,
              weightKg: 80,
              activityKcal: mode == ActivityMode.off ? null : activity,
            ),
        ],
        priorKcal: mode == ActivityMode.off ? 2500 : 2500 - activity,
        goalRateKgPerWeek: 0,
        bodyFatPercent: 20,
        previousTargetKcal: previous,
        taper: (adjustment, _) => adjustment,
        maxChangeKcal: cap,
        activityMode: mode,
      ),
    );

    test('the cap is the one chosen, or none', () {
      expect(
        checkIn(mode: ActivityMode.off, cap: 100).proposedTargetKcal,
        closeTo(2100, 1),
      );
      expect(
        checkIn(mode: ActivityMode.off, cap: null).proposedTargetKcal,
        closeTo(2500, 1),
      );
    });

    test('weekly: the week\'s activity rides on top of the capped base', () {
      final c = checkIn(mode: ActivityMode.weekly, previous: 2100, cap: 100);
      expect(c.activityKcal, closeTo(300, 0.1));
      expect(c.expenditureKcal, closeTo(2500, 1));
      // The base moves 2100 → 2200 at most; the activity is added after.
      expect(c.proposedTargetKcal, closeTo(2500, 1));
      expect(c.activityInTarget(ActivityMode.weekly), closeTo(300, 0.1));
    });

    test('each day: the proposal is the base, activity added per day', () {
      final c = checkIn(mode: ActivityMode.daily, previous: 2200, cap: null);
      expect(c.proposedTargetKcal, closeTo(2200, 1));
      expect(c.activityInTarget(ActivityMode.daily), 0);
    });
  });

  group('when a check-in is due', () {
    // 2026-10-22 is a Thursday.
    test('a week after the last, without a weekday', () {
      expect(checkInDueOn(_today, null, null), isTrue);
      expect(checkInDueOn(_today, DateTime(2026, 10, 16), null), isFalse);
      expect(checkInDueOn(_today, DateTime(2026, 10, 15), null), isTrue);
    });

    test('on the weekday, and after it until done', () {
      // Monday is the weekday; the last was on Sunday the 18th.
      expect(checkInDueOn(_today, DateTime(2026, 10, 18), 1), isTrue);
      expect(checkInDueOn(_today, DateTime(2026, 10, 19), 1), isFalse);
      expect(
        checkInDueOn(DateTime(2026, 10, 19), DateTime(2026, 10, 19), 1),
        isFalse,
      );
      // Thursday itself, the last a week ago.
      expect(checkInDueOn(_today, DateTime(2026, 10, 15), 4), isTrue);
      expect(checkInDueOn(_today, _today, 4), isFalse);
    });
  });

  group('settings', () {
    test('round trip, "no limit" apart from an older box', () {
      const s = AdaptiveSettings(
        responsiveness: Responsiveness.steady,
        activityMode: ActivityMode.daily,
        countSteps: false,
        workoutSharePct: 55,
        checkInWeekday: 7,
        maxCheckInChangeKcal: null,
        autoAcceptCheckIn: true,
      );
      final back = AdaptiveSettings.fromJson(s.toJson());
      expect(back.responsiveness, Responsiveness.steady);
      expect(back.activityMode, ActivityMode.daily);
      expect(back.countSteps, isFalse);
      expect(back.workoutSharePct, 55);
      expect(back.checkInWeekday, 7);
      expect(back.maxCheckInChangeKcal, isNull);
      expect(back.autoAcceptCheckIn, isTrue);

      final older = AdaptiveSettings.fromJson({'adaptiveTarget': true});
      expect(older.maxCheckInChangeKcal, 200);
      expect(older.activityMode, ActivityMode.off);
      expect(
        () => AdaptiveSettings.fromJson({'checkInWeekday': 8}),
        throwsFormatException,
      );
    });
  });

  group('with a box', () {
    late Directory dir;
    late Box<dynamic> box;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('expenditure');
      Hive.init(dir.path);
      box = await Hive.openBox<dynamic>('fork');
    });

    tearDown(() async {
      await Hive.deleteFromDisk();
      await dir.delete(recursive: true);
    });

    test('a step costs about 0.03 kcal for 80 kg at 180 cm', () {
      expect(kcalPerStep(80, 180), closeTo(0.0298, 0.0005));
    });

    test('workouts at the share of what the device reported, steps less '
        'those in an imported workout', () async {
      final yesterday = _today.subtract(const Duration(days: 1));
      final steps = StepCounts(
        _Steps({yesterday: 10000, _today: 4000}, duringWorkout: 3000),
        () async => box,
      );
      await steps.turnOn();
      final counter = ActivityCounter(
        activities: () async => [
          _workout(yesterday.add(const Duration(hours: 7)), externalId: 'run'),
          _workout(_today.add(const Duration(hours: 18)), reported: 200),
        ],
        steps: steps,
        dayStartOffsetMinutes: () async => 0,
      );
      final counted = await counter.daily(
        first: yesterday,
        today: _today,
        settings: const AdaptiveSettings(workoutSharePct: 50),
        user: _user(),
      );
      final perStep = kcalPerStep(80, 180);
      // The run's 500 reported at 50%, its 3,000 steps not again.
      expect(counted[yesterday], closeTo(250 + 7000 * perStep, 0.01));
      // A logged workout: its own figure, also at 50%.
      expect(counted[_today], closeTo(140 * 0.5 + 4000 * perStep, 0.01));

      final workoutsOnly = await counter.daily(
        first: yesterday,
        today: _today,
        settings: const AdaptiveSettings(countSteps: false),
        user: _user(),
      );
      final share = workoutShare(const AdaptiveSettings(), _user(), null);
      expect(workoutsOnly[yesterday], closeTo(500 * share, 0.01));
    });

    test('a day left out counts its weigh-in, not its food', () async {
      final part = _today.subtract(const Duration(days: 3));
      final service = AdaptiveService(
        _User(),
        _Weights(),
        _TrackedDays(part),
        AdaptiveStore(() async => box),
        () => _today.add(const Duration(hours: 9)),
      );
      final counted = (await service.expenditureHistory()).last;
      AdaptiveStore.skipped.value = {part};
      final skipped = await service.expenditureHistory();
      expect(
        skipped.last.expenditureKcal,
        greaterThan(counted.expenditureKcal),
      );
      expect(skipped.firstWhere((d) => d.date == part).intakeKcal, isNull);
    });

    test('skipped days are kept per day and loaded', () async {
      final store = AdaptiveStore(() async => box);
      await store.setSkipped(DateTime(2026, 10, 20, 15), true);
      await store.setSkipped(DateTime(2026, 10, 21), true);
      await store.setSkipped(DateTime(2026, 10, 21), false);
      AdaptiveStore.skipped.value = const {};
      await store.load();
      expect(AdaptiveStore.skipped.value, {DateTime(2026, 10, 20)});
    });
  });

  group('screens', () {
    testWidgets('the Diary switch leaves the day out', (tester) async {
      final store = _MemoryStore();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SkipDayTile(day: DateTime(2026, 10, 20, 12), store: store),
          ),
        ),
      );
      await tester.tap(find.byType(Switch));
      await tester.pump();
      expect(AdaptiveStore.skipped.value, {DateTime(2026, 10, 20)});
      expect(find.textContaining('Not used in the expenditure'), findsOneWidget);
    });

    testWidgets('three groups; activity rows only while it counts', (
      tester,
    ) async {
      AdaptiveStore.settings.value = const AdaptiveSettings(
        adaptiveTarget: true,
      );
      final store = _MemoryStore();
      await tester.pumpWidget(
        MaterialApp(
          home: ExpenditureSettingsScreen(
            store: store,
            steps: StepCounts(_Steps({}), () async => _NoBox()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final heading in ['Estimate', 'Activity']) {
        expect(find.text(heading), findsOneWidget);
      }
      expect(find.byKey(const ValueKey('count-workouts')), findsNothing);

      await tester.tap(find.text('Weekly'));
      await tester.pumpAndSettle();
      expect(AdaptiveStore.settings.value.activityMode, ActivityMode.weekly);
      expect(find.byKey(const ValueKey('count-workouts')), findsOneWidget);
      expect(find.textContaining('Workout calories counted'), findsOneWidget);

      final auto = find.byKey(const ValueKey('auto-accept-check-in'));
      await tester.scrollUntilVisible(auto, 200);
      await tester.ensureVisible(auto);
      await tester.pumpAndSettle();
      expect(find.text('Check-in'), findsOneWidget);
      await tester.tap(auto);
      await tester.pumpAndSettle();
      expect(AdaptiveStore.settings.value.autoAcceptCheckIn, isTrue);

      await tester.tap(find.text('No limit'));
      await tester.pumpAndSettle();
      expect(AdaptiveStore.settings.value.maxCheckInChangeKcal, isNull);
    });

    testWidgets('the Steps switch connects, and turns off and on', (
      tester,
    ) async {
      AdaptiveStore.settings.value = const AdaptiveSettings(
        activityMode: ActivityMode.weekly,
      );
      final steps = _SwitchSteps();
      await tester.pumpWidget(
        MaterialApp(
          home: ExpenditureSettingsScreen(store: _MemoryStore(), steps: steps),
        ),
      );
      await tester.pumpAndSettle();
      final tile = find.byKey(const ValueKey('count-steps'));
      bool shown() => tester.widget<SwitchListTile>(tile).value;
      expect(shown(), isFalse);

      await tester.tap(tile);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(steps.on, isTrue);
      expect(shown(), isTrue);

      await tester.tap(tile);
      await tester.pumpAndSettle();
      expect(AdaptiveStore.settings.value.countSteps, isFalse);
      expect(shown(), isFalse);

      await tester.tap(tile);
      await tester.pumpAndSettle();
      expect(AdaptiveStore.settings.value.countSteps, isTrue);
      expect(shown(), isTrue);
    });

    testWidgets('a refused permission leaves Steps off', (tester) async {
      AdaptiveStore.settings.value = const AdaptiveSettings(
        activityMode: ActivityMode.weekly,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: ExpenditureSettingsScreen(
            store: _MemoryStore(),
            steps: _SwitchSteps(grants: false),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final tile = find.byKey(const ValueKey('count-steps'));
      await tester.tap(tile);
      await tester.pumpAndSettle();
      expect(tester.widget<SwitchListTile>(tile).value, isFalse);
      expect(find.textContaining('Health Connect permission'), findsOneWidget);
    });

    testWidgets('choices stack as rows at large text', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: ExpenditureSettingsScreen(
              store: _MemoryStore(),
              steps: _SwitchSteps(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(SegmentedButton<Responsiveness>), findsNothing);
      await tester.tap(find.text('Responsive'));
      await tester.pumpAndSettle();
      expect(
        AdaptiveStore.settings.value.responsiveness,
        Responsiveness.responsive,
      );
    });
  });
}

class _SwitchSteps extends Fake implements StepCounts {
  final bool grants;
  bool on = false;

  _SwitchSteps({this.grants = true});

  @override
  Future<bool> isOn() async => on;

  @override
  Future<bool> turnOn() async => on = grants;
}

/// Hive's file I/O does not finish in a widget test's fake time.
class _MemoryStore extends AdaptiveStore {
  final keptSkipped = <DateTime>{};

  @override
  Future<void> save(AdaptiveSettings value) async =>
      AdaptiveStore.settings.value = value;

  @override
  Future<void> setSkipped(DateTime day, bool skipped) async {
    skipped ? keptSkipped.add(day) : keptSkipped.remove(day);
    AdaptiveStore.skipped.value = Set.of(keptSkipped);
  }
}

/// The steps switch's box, off and empty, without Hive.
class _NoBox extends Fake implements Box<dynamic> {
  @override
  dynamic get(dynamic key, {dynamic defaultValue}) => defaultValue;
}
