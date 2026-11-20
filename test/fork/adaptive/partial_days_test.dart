import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
import 'package:opennutritracker/fork/adaptive/auto_check_in.dart';
import 'package:opennutritracker/fork/adaptive/expenditure.dart';
import 'package:opennutritracker/fork/adaptive/partial_days.dart';

final _today = DateTime(2026, 10, 22);

/// The day [_TrackedDays] logs at half, five days back.
final _halfDay = DateTime(2026, 10, 17);

class _User extends Fake implements GetUserUsecase {
  @override
  Future<UserEntity> getUserData() async => UserEntity(
    birthday: DateTime(1990, 1, 1),
    heightCM: 180,
    weightKG: 90,
    gender: UserGenderEntity.male,
    goal: UserWeightGoalEntity.loseWeight,
    pal: UserPALEntity.active,
    weeklyWeightGoalKg: -0.5,
    targetWeightKg: 80,
  );
}

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

/// 60 days at 2,000 kcal, [_halfDay] at 1,000 and today, still being
/// eaten, at 400.
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
        caloriesTracked: d == 0
            ? 400
            : d == 5
            ? 1000
            : 2000,
      ),
  ];
}

class _MemoryStore extends AdaptiveStore {
  final records = <CheckInRecord>[];

  @override
  Future<List<CheckInRecord>> history() async => records;

  @override
  Future<void> addCheckIn(CheckInRecord record) async => records.add(record);

  @override
  Future<void> setSkipped(DateTime day, bool skipped) async =>
      AdaptiveStore.skipped.value = {...AdaptiveStore.skipped.value, day};

  @override
  Future<void> setWhole(DateTime day, bool isWhole) async =>
      AdaptiveStore.whole.value = {...AdaptiveStore.whole.value, day};
}

/// [n] days at [kcal], with [others] by index in their place.
List<AdaptiveDay> _days(
  int n, {
  double kcal = 2000,
  Map<int, double?> others = const {},
}) => [
  for (var i = 0; i < n; i++)
    AdaptiveDay(intakeKcal: others.containsKey(i) ? others[i] : kcal),
];

void main() {
  group('likelyPartlyLogged', () {
    test('a day at half the usual is found, with the usual', () {
      final found = likelyPartlyLogged(_days(30, others: {12: 1000}));
      expect(found.map((f) => f.day), [12]);
      expect(found.single.usualKcal, 2000);
    });

    test('a light day at 65% is not', () {
      expect(likelyPartlyLogged(_days(30, others: {12: 1300})), isEmpty);
    });

    test('the usual is the median: a feast does not hide a half day', () {
      final found = likelyPartlyLogged(
        _days(30, others: {10: 6000, 11: 6000, 12: 1100}),
      );
      expect(found.map((f) => f.day), [12]);
    });

    test('needs a week of other logged days around it', () {
      expect(likelyPartlyLogged(_days(7, others: {3: 900})), isEmpty);
      expect(likelyPartlyLogged(_days(8, others: {3: 900})), hasLength(1));
    });

    test('a day not logged is already left out', () {
      expect(
        likelyPartlyLogged(_days(30, others: {12: null, 13: 150})),
        isEmpty,
      );
    });

    test('low days as a habit, two fasting days a week, are not slips', () {
      final fasting = _days(
        42,
        others: {
          for (var i = 0; i < 42; i++)
            if (i % 7 == 1 || i % 7 == 4) i: 600.0,
        },
      );
      expect(likelyPartlyLogged(fasting), isEmpty);
    });

    test('the usual follows the days around, not the whole history', () {
      // A cut from 3,000 to 1,900: its days are not half days of the bulk.
      final days = [..._days(40, kcal: 3000), ..._days(40, kcal: 1700)];
      expect(likelyPartlyLogged(days), isEmpty);
    });
  });

  group('the check-in asks', () {
    late _MemoryStore store;
    late AdaptiveService service;

    setUp(() {
      store = _MemoryStore();
      service = AdaptiveService(
        _User(),
        _Weights(),
        _TrackedDays(),
        store,
        () => _today.add(const Duration(hours: 9)),
      );
    });

    tearDown(() {
      AdaptiveStore.settings.value = const AdaptiveSettings();
      AdaptiveStore.skipped.value = const {};
      AdaptiveStore.whole.value = const {};
      AutoCheckIn.accepted.value = null;
    });

    test('the half day is asked about; today, still eaten, is not', () async {
      final days = await service.partialDays();
      expect(days.map((d) => d.date), [_halfDay]);
      expect(days.single.kcal, 1000);
      expect(days.single.usualKcal, 2000);
    });

    test('a day kept or left out is not asked about again', () async {
      await service.keepDay(_halfDay);
      expect(await service.partialDays(), isEmpty);

      AdaptiveStore.whole.value = const {};
      await service.leaveOutDay(_halfDay);
      expect(await service.partialDays(), isEmpty);
    });

    test('leaving the day out raises the estimate', () async {
      final before = (await service.checkIn()).expenditureKcal;
      await service.leaveOutDay(_halfDay);
      expect((await service.checkIn()).expenditureKcal, greaterThan(before));
    });

    test('an automatic check-in waits for the answer', () async {
      AdaptiveStore.settings.value = const AdaptiveSettings(
        adaptiveTarget: true,
        autoAcceptCheckIn: true,
      );

      await AutoCheckIn.run(service);
      expect(store.records, isEmpty);

      await service.keepDay(_halfDay);
      await AutoCheckIn.run(service);
      expect(store.records, hasLength(1));
    });

    testWidgets('the screen shows the day and takes the answer', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 4000);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(home: CheckInScreen(service: service)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Logged only in part?'), findsOneWidget);
      expect(find.textContaining('usually about'), findsOneWidget);
      String field() => tester
          .widget<TextField>(find.byKey(const ValueKey('check-in-target')))
          .controller!
          .text;
      final before = field();

      await tester.tap(find.text('Leave out'));
      await tester.pumpAndSettle();

      expect(find.text('Logged only in part?'), findsNothing);
      expect(AdaptiveStore.skipped.value, {_halfDay});
      // The field follows the new proposal, not the one before the answer.
      final proposed = (await service.checkIn()).proposedTargetKcal.round();
      expect(field(), isNot(before));
      expect(field(), '$proposed');
    });
  });
}
