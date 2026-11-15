import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/utils/tracked_day_lock.dart';
import 'package:opennutritracker/fork/add/logged_bar.dart';
import 'package:opennutritracker/fork/bulk/bulk_log_undo.dart';
import 'package:opennutritracker/fork/bulk/photo_meal_memory.dart';
import 'package:opennutritracker/fork/bulk/photo_meal_memory_store.dart';
import 'package:opennutritracker/fork/copy/copy_entries.dart';
import 'package:opennutritracker/fork/leftovers/meal_groups.dart';

final _undoLogged = undoLogged;

/// Throws on use: only its id is read here.
class _Intake implements IntakeEntity {
  @override
  final String id;

  _Intake(this.id);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late Directory dir;
  late Box<Map> groupBox;
  late Box<dynamic> memoryBox;
  late MealGroupStore groups;
  late PhotoMealMemoryStore memory;
  // the diary's entries, which the swapped undo takes back
  late Set<String> diary;

  final loggedAt = DateTime(2026, 11, 15, 12, 30);
  final record = PhotoMealRecord(
    day: DateTime(2026, 11, 15),
    loggedAt: loggedAt,
    slot: 'lunch',
    foods: const [
      PhotoMealFood(key: 'rice', name: 'Rice', amount: 200, kcal: 260),
      PhotoMealFood(key: 'egg', name: 'Egg', amount: 50, kcal: 70),
    ],
    kcal: 330,
    corrected: false,
  );
  final Placed placed = (
    day: DateTime(2026, 11, 15),
    written: [_Intake('a'), _Intake('b')],
  );

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('bulk_log_undo');
    Hive.init(dir.path);
    groupBox = await Hive.openBox<Map>('groups');
    memoryBox = await Hive.openBox<dynamic>('memory');
    groups = MealGroupStore(() async => groupBox);
    memory = PhotoMealMemoryStore(() async => memoryBox);
    diary = {'a', 'b', 'other'};
    // the real undo's profile check, over the diary above
    undoLogged = (placed, {required startedOn}) async =>
        await withTrackedDayLockOnProfile(() async {
          diary.removeAll(placed.written.map((i) => i.id));
          return true;
        }, startedOn: startedOn) ??
        false;
  });

  tearDown(() async {
    undoLogged = _undoLogged;
    await Hive.deleteFromDisk();
    await dir.delete(recursive: true);
  });

  /// What one Log wrote: the entries, a group with its kept photo, and the
  /// memory record.
  Future<File> logged() async {
    final photo = File('${dir.path}/photo.webp')..writeAsBytesSync([1, 2]);
    await groups.record(['a', 'b'], loggedAt, photo.path);
    await groups.record(['c', 'd'], loggedAt);
    await memory.add(record, now: loggedAt);
    return photo;
  }

  Future<bool?> takeBack(ProfileStamp stamp) => takeBackLogged(
    placed,
    startedOn: stamp,
    alsoUndo: () => forgetBulkLog(
      intakeIds: ['a', 'b'],
      memory: record,
      memoryStore: memory,
      groups: groups,
    ),
  );

  test('Undo takes back the entries, the meal group with its photo and the '
      'memory record', () async {
    final photo = await logged();

    expect(await takeBack(ProfileStamp.now()), isTrue);

    expect(diary, {'other'});
    expect(await groups.groupOf('a'), isNull);
    expect(await groups.groupOf('b'), isNull);
    expect(photo.existsSync(), isFalse);
    expect(await memory.records(now: loggedAt), isEmpty);
    // another meal's group stays
    expect((await groups.groupOf('c'))?.intakeIds, ['c', 'd']);
  });

  test('after a profile switch nothing is undone', () async {
    final photo = await logged();
    final stamp = ProfileStamp.now();
    await withProfileSwitchLock(() async {});

    expect(await takeBack(stamp), isNull);

    expect(diary, {'a', 'b', 'other'});
    expect((await groups.groupOf('a'))?.photoPath, photo.path);
    expect(photo.existsSync(), isTrue);
    expect(await memory.records(now: loggedAt), hasLength(1));
  });

  test('a group that cannot be forgotten is reported, not hidden', () async {
    await logged();
    final broken = MealGroupStore(() async => throw StateError('closed'));

    final undone = await takeBackLogged(
      placed,
      startedOn: ProfileStamp.now(),
      alsoUndo: () => forgetBulkLog(
        intakeIds: ['a', 'b'],
        memory: record,
        memoryStore: memory,
        groups: broken,
      ),
    );

    expect(undone, isFalse);
    expect(diary, {'other'});
    // the memory record still goes
    expect(await memory.records(now: loggedAt), isEmpty);
  });

  test('a Log with no memory record leaves the memory alone', () async {
    await logged();
    expect(
      await forgetBulkLog(
        intakeIds: ['a', 'b'],
        memoryStore: memory,
        groups: groups,
      ),
      isTrue,
    );
    expect(await memory.records(now: loggedAt), hasLength(1));
  });
}
