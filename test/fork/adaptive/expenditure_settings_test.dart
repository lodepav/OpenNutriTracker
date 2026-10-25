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

/// A new user: the weigh-in from onboarding alone.
class _OneWeighIn extends Fake implements GetWeightLogUsecase {
  @override
  Future<List<WeightLogEntity>> getAllEntries() async => [
    WeightLogEntity(date: _today, weightKg: 80),
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

  group('D19', () {
    test('activity counted from partway through is not counted twice', () {
      // 2,500 kcal at a steady 80 kg; from day 40 steps count 300 a day.
      // The estimate before held that walking, so it drops by it at once
      // rather than over weeks while the target adds it back.
      final days = [
        for (var d = 0; d < 80; d++)
          AdaptiveDay(
            intakeKcal: 2500,
            weightKg: 80,
            activityKcal: d < 40 ? null : 300,
          ),
      ];
      final estimates = estimateExpenditure(days, priorKcal: 2500);
      expect(estimates[39], closeTo(2500, 5));
      expect(estimates[40], closeTo(2200, 5));
      expect(estimates.last, closeTo(2200, 5));
    });

    test('the window starts at the first logged day', () {
      // Weigh-ins for 30 days before logging: the first update comes a
      // warm-up after logging began, not once the window is 60% logged.
      final days = [
        for (var d = 0; d < 30; d++) const AdaptiveDay(weightKg: 80),
        for (var d = 0; d < 20; d++)
          const AdaptiveDay(intakeKcal: 2500, weightKg: 80),
      ];
      final run = estimateExpenditureRun(days, priorKcal: 3000);
      expect(run.firstUpdate, 30 + ExpenditureSettings.defaultWarmupDays - 1);
      expect(run.estimates.last, lessThan(2700));
    });

    test('a flat 7,700 kcal per kg, kept in the settings', () {
      const flat = AdaptiveSettings(flatEnergy: true);
      expect(flat.expenditure.kcalPerKgAt(90, 25), 7700);
      expect(
        const AdaptiveSettings().expenditure.kcalPerKgAt(90, 25),
        lessThan(7700),
      );
      expect(AdaptiveSettings.fromJson(flat.toJson()).flatEnergy, isTrue);
      expect(AdaptiveSettings.fromJson(const {}).flatEnergy, isFalse);
    });

    test('a weekly check-in says what the past week\'s activity moved', () {
      CheckIn at(double? previousActivity) => computeCheckIn(
        CheckInInputs(
          days: [
            for (var d = 0; d < 40; d++)
              const AdaptiveDay(
                intakeKcal: 2500,
                weightKg: 80,
                activityKcal: 300,
              ),
          ],
          priorKcal: 2500,
          goalRateKgPerWeek: 0,
          bodyFatPercent: 20,
          previousBaseKcal: 2200,
          previousActivityKcal: previousActivity,
          activityMode: ActivityMode.weekly,
          taper: (adjustment, _) => adjustment,
        ),
      );
      expect(at(100).activityChangeKcal, closeTo(200, 0.01));
      expect(at(null).activityChangeKcal, isNull);
    });
  });

  group('D18', () {
    test('a gap while not logging leaves the estimate where it was', () {
      // 60 days at 2,500 kcal holding 80 kg, then 14 unlogged days gaining
      // 1 kg, then 6 days back on 2,500 kcal: under 60% of the window is
      // logged, so the gain is not priced at the logged intake.
      final days = [
        for (var d = 0; d < 60; d++)
          const AdaptiveDay(intakeKcal: 2500, weightKg: 80),
        for (var d = 1; d <= 14; d++) AdaptiveDay(weightKg: 80 + d / 14),
        for (var d = 0; d < 6; d++)
          const AdaptiveDay(intakeKcal: 2500, weightKg: 81),
      ];
      final guarded = estimateExpenditure(days, priorKcal: 2500);
      final unguarded = estimateExpenditure(
        days,
        priorKcal: 2500,
        settings: const ExpenditureSettings(minLoggedShare: 0),
      );
      expect(guarded.last, closeTo(2500, 5));
      expect(unguarded.last, lessThan(guarded.last - 20));
    });

    test('calibration counts updates, not days before logging began', () {
      // 40 days of weigh-ins alone, then logging: the fast blend is still
      // there when updates begin.
      final days = [
        for (var d = 0; d < 40; d++) const AdaptiveDay(weightKg: 80),
        for (var d = 0; d < 30; d++)
          const AdaptiveDay(intakeKcal: 2500, weightKg: 80),
      ];
      final run = estimateExpenditureRun(days, priorKcal: 3200);
      expect(run.updates, greaterThan(0));
      expect(run.estimates.last, closeTo(2500, 30));
    });

    test('a record keeps its base and goal; an older one falls back', () {
      final record = CheckInRecord(
        date: DateTime(2026, 10, 1),
        expenditureKcal: 2800,
        proposedKcal: 2500,
        acceptedKcal: 2500,
        activityKcal: 300,
        baseKcal: 2450,
        goalRateKgPerWeek: -0.5,
        targetWeightKg: 80,
      );
      final back = CheckInRecord.fromJson(record.toJson());
      expect(back.baseKcal, 2450);
      expect(back.goalRateKgPerWeek, -0.5);
      expect(back.targetWeightKg, 80);
      expect(back.goalChanged(-0.5, 80), isFalse);
      expect(back.goalChanged(0, 80), isTrue);
      expect(back.goalChanged(-0.5, 78), isTrue);
      expect(back.goalChanged(-0.5, null), isTrue);

      final older = CheckInRecord.fromJson({
        'date': '2026-10-01T09:00:00.000',
        'expenditureKcal': 2800,
        'proposedKcal': 2500,
        'acceptedKcal': 2500,
        'activityKcal': 300,
      });
      expect(older.baseKcal, 2500);
      expect(older.goalChanged(0, null), isFalse);
    });
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
        previousBaseKcal: previous,
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

    test('the suggested workout share is the 5% step the slider shows', () {
      expect(toShareStep(0.7249), 0.7);
      expect(toShareStep(0.7251), 0.75);
      for (final bodyFat in [null, 12.0, 23.0, 31.0]) {
        final pct =
            workoutShare(const AdaptiveSettings(), _user(), bodyFat) * 100;
        expect(pct, closeTo((pct / 5).round() * 5, 1e-9), reason: '$bodyFat');
      }
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

    test('the daily limit holds for the base too, and today is left out '
        'while its steps come in', () async {
      AdaptiveService serviceWith(List<DateTime> workouts) => AdaptiveService(
        _User(),
        _Weights(),
        _TrackedDays(),
        AdaptiveStore(() async => box),
        () => _today.add(const Duration(hours: 9)),
        null,
        ActivityCounter(
          activities: () async => [
            for (final d in workouts)
              _workout(d.add(const Duration(hours: 7)), reported: 3000),
          ],
          steps: StepCounts(_Steps(const {}), () async => box),
          dayStartOffsetMinutes: () async => 0,
        ),
      );
      AdaptiveStore.settings.value = const AdaptiveSettings(
        adaptiveTarget: true,
        activityMode: ActivityMode.daily,
        countSteps: false,
      );
      addTearDown(
        () => AdaptiveStore.settings.value = const AdaptiveSettings(),
      );

      final everyDay = await serviceWith([
        for (var d = 0; d < 7; d++) _today.subtract(Duration(days: d)),
      ]).checkIn();
      // A day's target adds no more than 800, so the base takes no more off.
      expect(everyDay.activityKcal, closeTo(maxDailyActivityKcal, 0.01));

      final todayOnly = await serviceWith([_today]).checkIn();
      expect(todayOnly.activityKcal, 0);
    });

    test("a new user's first day takes off a whole day's steps from the "
        'days before it', () async {
      final steps = StepCounts(
        _Steps({
          for (var d = 1; d <= 14; d++)
            _today.subtract(Duration(days: d)): 10000,
          _today: 1000,
        }),
        () async => box,
        () => _today.add(const Duration(hours: 9)),
      );
      await steps.turnOn();
      AdaptiveService serviceWith(AdaptiveSettings settings) {
        AdaptiveStore.settings.value = settings;
        return AdaptiveService(
          _User(),
          _OneWeighIn(),
          _TrackedDays(),
          AdaptiveStore(() async => box),
          () => _today.add(const Duration(hours: 9)),
          null,
          ActivityCounter(
            activities: () async => [],
            steps: steps,
            dayStartOffsetMinutes: () async => 0,
          ),
        );
      }

      addTearDown(
        () => AdaptiveStore.settings.value = const AdaptiveSettings(),
      );
      final off = await serviceWith(
        const AdaptiveSettings(adaptiveTarget: true),
      ).checkIn();
      final daily = await serviceWith(
        const AdaptiveSettings(
          adaptiveTarget: true,
          activityMode: ActivityMode.daily,
          countWorkouts: false,
        ),
      ).checkIn();
      // 10,000 a day before it, not the 1,000 of this morning.
      expect(
        daily.baseKcal,
        closeTo(off.baseKcal - 10000 * kcalPerStep(80, 180), 0.01),
      );
    });

    test("a new user's first day takes its activity off the prior", () async {
      AdaptiveService serviceWith(AdaptiveSettings settings) {
        AdaptiveStore.settings.value = settings;
        return AdaptiveService(
          _User(),
          _OneWeighIn(),
          _TrackedDays(),
          AdaptiveStore(() async => box),
          () => _today.add(const Duration(hours: 9)),
          null,
          ActivityCounter(
            activities: () async => [
              _workout(_today.add(const Duration(hours: 7)), reported: 3000),
            ],
            steps: StepCounts(_Steps(const {}), () async => box),
            dayStartOffsetMinutes: () async => 0,
          ),
        );
      }

      addTearDown(
        () => AdaptiveStore.settings.value = const AdaptiveSettings(),
      );
      final off = await serviceWith(
        const AdaptiveSettings(adaptiveTarget: true),
      ).checkIn();
      final daily = await serviceWith(
        const AdaptiveSettings(
          adaptiveTarget: true,
          activityMode: ActivityMode.daily,
          countSteps: false,
        ),
      ).checkIn();
      // The prior holds activity; the daily mode adds the day's back.
      expect(
        daily.baseKcal,
        closeTo(off.baseKcal - maxDailyActivityKcal, 0.01),
      );
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
    testWidgets('Count again works from TalkBack', (tester) async {
      final handle = tester.ensureSemantics();
      final store = _MemoryStore();
      final day = DateTime(2026, 10, 20);
      await store.setSkipped(day, true);
      await tester.pumpWidget(
        MaterialApp(home: ExpenditureSettingsScreen(store: store)),
      );
      await tester.pumpAndSettle();
      final tile = find.byKey(const ValueKey('skipped-days'));
      await tester.ensureVisible(tile);
      await tester.pumpAndSettle();
      await tester.tap(tile);
      await tester.pumpAndSettle();

      // A double-tap sends the node's tap action; a wrapper that drops it
      // leaves nothing to send.
      tester.semantics.tap(find.semantics.byLabel(RegExp('Count again')));
      await tester.pumpAndSettle();
      expect(store.keptSkipped, isEmpty);
      handle.dispose();
    });

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
      expect(
        find.textContaining('Not used in the expenditure'),
        findsOneWidget,
      );
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
      await tester.ensureVisible(tile);
      await tester.pumpAndSettle();
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
      await tester.ensureVisible(tile);
      await tester.pumpAndSettle();
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
