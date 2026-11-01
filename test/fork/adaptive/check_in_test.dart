import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/fork/adaptive/activity.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:opennutritracker/core/domain/entity/tracked_day_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_entity.dart';
import 'package:opennutritracker/core/domain/entity/app_theme_entity.dart';
import 'package:opennutritracker/core/domain/entity/config_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_kcal_goal_usecase.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/core/domain/entity/user_gender_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_pal_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_weight_goal_entity.dart';
import 'package:opennutritracker/core/domain/entity/weight_log_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_tracked_day_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_user_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_weight_log_usecase.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_service.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_store.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_ui.dart';
import 'package:opennutritracker/fork/adaptive/check_in.dart';
import 'package:opennutritracker/fork/adaptive/expenditure.dart';
import 'package:opennutritracker/fork/adaptive/goal_plan.dart';
import 'package:opennutritracker/fork/adaptive/goal_saving.dart';
import 'package:opennutritracker/fork/body/measurement_store.dart';
import 'package:opennutritracker/core/domain/entity/body_weight_unit_entity.dart';
import 'package:opennutritracker/fork/adaptive/trend_points.dart';
import 'package:opennutritracker/fork/units/weight_text.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:provider/provider.dart';

final _today = DateTime(2026, 10, 22);

UserEntity _user() => UserEntity(
  birthday: DateTime(1990, 1, 1),
  heightCM: 180,
  weightKG: 90,
  gender: UserGenderEntity.male,
  goal: UserWeightGoalEntity.loseWeight,
  pal: UserPALEntity.active,
  weeklyWeightGoalKg: -0.5,
  targetWeightKg: 80,
);

class _User extends Fake implements GetUserUsecase {
  final double rate;

  _User({this.rate = -0.5});

  /// A pace that leaves about [kcal] of a target from the 60 days below.
  _User.pacedTo(double kcal) : rate = (kcal - 2500) * 7 / 7000;

  @override
  Future<UserEntity> getUserData() async => _user()
    ..weeklyWeightGoalKg = rate
    ..goal = rate == 0
        ? UserWeightGoalEntity.maintainWeight
        : UserWeightGoalEntity.loseWeight;
}

/// 60 days of losing 0.5 kg a week on 2,000 kcal, weighed every other day.
class _Weights extends Fake implements GetWeightLogUsecase {
  @override
  Future<List<WeightLogEntity>> getAllEntries() async => [
    for (var d = 59; d >= 0; d -= 2)
      WeightLogEntity(
        date: _today.subtract(Duration(days: d)),
        weightKg: 90 - 0.5 * (59 - d) / 7,
      ),
  ];
}

/// As [_Weights], over the last [days] only: the estimate still calibrates.
class _RecentWeights extends Fake implements GetWeightLogUsecase {
  final int days;

  _RecentWeights(this.days);

  @override
  Future<List<WeightLogEntity>> getAllEntries() async => [
    for (var d = days - 1; d >= 0; d--)
      WeightLogEntity(
        date: _today.subtract(Duration(days: d)),
        weightKg: 90 - 0.5 * (days - 1 - d) / 7,
      ),
  ];
}

class _NoWeights extends Fake implements GetWeightLogUsecase {
  @override
  Future<List<WeightLogEntity>> getAllEntries() async => [];
}

class _TrackedDays extends Fake implements GetTrackedDayUsecase {
  @override
  Future<List<TrackedDayEntity>> getTrackedDaysByRange(
    DateTime start,
    DateTime end,
  ) async => [
    for (var d = 0; d < 60; d++)
      TrackedDayEntity(
        day: _today.subtract(Duration(days: d)),
        calorieGoal: 2000,
        caloriesTracked: 2000,
      ),
  ];
}

/// A new user: the weigh-in from onboarding, nothing logged.
class _OneWeighIn extends Fake implements GetWeightLogUsecase {
  @override
  Future<List<WeightLogEntity>> getAllEntries() async => [
    WeightLogEntity(date: _today, weightKg: 90),
  ];
}

class _NoLogs extends Fake implements GetTrackedDayUsecase {
  @override
  Future<List<TrackedDayEntity>> getTrackedDaysByRange(
    DateTime start,
    DateTime end,
  ) async => [];
}

