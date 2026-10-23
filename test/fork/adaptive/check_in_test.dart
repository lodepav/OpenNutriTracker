import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:opennutritracker/core/domain/entity/tracked_day_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_entity.dart';
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
import 'package:opennutritracker/fork/adaptive/trend_points.dart';

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
  @override
  Future<UserEntity> getUserData() async => _user();
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
    CheckIn run({double previous = 2000}) => computeCheckIn(
      CheckInInputs(
        days: [
          for (var d = 0; d < 60; d++)
            AdaptiveDay(intakeKcal: 2000, weightKg: 90 - 0.5 * d / 7),
        ],
        priorKcal: 2500,
        goalRateKgPerWeek: -0.5,
        bodyFatPercent: 25,
        targetWeightKg: 80,
        previousTargetKcal: previous,
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

    test('a check-in moves the target at most 200 kcal', () {
      expect(run(previous: 1500).proposedTargetKcal, 1700);
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
      // Upstream's formula target is above what this user burns, so the
      // first check-in moves the most it may down from it.
      expect(
        checkIn.proposedTargetKcal,
        greaterThan(checkIn.uncappedTargetKcal),
      );
      expect(checkIn.uncappedTargetKcal, lessThan(checkIn.expenditureKcal));
    });

    test(
      'the accepted target is the goal only while the switch is on',
      () async {
        final checkIn = await service.checkIn();
        await service.accept(checkIn, 2100);

        expect(await adaptiveTargetKcal(), isNull);
        expect(await adaptiveTargetKcal(store), isNull);
        await store.save(const AdaptiveSettings(adaptiveTarget: true));
        expect(await adaptiveTargetKcal(store), 2100);
      },
    );

    test('another profile answers with its own switch and target', () async {
      await store.save(const AdaptiveSettings(adaptiveTarget: true));
      await service.accept(await service.checkIn(), 2100);
      final other = AdaptiveStore(() => Hive.openBox<dynamic>('other'));

      expect(await adaptiveTargetKcal(other), isNull);
      await other.save(const AdaptiveSettings(adaptiveTarget: true));
      expect(await adaptiveTargetKcal(other), isNull);
      expect(await adaptiveTargetKcal(store), 2100);
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

  test('the chart gets a smoothed point a day only when chosen', () async {
    final entries = await _Weights().getAllEntries();
    expect(smoothedTrendPoints(entries), isNull);

    AdaptiveStore.settings.value = const AdaptiveSettings(smoothedTrend: true);
    final points = smoothedTrendPoints(entries)!;

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
    await tester.tap(find.text('Weekly check-in'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Accept'));
    await tester.pumpAndSettle();

    expect(refreshed, 1);
    expect(find.text('Weekly check-in'), findsNothing);
    expect(memory.records, hasLength(1));
  });
}

/// Hive's file I/O does not finish in a widget test's fake time.
class _MemoryStore extends AdaptiveStore {
  final records = <CheckInRecord>[];

  @override
  Future<List<CheckInRecord>> history() async => records;

  @override
  Future<void> addCheckIn(CheckInRecord record) async => records.add(record);
}
