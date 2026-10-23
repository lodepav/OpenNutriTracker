import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:opennutritracker/core/data/repository/user_repository.dart';
import 'package:opennutritracker/core/data/repository/weight_log_repository.dart';
import 'package:opennutritracker/core/domain/entity/user_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_gender_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_pal_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_weight_goal_entity.dart';
import 'package:opennutritracker/core/domain/entity/weight_log_entity.dart';
import 'package:opennutritracker/core/utils/extensions.dart';
import 'package:opennutritracker/fork/health/weight_import.dart';

void main() {
  late Directory dir;
  late _Source source;
  late _Log log;
  late _User user;
  late DateTime now;
  DateTime? createdAt;
  var profile = 'a';

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('weight_import');
    Hive.init(dir.path);
    source = _Source();
    log = _Log();
    user = _User();
    now = DateTime(2026, 10, 23, 12);
    createdAt = DateTime(2026, 1, 1);
    profile = 'a';
  });

  tearDown(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  WeightImport import() => WeightImport(
    source,
    log,
    user,
    box: () => Hive.openBox<dynamic>(WeightImport.boxName),
    profile: () => profile,
    profileCreatedAt: () => createdAt,
    clock: () => now,
  );

  HealthWeight at(String id, DateTime when, double kg) =>
      HealthWeight(id, when, kg);

  test('off until turned on; then each day keeps its latest reading and the '
      'newest becomes the current weight', () async {
    source.readings = [
      at('a', DateTime(2026, 10, 22, 7), 80.4),
      at('b', DateTime(2026, 10, 22, 21), 80.9),
      at('c', DateTime(2026, 10, 23, 7), 80.1),
    ];
    final importer = import();
    expect(await importer.runIfDue(), 0);
    expect(log.rows, isEmpty);

    expect(await importer.turnOn(), 2);
    expect(log.kg('2026-10-22'), 80.9);
    expect(log.kg('2026-10-23'), 80.1);
    expect(user.entity.weightKG, 80.1);
  });

  test('a refused permission leaves it off', () async {
    source.granted = false;
    expect(await import().turnOn(), isNull);
    expect(await import().isOn(), isFalse);
  });

  test('a weight the user entered or edited is never replaced', () async {
    final importer = import();
    source.readings = [at('a', DateTime(2026, 10, 21, 7), 81)];
    log.put('2026-10-22', 79); // typed by the user
    await importer.turnOn();
    log.put('2026-10-21', 80.5); // the imported day, edited

    source.readings = [
      at('b', DateTime(2026, 10, 21, 20), 81.5),
      at('c', DateTime(2026, 10, 22, 20), 81.2),
    ];
    now = now.add(const Duration(hours: 1));
    expect(await importer.runNow(), 0);
    expect(log.kg('2026-10-21'), 80.5);
    expect(log.kg('2026-10-22'), 79);
    expect(user.entity.weightKG, 90, reason: 'the newest row is the user\'s');
  });

  test('a deleted day stays empty until a newer reading arrives', () async {
    final importer = import();
    source.readings = [at('b', DateTime(2026, 10, 22, 21), 80.9)];
    await importer.turnOn();
    log.rows.remove('2026-10-22');

    source.readings = [
      at('a', DateTime(2026, 10, 22, 7), 80.4),
      at('b', DateTime(2026, 10, 22, 21), 80.9),
    ];
    now = now.add(const Duration(hours: 1));
    expect(await importer.runNow(), 0);
    expect(log.rows, isEmpty);

    source.readings.add(at('c', DateTime(2026, 10, 22, 23), 80.7));
    expect(await importer.runNow(), 1);
    expect(log.kg('2026-10-22'), 80.7);
  });

  test('reads from the last run less the overlap, a month back at most, and '
      'not again within the interval', () async {
    final importer = import();
    await importer.turnOn();
    expect(source.from, DateTime(2026, 9, 22, 12));

    now = now.add(const Duration(minutes: 5));
    expect(await importer.runIfDue(), 0);
    expect(source.reads, 1);

    now = now.add(const Duration(hours: 1));
    await importer.runIfDue();
    expect(source.from, DateTime(2026, 10, 22, 12));
  });

  test('a reading from before the profile was made does not replace the '
      'onboarding weight', () async {
    createdAt = DateTime(2026, 10, 23, 9);
    source.readings = [at('a', DateTime(2026, 10, 23, 7), 80.1)];
    await import().turnOn();
    expect(log.kg('2026-10-23'), 80.1);
    expect(user.entity.weightKG, 90);
  });

  test('a profile switch during the read files nothing', () async {
    source.readings = [at('a', DateTime(2026, 10, 23, 7), 80.1)];
    source.onRead = () => profile = 'b';
    await import().turnOn();
    expect(log.rows, isEmpty);
  });
}

class _Source implements WeightSource {
  var readings = <HealthWeight>[];
  var granted = true;
  var reads = 0;
  DateTime? from;
  void Function()? onRead;

  @override
  Future<bool> requestPermission() async => granted;

  @override
  Future<List<HealthWeight>> read(DateTime from, DateTime to) async {
    reads++;
    this.from = from;
    onRead?.call();
    return [...readings];
  }
}

class _Log extends Fake implements WeightLogRepository {
  final rows = <String, WeightLogEntity>{};

  void put(String day, double kg) =>
      rows[day] = WeightLogEntity(date: DateTime.parse(day), weightKg: kg);

  double? kg(String day) => rows[day]?.weightKg;

  @override
  Future<void> addEntry(WeightLogEntity entry) async =>
      rows[entry.date.toParsedDay()] = entry;

  @override
  Future<WeightLogEntity?> getEntry(DateTime date) async =>
      rows[date.toParsedDay()];

  @override
  Future<List<WeightLogEntity>> getAllEntries() async => [...rows.values];
}

class _User extends Fake implements UserRepository {
  var entity = UserEntity(
    birthday: DateTime(1990, 1, 1),
    heightCM: 180,
    weightKG: 90,
    gender: UserGenderEntity.male,
    goal: UserWeightGoalEntity.loseWeight,
    pal: UserPALEntity.active,
  );

  @override
  Future<bool> hasUserData() async => true;

  @override
  Future<UserEntity> getUserData() async => entity;

  @override
  Future<void> updateUserData(UserEntity userEntity) async =>
      entity = userEntity;
}
