import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/fork/dev/fake_health.dart';
import 'package:opennutritracker/fork/health/nutrition_export.dart';

IntakeEntity _intake(
  String id,
  DateTime at, {
  double amount = 150,
  IntakeTypeEntity type = IntakeTypeEntity.breakfast,
  String code = 'oats',
}) => IntakeEntity(
  id: id,
  unit: 'g',
  amount: amount,
  type: type,
  meal: MealEntity(
    code: code,
    name: 'Oats',
    url: null,
    mealQuantity: null,
    mealUnit: 'g',
    servingQuantity: null,
    servingUnit: 'g',
    servingSize: null,
    nutriments: const MealNutrimentsEntity(
      energyKcal100: 380,
      carbohydrates100: 60,
      fat100: 7,
      proteins100: 13,
      sugars100: null,
      saturatedFat100: null,
      fiber100: 10,
      sodium100: 6,
    ),
    source: MealSourceEntity.custom,
  ),
  dateTime: at,
);

void main() {
  late Directory dir;
  late _Sink sink;
  late List<IntakeEntity> diary;
  late DateTime now;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('nutrition_export');
    Hive.init(dir.path);
    sink = _Sink();
    diary = [];
    now = DateTime(2026, 10, 23, 20);
  });

  tearDown(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  NutritionExport export() => NutritionExport(
    sink,
    intakes: (since) async => [
      for (final i in diary)
        if (!i.dateTime.isBefore(since)) i,
    ],
    box: () => Hive.openBox<dynamic>('fork'),
    clock: () => now,
  );

  test('a record carries the entry\'s calories and grams', () {
    final r = NutritionRecord.of(_intake('a', DateTime(2026, 10, 23, 8)));
    expect(r.clientId, 'openbite-a');
    expect(r.kcal, closeTo(570, 1e-9));
    expect(r.carbs, closeTo(90, 1e-9));
    expect(r.protein, closeTo(19.5, 1e-9));
    expect(r.fat, closeTo(10.5, 1e-9));
    expect(r.fiber, closeTo(15, 1e-9));
    expect(r.sodium, closeTo(0.009, 1e-12));
    expect(r.sugar, isNull);
  });

  test('a date-only entry goes out at noon of its date', () {
    expect(
      NutritionRecord.of(_intake('a', DateTime.utc(2026, 10, 22))).at,
      DateTime(2026, 10, 22, 12),
    );
  });

  test('an imported day is not written', () async {
    diary = [
      _intake('a', DateTime(2026, 10, 23, 8)),
      _intake(
        'history-2026-10-22-day',
        DateTime(2026, 10, 22, 12),
        code: 'history-2026-10-22-day',
      ),
    ];
    expect(await export().turnOn(), 1);
    expect(sink.records.keys, {'openbite-a'});
  });

  test('off until turned on; then the window is written once', () async {
    diary = [
      _intake('a', DateTime(2026, 10, 23, 8)),
      _intake('b', DateTime(2026, 10, 22, 13), type: IntakeTypeEntity.lunch),
      _intake('old', DateTime(2026, 9, 1)),
    ];
    final e = export();
    expect(await e.runIfOn(), 0);
    expect(sink.records, isEmpty);

    expect(await e.turnOn(), 2);
    expect(sink.records.keys, {'openbite-a', 'openbite-b'});
    expect(await e.runNow(), 0);
    expect(sink.writes, 2);
  });

  test('an edit is written again over its record, at a higher version; a '
      'delete removes it', () async {
    diary = [_intake('a', DateTime(2026, 10, 23, 8))];
    final e = export();
    await e.turnOn();
    final first = sink.versions['openbite-a']!;

    now = now.add(const Duration(minutes: 5));
    diary = [_intake('a', DateTime(2026, 10, 23, 9), amount: 200)];
    expect(await e.runNow(), 1);
    expect(sink.records['openbite-a']!.kcal, closeTo(760, 1e-9));
    expect(sink.records['openbite-a']!.at, DateTime(2026, 10, 23, 9));
    expect(sink.versions['openbite-a']!, greaterThan(first));

    diary = [];
    expect(await e.runNow(), 1);
    expect(sink.records, isEmpty);
  });

  test('the window is cut on the time a record goes out at', () async {
    // The store hands over a day early, for a date-only entry west of UTC.
    final e = NutritionExport(
      sink,
      intakes: (since) async => diary,
      box: () => Hive.openBox<dynamic>('fork'),
      clock: () => now,
    );
    diary = [
      _intake('a', DateTime(2026, 10, 9, 8)),
      _intake('before', DateTime(2026, 10, 8, 23)),
    ];
    expect(await e.turnOn(), 1);
    expect(sink.records.keys, ['openbite-a']);
  });

  test('an entry ageing out of the window is forgotten, not deleted', () async {
    diary = [_intake('a', DateTime(2026, 10, 10, 8))];
    final e = export();
    await e.turnOn();
    now = DateTime(2026, 10, 30, 20);
    expect(await e.runNow(), 0);
    expect(sink.records.keys, ['openbite-a']);
  });

  test('a failure keeps what went out, and the rest goes next time', () async {
    diary = [
      _intake('a', DateTime(2026, 10, 23, 8)),
      _intake('b', DateTime(2026, 10, 23, 9)),
    ];
    final e = export();
    sink.failOn = 'openbite-b';
    await expectLater(e.turnOn(), throwsStateError);
    expect(sink.writes, 1);

    sink.failOn = null;
    expect(await e.runIfOn(), 1);
    expect(sink.records.keys, {'openbite-a', 'openbite-b'});
  });

  test('a refused permission leaves it off', () async {
    sink.granted = false;
    expect(await export().turnOn(), isNull);
    expect(await export().isOn(), isFalse);
  });
}

class _Sink extends FakeNutrition {
  bool granted = true;
  String? failOn;
  var writes = 0;
  final versions = <String, int>{};

  @override
  Future<bool> requestPermission() async => granted;

  @override
  Future<void> write(NutritionRecord record, int version) async {
    if (record.clientId == failOn) throw StateError('refused');
    writes++;
    versions[record.clientId] = version;
    await super.write(record, version);
  }
}