/// The check-in on a phone's width at 200% text.
Future<void> _pumpLarge(WidgetTester tester, AdaptiveService service) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: const TextScaler.linear(2)),
        child: child!,
      ),
      home: CheckInScreen(service: service),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  late Directory dir;
  late AdaptiveStore store;
  late AdaptiveService service;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('adaptive');
    Hive.init(dir.path);
    store = AdaptiveStore(() => Hive.openBox<dynamic>(AdaptiveStore.boxName));
    service = AdaptiveService(
      _User(),
      _Weights(),
      _TrackedDays(),
      store,
      () => _today.add(const Duration(hours: 9)),
    );
    AdaptiveStore.settings.value = const AdaptiveSettings();
  });

  tearDown(() async {
    AdaptiveStore.settings.value = const AdaptiveSettings();
    await Hive.deleteFromDisk();
    await dir.delete(recursive: true);
  });

  group('computeCheckIn', () {
    CheckIn run({double? previous, int days = 60}) => computeCheckIn(
      CheckInInputs(
        days: [
          for (var d = 0; d < days; d++)
            AdaptiveDay(intakeKcal: 2000, weightKg: 90 - 0.5 * d / 7),
        ],
        priorKcal: 2500,
        goalRateKgPerWeek: -0.5,
        bodyFatPercent: 25,
        targetWeightKg: 80,
        previousBaseKcal: previous,
        taper: (adjustment, _) => adjustment,
      ),
    );

    test('the target is expenditure less the energy of the goal', () {
      final checkIn = run();

      // 0.5 kg/week at ~22 kg of fat (~7,000 kcal/kg) is ~500 kcal/day.
      expect(checkIn.expenditureKcal, closeTo(2500, 60));
      expect(
        checkIn.uncappedTargetKcal,
        closeTo(checkIn.expenditureKcal - 500, 30),
      );
      expect(checkIn.enoughData, isTrue);
      expect(checkIn.weekChangeKg, closeTo(-0.5, 0.05));
    });

    test('a check-in moves the expenditure under the target at most '
        '200 kcal, and the goal in full', () {
      final c = run(previous: 2000);
      expect(c.baseKcal, 2200);
      expect(
        c.proposedTargetKcal,
        closeTo(c.uncappedTargetKcal - (c.expenditureKcal - 2200), 0.01),
      );
      // The goal's energy is the whole of the gap below the base.
      expect(c.proposedTargetKcal, closeTo(2200 - 500, 30));
    });

    test('nothing holds the estimate back before the first check-in or '
        'while it calibrates', () {
      final first = run();
      expect(first.proposedTargetKcal, first.uncappedTargetKcal);
      // 20 days: 6 updates past the warm-up, under the 16 calibrating.
      final calibrating = run(previous: 1000, days: 20);
      expect(calibrating.baseKcal, calibrating.expenditureKcal);
    });

    test('back from a break the target holds at the last check-in\'s '
        'base (D27)', () {
      final c = computeCheckIn(
        CheckInInputs(
          days: [
            for (var d = 0; d < 40; d++)
              AdaptiveDay(intakeKcal: 2000, weightKg: 90 - 0.5 * d / 7),
            for (var d = 0; d < 7; d++) const AdaptiveDay(),
            for (var d = 0; d < 5; d++)
              const AdaptiveDay(intakeKcal: 2000, weightKg: 89),
          ],
          priorKcal: 2500,
          goalRateKgPerWeek: -0.5,
          bodyFatPercent: 25,
          previousBaseKcal: 2450,
          taper: (adjustment, _) => adjustment,
        ),
      );
      expect(c.breakHold, isNotNull);
      expect(c.enoughData, isFalse);
      expect(c.baseKcal, 2450);
      expect(c.proposedTargetKcal, c.uncappedTargetKcal);
    });

    test('with no weigh-in the goal\'s energy is at the fallback weight', () {
      final c = computeCheckIn(
        CheckInInputs(
          days: [const AdaptiveDay(intakeKcal: 2000)],
          priorKcal: 2500,
          goalRateKgPerWeek: -0.5,
          bodyFatPercent: 25,
          previousBaseKcal: null,
          fallbackWeightKg: 120,
          taper: (adjustment, weight) {
            expect(weight, 120);
            return adjustment;
          },
        ),
      );
      expect(c.kcalPerKg, const ExpenditureSettings().kcalPerKgAt(120, 25));
    });

    group('with no update in the history', () {
      CheckIn aged({double? previous}) => computeCheckIn(
        CheckInInputs(
          days: [for (var d = 0; d < 30; d++) const AdaptiveDay()],
          priorKcal: 2500,
          goalRateKgPerWeek: -0.5,
          bodyFatPercent: 25,
          previousBaseKcal: previous,
          taper: (adjustment, _) => adjustment,
        ),
      );

      test('the last check-in\'s base carries over, not the prior', () {
        final c = aged(previous: 2200);
        expect(c.baseKcal, 2200);
        expect(c.expenditureKcal, 2200);
        expect(c.proposedTargetKcal, c.uncappedTargetKcal);
        expect(c.proposedTargetKcal, lessThan(2200));
      });

      test('before any check-in it is the prior', () {
        expect(aged().baseKcal, 2500);
      });
    });

    group('whether the check-in limit was compared', () {
      test('it was, and the estimate moved no more than it', () {
        final free = run().baseKcal;
        final c = run(previous: free - 100);
        expect(c.movedWithinCap, isTrue);
        expect(c.capCalibrating, isFalse);
      });

      test('it was, and it held the estimate back', () {
        final free = run().baseKcal;
        expect(run(previous: free - 500).movedWithinCap, isFalse);
      });

      test('no mark to compare with', () {
        expect(run().movedWithinCap, isFalse);
      });

      test('still calibrating: not compared', () {
        final c = run(previous: 2400, days: 20);
        expect(c.movedWithinCap, isFalse);
        expect(c.capCalibrating, isTrue);
      });
    });

    test('days to the target weight round up, as the planner\'s do', () {
      final c = computeCheckIn(
        CheckInInputs(
          days: [
            for (var d = 0; d < 10; d++)
              const AdaptiveDay(intakeKcal: 2000, weightKg: 90),
          ],
          priorKcal: 2500,
          goalRateKgPerWeek: -0.3,
          bodyFatPercent: 25,
          targetWeightKg: 89,
          previousBaseKcal: null,
          taper: (adjustment, _) => adjustment,
        ),
      );
      // 1 kg at 0.3 a week is 23.3 days.
      expect(c.daysToTargetAtGoal, 24);
      expect(c.daysToTargetAtGoal, daysToTarget(90, 89, -0.3 / 7));
    });

    test('the target weight is about 13 weeks off at either pace', () {
      final checkIn = run();

      // The scale is at 85.8 kg and the trend lags it a little above.
      expect(checkIn.daysToTargetAtGoal, inInclusiveRange(80, 100));
      expect(checkIn.daysToTargetAtTrend, inInclusiveRange(80, 100));
    });
  });

  group('AdaptiveService', () {
    test('reads the profile, weight log and tracked days', () async {
      final checkIn = await service.checkIn();

      expect(checkIn.loggedDays, 7);
      expect(checkIn.weighIns, inInclusiveRange(3, 4));
      expect(checkIn.expenditureKcal, greaterThan(2200));
      // The first check-in has no estimate before it to hold to.
      expect(checkIn.proposedTargetKcal, checkIn.uncappedTargetKcal);
      expect(checkIn.uncappedTargetKcal, lessThan(checkIn.expenditureKcal));
      expect(checkIn.goalRateKgPerWeek, -0.5);
      expect(checkIn.targetWeightKg, 80);
    });

    test(
      'the accepted target is the goal only while the switch is on',
      () async {
        final checkIn = await service.checkIn();
        await service.accept(checkIn, 2100);

        expect((await forkKcalGoal(_today)).target, isNull);
        expect((await forkKcalGoal(_today, store)).target, isNull);
        await store.save(const AdaptiveSettings(adaptiveTarget: true));
        expect((await forkKcalGoal(_today, store)).target, 2100);
      },
    );

    test('another profile answers with its own switch and target', () async {
      await store.save(const AdaptiveSettings(adaptiveTarget: true));
      await service.accept(await service.checkIn(), 2100);
      final other = AdaptiveStore(() => Hive.openBox<dynamic>('other'));

      expect((await forkKcalGoal(_today, other)).target, isNull);
      await other.save(const AdaptiveSettings(adaptiveTarget: true));
      expect((await forkKcalGoal(_today, other)).target, isNull);
      expect((await forkKcalGoal(_today, store)).target, 2100);
    });

    test('with no weigh-in the profile\'s weight sets the energy of the '
        'goal', () async {
      final c = await AdaptiveService(
        _User(),
        _NoWeights(),
        _NoLogs(),
        store,
        () => _today.add(const Duration(hours: 9)),
      ).checkIn();
      expect(c.trendKg, isNull);
      expect(
        c.kcalPerKg,
        const ExpenditureSettings().kcalPerKgAt(90, bodyFatPercent(_user())),
      );
    });

    group('auto-accept', () {
      const auto = AdaptiveSettings(
        adaptiveTarget: true,
        autoAcceptCheckIn: true,
      );
      AdaptiveService paced(double kcal, AdaptiveStore into) => AdaptiveService(
        _User.pacedTo(kcal),
        _Weights(),
        _TrackedDays(),
        into,
        () => _today.add(const Duration(hours: 9)),
      );

      test('takes a proposal at the floor or over it', () async {
        AdaptiveStore.settings.value = auto;
        final memory = _MemoryStore();
        final due = paced(1800, memory);
        final accepted = await due.autoAcceptIfDue();
        expect(accepted, isNotNull);
        expect(accepted!.belowRecommendedFloor, isFalse);
        expect(memory.records, hasLength(1));
      });

      test(
        'refuses one whose activity could not be read, and says so',
        () async {
          AdaptiveStore.settings.value = const AdaptiveSettings(
            adaptiveTarget: true,
            autoAcceptCheckIn: true,
            activityMode: ActivityMode.weekly,
          );
          final memory = _MemoryStore();
          final due = AdaptiveService(
            _User.pacedTo(1800),
            _Weights(),
            _TrackedDays(),
            memory,
            () => _today.add(const Duration(hours: 9)),
            null,
            _UnreadableActivity(),
          );
          expect((await due.checkIn()).activityUnreadable, isTrue);
          expect(await due.autoAcceptIfDue(), isNull);
          expect(memory.records, isEmpty);
        },
      );

      test(
        'an unread check-in kept leaves the last known base and activity',
        () async {
          AdaptiveStore.settings.value = const AdaptiveSettings(
            adaptiveTarget: true,
            activityMode: ActivityMode.weekly,
          );
          final memory = _MemoryStore()
            ..records.add(
              CheckInRecord(
                date: _today.subtract(const Duration(days: 8)),
                expenditureKcal: 2300,
                proposedKcal: 1800,
                acceptedKcal: 1800,
                activityKcal: 300,
                baseKcal: 2000,
              ),
            );
          final due = AdaptiveService(
            _User.pacedTo(1800),
            _Weights(),
            _TrackedDays(),
            memory,
            () => _today.add(const Duration(hours: 9)),
            null,
            _UnreadableActivity(),
          );
          await due.accept(await due.checkIn(), 1800);
          expect(memory.records.last.activityKcal, 300);
          expect(memory.records.last.baseKcal, 2000);
        },
      );

      test('refuses one under the floor, and it stays due', () async {
        AdaptiveStore.settings.value = auto;
        final memory = _MemoryStore();
        final due = paced(1000, memory);
        final proposal = await due.checkIn();
        // The male floor; the proposal is not clamped to it.
        expect(proposal.recommendedFloorKcal, 1500);
        expect(proposal.proposedTargetKcal, lessThan(1500));
        expect(await due.autoAcceptIfDue(), isNull);
        expect(memory.records, isEmpty);
        expect(await due.checkInDue(), isTrue);
      });
    });

    test('a check-in is due a week after the last', () async {
      expect(await service.checkInDue(), isFalse);
      AdaptiveStore.settings.value = const AdaptiveSettings(
        adaptiveTarget: true,
      );
      expect(await service.checkInDue(), isTrue);

      await service.accept(await service.checkIn(), 2100);
      expect(await service.checkInDue(), isFalse);
    });

    test('a changed goal is due a check-in at once', () async {
      AdaptiveStore.settings.value = const AdaptiveSettings(
        adaptiveTarget: true,
      );
      await service.accept(await service.checkIn(), 2100);
      final maintain = AdaptiveService(
        _User(rate: 0),
        _Weights(),
        _TrackedDays(),
        store,
        () => _today.add(const Duration(hours: 9)),
      );
      expect(await service.goalChanged(), isFalse);
      expect(await maintain.goalChanged(), isTrue);
      expect(await maintain.checkInDue(), isTrue);

      final checkIn = await maintain.checkIn();
      // The 500 kcal of the loss goal is all gone in this one check-in.
      expect(checkIn.proposedTargetKcal, closeTo(checkIn.expenditureKcal, 1));
      await maintain.accept(checkIn, checkIn.proposedTargetKcal);
      expect(await maintain.checkInDue(), isFalse);
    });

    test('settings the target is built under are due a check-in', () async {
      AdaptiveStore.settings.value = const AdaptiveSettings(
        adaptiveTarget: true,
      );
      await service.accept(await service.checkIn(), 2100);
      expect(await service.checkInDue(), isFalse);

      // Responsiveness leaves the target as it is; activity counted or a
      // flat kcal per kg does not.
      AdaptiveStore.settings.value = AdaptiveStore.settings.value.copyWith(
        responsiveness: Responsiveness.responsive,
      );
      expect(await service.checkInDue(), isFalse);
      for (final changed in [
        const AdaptiveSettings(
          adaptiveTarget: true,
          activityMode: ActivityMode.daily,
        ),
        const AdaptiveSettings(adaptiveTarget: true, flatEnergy: true),
      ]) {
        AdaptiveStore.settings.value = changed;
        expect(await service.basisChanged(), isTrue, reason: '$changed');
        expect(await service.checkInDue(), isTrue);
      }
      await service.accept(await service.checkIn(), 2100);
      expect(await service.checkInDue(), isFalse);

      final record = (await store.lastCheckIn())!;
      expect(CheckInRecord.fromJson(record.toJson()).basis, record.basis);
      // An older record, without one, is not due for it.
      final older = CheckInRecord.fromJson(
        {...record.toJson()}..remove('basis'),
      );
      expect(older.basisChanged(const AdaptiveSettings()), isFalse);
    });

    test("a check-in under other settings gives no change in the week's "
        'activity', () async {
      AdaptiveStore.settings.value = const AdaptiveSettings(
        adaptiveTarget: true,
        activityMode: ActivityMode.daily,
      );
      await service.accept(await service.checkIn(), 2100);
      // The daily mode keeps none of its activity in the target: the
      // weekly mode's first check-in has nothing to compare with.
      AdaptiveStore.settings.value = const AdaptiveSettings(
        adaptiveTarget: true,
        activityMode: ActivityMode.weekly,
      );
      expect((await service.checkIn()).activityChangeKcal, isNull);

      await service.accept(await service.checkIn(), 2100);
      expect((await service.checkIn()).activityChangeKcal, 0);
    });

    test(
      'a check-in is capped against a base of the same settings only',
      () async {
        const settings = AdaptiveSettings(
          adaptiveTarget: true,
          maxCheckInChangeKcal: 100,
        );
        AdaptiveStore.settings.value = settings;
        final free = (await service.checkIn()).baseKcal;
        await store.addCheckIn(
          CheckInRecord(
            date: _today.subtract(const Duration(days: 7)),
            expenditureKcal: free - 500,
            proposedKcal: 2000,
            acceptedKcal: 2000,
            baseKcal: free - 500,
            basis: settings.targetBasis,
          ),
        );
        expect((await service.checkIn()).baseKcal, closeTo(free - 400, 0.01));

        AdaptiveStore.settings.value = settings.copyWith(
          activityMode: ActivityMode.weekly,
        );
        final switched = await service.checkIn();
        expect(switched.baseKcal, closeTo(free, 0.01));

        // Switched back, as auto-accept takes each switch: capped against
        // the record of these settings again, not the switch's.
        await service.accept(switched, switched.proposedTargetKcal);
        AdaptiveStore.settings.value = settings;
        expect((await service.checkIn()).baseKcal, closeTo(free - 400, 0.01));
      },
    );

    test("switches in a day keep one record of their own", () async {
      const settings = AdaptiveSettings(adaptiveTarget: true);
      await store.addCheckIn(
        CheckInRecord(
          date: _today.subtract(const Duration(days: 3)),
          expenditureKcal: 2500,
          proposedKcal: 2000,
          acceptedKcal: 2000,
          baseKcal: 2500,
          basis: settings.targetBasis,
        ),
      );
      // Back and forth, landing on the seed's settings on the way.
      for (final s in [
        settings.copyWith(activityMode: ActivityMode.daily),
        settings,
        settings.copyWith(flatEnergy: true),
        settings,
      ]) {
        AdaptiveStore.settings.value = s;
        final due = await service.checkIn();
        await service.accept(due, due.proposedTargetKcal);
      }
      final history = await store.history();
      expect(history, hasLength(2));
      expect(history.last.basis, settings.targetBasis);

      // A check-in of the same settings is a record of its own; a switch
      // after it takes its place, as the day's target is the switch's.
      final weekly = await service.checkIn();
      await service.accept(weekly, weekly.proposedTargetKcal);
      expect(await store.history(), hasLength(3));
      AdaptiveStore.settings.value = settings.copyWith(flatEnergy: true);
      final due = await service.checkIn();
      await service.accept(due, due.proposedTargetKcal);
      final last = await store.history();
      expect(last, hasLength(3));
      expect(last.last.basis, AdaptiveStore.settings.value.targetBasis);
    });

    test('a record of these settings weeks before the last is no mark', () {
      const settings = AdaptiveSettings(adaptiveTarget: true);
      CheckInRecord at(int daysAgo, AdaptiveSettings s) => CheckInRecord(
        date: _today.subtract(Duration(days: daysAgo)),
        expenditureKcal: 2500,
        proposedKcal: 2000,
        acceptedKcal: 2000,
        baseKcal: 2500,
        basis: s.targetBasis,
      );
      final daily = settings.copyWith(activityMode: ActivityMode.daily);
      expect(
        AdaptiveService.capMark([at(30, settings), at(0, daily)], settings),
        isNull,
      );
      expect(
        AdaptiveService.capMark([at(7, settings), at(0, daily)], settings),
        isNotNull,
      );
    });

    test('a record without its settings gives no activity change', () async {
      AdaptiveStore.settings.value = const AdaptiveSettings(
        adaptiveTarget: true,
        activityMode: ActivityMode.weekly,
      );
      await store.addCheckIn(
        CheckInRecord(
          date: _today.subtract(const Duration(days: 7)),
          expenditureKcal: 2500,
          proposedKcal: 2000,
          acceptedKcal: 2000,
          activityKcal: 0,
          baseKcal: 2500,
        ),
      );
      expect((await service.checkIn()).activityChangeKcal, isNull);
    });

    test('the settings are saved and loaded', () async {
      await store.save(
        const AdaptiveSettings(smoothedTrend: true, cycleWindow: true),
      );
      AdaptiveStore.settings.value = const AdaptiveSettings();

      await store.load();

      expect(AdaptiveStore.settings.value.smoothedTrend, isTrue);
      expect(AdaptiveStore.settings.value.adaptiveTarget, isFalse);
      expect(AdaptiveStore.settings.value.cycleWindow, isTrue);
    });
  });

  test('the chart gets a smoothed point a day', () async {
    final points = trendPoints(await _Weights().getAllEntries());

    expect(points, hasLength(59));
    expect(points.first.weightKg, 90);
    expect(points.last.weightKg, lessThan(90));
  });

  testWidgets('accepting the check-in hides the card and refreshes', (
    tester,
  ) async {
    AdaptiveStore.settings.value = const AdaptiveSettings(adaptiveTarget: true);
    final memory = _MemoryStore();
    var refreshed = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdaptiveCheckInCard(
            service: AdaptiveService(
              _User(),
              _Weights(),
              _TrackedDays(),
              memory,
              () => _today.add(const Duration(hours: 9)),
            ),
            onAccepted: () => refreshed++,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // None accepted yet: the first, not a weekly one.
    expect(find.text('Weekly check-in'), findsNothing);
    await tester.tap(find.text('Your first target'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Accept'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('Accept'));
    await tester.pumpAndSettle();

    expect(refreshed, 1);
    expect(find.text('Your first target'), findsNothing);
    expect(memory.records, hasLength(1));
    expect(find.textContaining('Daily target set to'), findsOneWidget);
  });

  testWidgets('says activity went unread, and names no activity move', (
    tester,
  ) async {
    AdaptiveStore.settings.value = const AdaptiveSettings(
      adaptiveTarget: true,
      activityMode: ActivityMode.weekly,
    );
    final memory = _MemoryStore()
      ..records.add(
        CheckInRecord(
          date: _today.subtract(const Duration(days: 8)),
          expenditureKcal: 2300,
          proposedKcal: 1800,
          acceptedKcal: 1800,
          activityKcal: 300,
          baseKcal: 2000,
        ),
      );
    final service = AdaptiveService(
      _User(),
      _Weights(),
      _TrackedDays(),
      memory,
      () => _today.add(const Duration(hours: 9)),
      null,
      _UnreadableActivity(),
    );
    await tester.pumpWidget(MaterialApp(home: CheckInScreen(service: service)));
    await tester.pumpAndSettle();

    expect(
      find.byKey(
        const ValueKey('check-in-activity-unreadable'),
        skipOffstage: false,
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining("week's activity", skipOffstage: false),
      findsNothing,
    );
  });

  testWidgets('a kilojoule user reads and types the target in kJ', (
    tester,
  ) async {
    final memory = _MemoryStore();
    final service = AdaptiveService(
      _User(),
      _Weights(),
      _TrackedDays(),
      memory,
      () => _today.add(const Duration(hours: 9)),
    );
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => EnergyUnitProvider(usesKilojoules: true),
        child: MaterialApp(home: CheckInScreen(service: service)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining(' kJ'), findsWidgets);
    expect(find.textContaining('kcal'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('Accept'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.enterText(
      find.byKey(const ValueKey('check-in-target')),
      '8368',
    );
    await tester.tap(find.text('Accept'));
    await tester.pumpAndSettle();

    expect(memory.records.single.acceptedKcal, closeTo(2000, 0.01));
  });

  testWidgets('the first check-in shows the target in use and the change', (
    tester,
  ) async {
    locator.registerSingleton<GetKcalGoalUsecase>(_Goal());
    addTearDown(locator.unregister<GetKcalGoalUsecase>);
    final service = AdaptiveService(
      _User(),
      _Weights(),
      _TrackedDays(),
      _MemoryStore(),
      () => _today.add(const Duration(hours: 9)),
    );
    final checkIn = await tester.runAsync(service.checkIn);
    await tester.pumpWidget(MaterialApp(home: CheckInScreen(service: service)));
    await tester.pumpAndSettle();

    // Home's goal adds the day's activity to it.
    expect(find.text('Formula target without activity'), findsOneWidget);
    expect(find.text('2847 kcal'), findsOneWidget);
    expect(find.text('Change'), findsOneWidget);
    // The rows add up as shown.
    final proposed = checkIn!.proposedTargetKcal.round();
    expect(find.text('${proposed - 2847} kcal'), findsOneWidget);
    expect(
      find.textContaining(
        'That is the expenditure less '
        '${checkIn.expenditureKcal.round() - proposed} kcal',
      ),
      findsOneWidget,
    );
    // The goal page's figure for the pace is at 7700 a kg; this one says
    // what it is at.
    expect(
      find.textContaining(
        'at ${checkIn.kcalPerKg!.toInt()} kcal a kg of weight change '
        '(from your body fat).',
      ),
      findsOneWidget,
    );
  });

  testWidgets('the first check-in leaves today\'s weekday shift out of the '
      'target in use, as the proposal does', (tester) async {
    locator.registerSingleton<GetKcalGoalUsecase>(_Goal());
    locator.registerSingleton<GetConfigUsecase>(_Config());
    addTearDown(locator.unregister<GetKcalGoalUsecase>);
    addTearDown(locator.unregister<GetConfigUsecase>);
    // Only today's shift, so another day's would show.
    AdaptiveStore.settings.value = AdaptiveSettings(
      weekdayOffsets: [
        for (var d = 1; d <= 7; d++) d == DateTime.now().weekday ? 300 : 0,
      ],
    );
    addTearDown(() => AdaptiveStore.settings.value = const AdaptiveSettings());
    final service = AdaptiveService(
      _User(),
      _Weights(),
      _TrackedDays(),
      _MemoryStore(),
      () => _today.add(const Duration(hours: 9)),
    );
    await tester.pumpWidget(MaterialApp(home: CheckInScreen(service: service)));
    await tester.pumpAndSettle();

    expect(find.text('2547 kcal'), findsOneWidget);
  });

  testWidgets("a new user's first check-in says it is from the profile", (
    tester,
  ) async {
    final service = AdaptiveService(
      _User(),
      _OneWeighIn(),
      _NoLogs(),
      _MemoryStore(),
      () => _today.add(const Duration(hours: 9)),
    );
    await _pumpLarge(tester, service);

    expect(find.textContaining('Your first target'), findsOneWidget);
    expect(find.textContaining('under the formula'), findsOneWidget);
    // No week before it to report, nor to carry the expenditure from.
    expect(find.text('Past week'), findsNothing);
    expect(find.textContaining('Not enough data'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a later check-in without an update keeps its past week', (
    tester,
  ) async {
    final memory = _MemoryStore();
    final service = AdaptiveService(
      _User(),
      _OneWeighIn(),
      _NoLogs(),
      memory,
      () => _today.add(const Duration(hours: 9)),
    );
    await service.accept(await service.checkIn(), 2000);
    await _pumpLarge(tester, service);

    expect(find.textContaining('Your first target'), findsNothing);
    expect(find.text('Past week'), findsOneWidget);
    expect(find.textContaining('Not enough data'), findsOneWidget);
  });

  testWidgets('a later check-in shows the current target and the change', (
    tester,
  ) async {
    final service = AdaptiveService(
      _User(),
      _Weights(),
      _TrackedDays(),
      _MemoryStore(),
      () => _today.add(const Duration(hours: 9)),
    );
    await service.accept(await service.checkIn(), 2000);
    // As shown: the rows add up.
    final change = (await service.checkIn()).proposedTargetKcal.round() - 2000;
    await _pumpLarge(tester, service);

    final current = find.text('Current target');
    await tester.scrollUntilVisible(current, 200);
    expect(find.text('2000 kcal'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Change'), 200);
    expect(find.text('${change > 0 ? '+' : ''}$change kcal'), findsOneWidget);
    // The cap is explained whether or not it held the change back.
    final cap = find.textContaining(RegExp('check-in limit|A check-in moves'));
    await tester.scrollUntilVisible(cap, 200);
    expect(cap, findsOneWidget);
  });

  group('the check-in limit\'s line', () {
    AdaptiveService limited(GetWeightLogUsecase weights) => AdaptiveService(
      _User(),
      weights,
      _TrackedDays(),
      _MemoryStore(),
      () => _today.add(const Duration(hours: 9)),
    );
    Future<void> pumpTall(WidgetTester tester, AdaptiveService service) async {
      tester.view.physicalSize = const Size(1000, 4000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(home: CheckInScreen(service: service)),
      );
      await tester.pumpAndSettle();
    }

    final within = find.textContaining('moved less than');
    final notYet = find.textContaining('does not apply yet');

    testWidgets('says the change is within it only once compared', (
      tester,
    ) async {
      final service = limited(_Weights());
      await service.accept(await service.checkIn(), 2000);
      await pumpTall(tester, service);
      expect(within, findsOneWidget);
      expect(notYet, findsNothing);
    });

    testWidgets('while calibrating says it does not apply yet', (tester) async {
      final service = limited(_RecentWeights(20));
      await service.accept(await service.checkIn(), 2000);
      await pumpTall(tester, service);
      expect(within, findsNothing);
      expect(notYet, findsOneWidget);
    });

    testWidgets('with no record of these settings claims nothing', (
      tester,
    ) async {
      final service = limited(_Weights());
      final due = await service.checkIn();
      // Accepted under other settings: no mark for these.
      AdaptiveStore.settings.value = const AdaptiveSettings(flatEnergy: true);
      await service.accept(due, 2000);
      AdaptiveStore.settings.value = const AdaptiveSettings();
      await pumpTall(tester, service);
      expect(within, findsNothing);
      expect(notYet, findsNothing);
    });
  });

  testWidgets('in the daily mode the expenditure row says it holds the '
      'activity the row below names', (tester) async {
    AdaptiveStore.settings.value = const AdaptiveSettings(
      activityMode: ActivityMode.daily,
    );
    final service = AdaptiveService(
      _User(),
      _Weights(),
      _TrackedDays(),
      _MemoryStore(),
      () => _today.add(const Duration(hours: 9)),
    );
    await tester.pumpWidget(MaterialApp(home: CheckInScreen(service: service)));
    await tester.pumpAndSettle();
    expect(find.text('Expenditure before activity'), findsNothing);
    expect(find.text("Expenditure with this week's activity"), findsOneWidget);
  });

  group('a proposal under the advised floor', () {
    AdaptiveService paced(double kcal, [_MemoryStore? memory]) =>
        AdaptiveService(
          _User.pacedTo(kcal),
          _Weights(),
          _TrackedDays(),
          memory ?? _MemoryStore(),
          () => _today.add(const Duration(hours: 9)),
        );
    Future<void> pumpTall(WidgetTester tester, AdaptiveService service) async {
      tester.view.physicalSize = const Size(1000, 4000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(home: CheckInScreen(service: service)),
      );
      await tester.pumpAndSettle();
    }

    final warning = find.byKey(const ValueKey('check-in-below-floor'));
    TextField field(WidgetTester tester) =>
        tester.widget<TextField>(find.byKey(const ValueKey('check-in-target')));

    testWidgets('is warned of and still offered, not clamped', (tester) async {
      final service = paced(1000);
      final proposed = (await service.checkIn()).proposedTargetKcal;
      await pumpTall(tester, service);
      expect(warning, findsOneWidget);
      expect(find.textContaining('1500 kcal a day'), findsOneWidget);
      expect(field(tester).controller!.text, '${proposed.round()}');
    });

    testWidgets('over it, no warning', (tester) async {
      await pumpTall(tester, paced(1800));
      expect(warning, findsNothing);
    });

    testWidgets('of nothing or less is not prefilled, and Accept says why', (
      tester,
    ) async {
      final memory = _MemoryStore();
      final service = paced(-500, memory);
      expect(
        (await service.checkIn()).proposedTargetKcal,
        lessThanOrEqualTo(0),
      );
      await pumpTall(tester, service);
      expect(warning, findsOneWidget);
      expect(field(tester).controller!.text, isEmpty);

      await tester.tap(find.text('Accept'));
      await tester.pump();
      expect(find.text('Enter a daily target above 0 kcal.'), findsOneWidget);
      expect(memory.records, isEmpty);
    });

    testWidgets('with auto-accept on, the card stays to be done by hand', (
      tester,
    ) async {
      AdaptiveStore.settings.value = const AdaptiveSettings(
        adaptiveTarget: true,
        autoAcceptCheckIn: true,
      );
      final memory = _MemoryStore();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdaptiveCheckInCard(
              service: paced(1000, memory),
              onAccepted: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(memory.records, isEmpty);
      expect(find.text('Your first target'), findsOneWidget);
      expect(find.text('Your first target is set'), findsNothing);
    });
  });

  group('a user who weighs in pounds', () {
    setUp(() {
      locator.registerSingleton<GetConfigUsecase>(
        _Config(unit: BodyWeightUnit.lb),
      );
    });
    tearDown(() => locator.unregister<GetConfigUsecase>());

    testWidgets('reads the check-in in pounds, not kg', (tester) async {
      tester.view.physicalSize = const Size(1000, 4000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final service = AdaptiveService(
        _User(),
        _Weights(),
        _TrackedDays(),
        _MemoryStore(),
        () => _today.add(const Duration(hours: 9)),
      );
      final checkIn = await tester.runAsync(service.checkIn);
      await tester.pumpWidget(
        MaterialApp(home: CheckInScreen(service: service)),
      );
      await tester.pumpAndSettle();

      expect(
        find.text(weightText(checkIn!.trendKg!, BodyWeightUnit.lb)),
        findsOneWidget,
      );
      expect(
        find.text(weightChangeText(checkIn.weekChangeKg!, BodyWeightUnit.lb)),
        findsOneWidget,
      );
      expect(find.textContaining('for -1.1 lb a week'), findsOneWidget);
      final perLb = (checkIn.kcalPerKg! / 2.20462).round();
      expect(
        find.textContaining('at $perLb kcal a lb of weight change'),
        findsOneWidget,
      );
      expect(find.textContaining(RegExp(r'\bkg\b')), findsNothing);
    });
  });

  testWidgets('Keep current target records the check-in at it', (tester) async {
    final memory = _MemoryStore();
    final service = AdaptiveService(
      _User(),
      _Weights(),
      _TrackedDays(),
      memory,
      () => _today.add(const Duration(hours: 9)),
    );
    await service.accept(await service.checkIn(), 2100);
    await _pumpLarge(tester, service);
    // The proposal is another figure, so Accept would have stored it.
    expect(
      (await service.checkIn()).proposedTargetKcal,
      isNot(closeTo(2100, 1)),
    );

    final keep = find.byKey(const ValueKey('check-in-keep'));
    await tester.scrollUntilVisible(
      keep,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(keep);
    await tester.pumpAndSettle();
    await tester.tap(keep);
    await tester.pumpAndSettle();
    expect(memory.accepts, 2);
    expect(memory.records.last.acceptedKcal, 2100);
  });

  testWidgets("without Home's target, the first check-in shows no change", (
    tester,
  ) async {
    final service = AdaptiveService(
      _User(),
      _Weights(),
      _TrackedDays(),
      _MemoryStore(),
      () => _today.add(const Duration(hours: 9)),
    );
    await _pumpLarge(tester, service);

    expect(find.text('Current target'), findsNothing);
    expect(find.text('Change'), findsNothing);
  });

  testWidgets('a settings change names the setting that changed', (
    tester,
  ) async {
    const weekly = AdaptiveSettings(
      adaptiveTarget: true,
      activityMode: ActivityMode.weekly,
    );
    AdaptiveStore.settings.value = weekly;
    addTearDown(() => AdaptiveStore.settings.value = const AdaptiveSettings());
    final service = AdaptiveService(
      _User(),
      _Weights(),
      _TrackedDays(),
      _MemoryStore(),
      () => _today.add(const Duration(hours: 9)),
    );
    await service.accept(await service.checkIn(), 2000);
    AdaptiveStore.settings.value = weekly.copyWith(countSteps: false);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdaptiveCheckInCard(service: service, onAccepted: () {}),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Your target settings changed'), findsOneWidget);
    expect(find.textContaining('You changed steps.'), findsOneWidget);
  });

  testWidgets('a check-in the settings made due is headed with the change', (
    tester,
  ) async {
    AdaptiveStore.settings.value = const AdaptiveSettings(adaptiveTarget: true);
    addTearDown(() => AdaptiveStore.settings.value = const AdaptiveSettings());
    final service = AdaptiveService(
      _User(),
      _Weights(),
      _TrackedDays(),
      _MemoryStore(),
      () => _today.add(const Duration(hours: 9)),
    );
    await service.accept(await service.checkIn(), 2000);
    AdaptiveStore.settings.value = const AdaptiveSettings(
      adaptiveTarget: true,
      activityMode: ActivityMode.weekly,
    );
    await tester.pumpWidget(MaterialApp(home: CheckInScreen(service: service)));
    await tester.pumpAndSettle();

    expect(find.text('Target settings changed'), findsOneWidget);
    expect(find.text('Weekly check-in'), findsNothing);
    expect(find.text('Activity is now counted weekly'), findsOneWidget);
    expect(
      find.text(
        'So the expenditure now takes your average counted activity off '
        "and adds the past week's, which had none: a quieter week than "
        'usual lowers the target.',
      ),
      findsOneWidget,
    );
    // not Trends' expenditure, which holds the average activity
    expect(find.text("Expenditure with this week's activity"), findsOneWidget);
  });

  test('each changed setting is a sentence', () {
    expect(
      targetSettingsChanges(
        'activity=weekly;steps=true;workouts=true;flat=false',
        'activity=daily;steps=false;workouts=true;flat=true',
      ),
      [
        'Activity is now counted daily',
        'Steps are no longer counted',
        'Weight change now counts at the common energy per kg',
      ],
    );
    // Steps are not in a basis without activity: only the mode is told.
    expect(
      targetSettingsChanges(
        'activity=weekly;steps=true;workouts=true;flat=false',
        'activity=off;flat=false',
      ),
      ['Activity is no longer counted'],
    );
  });

  testWidgets('a row at 200% text wraps its value below the label', (
    tester,
  ) async {
    final service = AdaptiveService(
      _User(),
      _Weights(),
      _TrackedDays(),
      _MemoryStore(),
      () => _today.add(const Duration(hours: 9)),
    );
    await _pumpLarge(tester, service);

    final label = find.text('Target weight, chosen pace');
    await tester.scrollUntilVisible(label, 200);
    // Squeezed beside its value it took a letter a line.
    expect(tester.getSize(label).height, lessThan(200));
    expect(find.textContaining('Your first target'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('a small pace is still maintaining', () {
    expect(goalOfPace(0.05), UserWeightGoalEntity.maintainWeight);
    expect(goalOfPace(-0.05), UserWeightGoalEntity.maintainWeight);
    expect(goalOfPace(0), UserWeightGoalEntity.maintainWeight);
    expect(goalOfPace(0.1), UserWeightGoalEntity.gainWeight);
    expect(goalOfPace(-0.1), UserWeightGoalEntity.loseWeight);
  });

  test('a measured body fat % changes the expenditure read', () async {
    final measurements = MeasurementStore(
      () => Hive.openBox<dynamic>('measurements'),
    );
    await measurements.addDay(_today, {BodyMetric.bodyFat: 10});
    final lean = AdaptiveService(
      _User(),
      _Weights(),
      _TrackedDays(),
      store,
      () => _today.add(const Duration(hours: 9)),
      measurements,
    );

    // Leaner: more of a loss is lean tissue, worth less energy, so the
    // same loss on the same intake reads as a lower expenditure.
    expect(
      (await lean.checkIn()).expenditureKcal,
      lessThan((await service.checkIn()).expenditureKcal),
    );
  });

  group('expenditure history', () {
    test(
      'every day from the first weigh-in, settled after two weeks',
      () async {
        final days = await service.expenditureHistory();

        expect(days.length, 60);
        expect(days.last.date, _today);
        expect(days.first.settled, isFalse);
        expect(days.last.settled, isTrue);
        expect(days.last.intakeKcal, 2000);
        // Losing 0.5 kg a week on 2,000 kcal: expenditure is well above it.
        expect(days.last.expenditureKcal, greaterThan(2300));
      },
    );

    test('nothing without a weigh-in', () async {
      final none = AdaptiveService(
        _User(),
        _NoWeights(),
        _TrackedDays(),
        store,
        () => _today,
      );
      expect(await none.expenditureHistory(), isEmpty);
    });
  });
}

class _Config extends Fake implements GetConfigUsecase {
  final BodyWeightUnit unit;

  _Config({this.unit = BodyWeightUnit.kg});

  @override
  Future<ConfigEntity> getConfig() async => ConfigEntity(
    true,
    true,
    false,
    AppThemeEntity.system,
    bodyWeightUnit: unit,
  );
}

class _Goal extends Fake implements GetKcalGoalUsecase {
  @override
  Future<double> getKcalGoal({
    UserEntity? userEntity,
    double? totalKcalActivitiesParam,
    double? kcalUserAdjustment,
  }) async => totalKcalActivitiesParam == 0 ? 2847 : 3096;
}

/// Hive's file I/O does not finish in a widget test's fake time.
class _MemoryStore extends AdaptiveStore {
  final records = <CheckInRecord>[];

  /// Check-ins accepted, new or in place of the last.
  var accepts = 0;

  @override
  Future<List<CheckInRecord>> history() async => records;

  @override
  Future<void> addCheckIn(CheckInRecord record) async {
    accepts++;
    records.add(record);
  }

  @override
  Future<void> replaceLastCheckIn(CheckInRecord record) async {
    accepts++;
    records[records.length - 1] = record;
  }
}


class _UnreadableActivity extends Fake implements ActivityCounter {
  @override
  Future<Map<DateTime, double>> daily({
    required DateTime first,
    required DateTime today,
    required AdaptiveSettings settings,
    required UserEntity user,
    double? bodyFatPercent,
    bool readHealth = true,
  }) async => throw StateError('The steps grant is gone');
}
