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
import 'package:opennutritracker/fork/adaptive/auto_check_in.dart';

final _today = DateTime(2026, 10, 22);

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

/// 60 days of losing 0.5 kg a week, weighed every other day.
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

class _MemoryStore extends AdaptiveStore {
  final records = <CheckInRecord>[];
  final keys = <String, Object?>{};

  @override
  Future<List<CheckInRecord>> history() async => records;

  @override
  Future<void> addCheckIn(CheckInRecord record) async => records.add(record);

  @override
  Future<void> restoreCheckIns(List<CheckInRecord> records) async =>
      this.records
        ..clear()
        ..addAll(records);

  @override
  Future<Object?> readKey(String key) async => keys[key];

  @override
  Future<void> writeKey(String key, Object? value) async => keys[key] = value;
}

void main() {
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
    AutoCheckIn.accepted.value = null;
    AutoCheckIn.waiting.value = null;
  });

  test('accepts a due check-in once and publishes it, with why', () async {
    AdaptiveStore.settings.value = const AdaptiveSettings(
      adaptiveTarget: true,
      autoAcceptCheckIn: true,
    );

    await AutoCheckIn.run(service);

    expect(store.records, hasLength(1));
    final accepted = AutoCheckIn.accepted.value!;
    expect(accepted.reason, CheckInReason.first);
    expect(
      store.records.single.acceptedKcal,
      accepted.checkIn.proposedTargetKcal,
    );

    await AutoCheckIn.run(service);
    expect(store.records, hasLength(1));
  });

  test(
    'an undone check-in is left to the card until the next is due',
    () async {
      AdaptiveStore.settings.value = const AdaptiveSettings(
        adaptiveTarget: true,
        autoAcceptCheckIn: true,
      );
      final before = await service.checkIns();
      await AutoCheckIn.run(service);
      expect(store.records, hasLength(1));

      await service.restoreCheckIns(before);
      AutoCheckIn.accepted.value = null;
      await AutoCheckIn.run(service);
      expect(store.records, isEmpty);
      expect(AutoCheckIn.accepted.value, isNull);
      expect(await service.checkInDue(), isTrue);

      // A week on, the next check-in is due and goes ahead on its own.
      final later = AdaptiveService(
        _User(),
        _Weights(),
        _TrackedDays(),
        store,
        () => _today.add(const Duration(days: 7, hours: 9)),
      );
      await AutoCheckIn.run(later);
      expect(store.records, hasLength(1));
    },
  );

  test('an Undo holds while its record is the last and no new check-in is '
      'due', () {
    final on = DateTime(2026, 11, 21);
    bool holds(DateTime today, {String lastNow = 'a', int? weekday}) =>
        undoHolds(
          today: today,
          undoneOn: on,
          undoneAfter: 'a',
          lastNow: lastNow,
          weekday: weekday,
        );
    expect(holds(on), isTrue);
    expect(holds(DateTime(2026, 11, 27)), isTrue);
    expect(holds(DateTime(2026, 11, 28)), isFalse);
    // answered by hand since
    expect(holds(on, lastNow: 'b'), isFalse);
    // Nov 21 2026 is a Saturday; check-ins on Mondays come due Nov 23.
    expect(holds(DateTime(2026, 11, 22), weekday: DateTime.monday), isTrue);
    expect(holds(DateTime(2026, 11, 23), weekday: DateTime.monday), isFalse);
  });

  test('does nothing with automatic check-ins off', () async {
    AdaptiveStore.settings.value = const AdaptiveSettings(adaptiveTarget: true);

    await AutoCheckIn.run(service);

    expect(store.records, isEmpty);
    expect(AutoCheckIn.accepted.value, isNull);
  });

  test('switched off, no check-in is said to wait', () async {
    AutoCheckIn.waiting.value = (service: service, since: _today);
    AdaptiveStore.settings.value = const AdaptiveSettings(adaptiveTarget: true);

    await AutoCheckIn.run(service);

    expect(AutoCheckIn.waiting.value, isNull);
  });

  test('two callers at once accept it once', () async {
    AdaptiveStore.settings.value = const AdaptiveSettings(
      adaptiveTarget: true,
      autoAcceptCheckIn: true,
    );

    await Future.wait([AutoCheckIn.run(service), AutoCheckIn.run(service)]);

    expect(store.records, hasLength(1));
  });
}
