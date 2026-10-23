import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:opennutritracker/fork/body/measurement_store.dart';
import 'package:opennutritracker/fork/health/body_fat_import.dart';

void main() {
  late Directory dir;
  late _Source source;
  late DateTime now;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('body_fat_import');
    Hive.init(dir.path);
    source = _Source();
    now = DateTime(2026, 10, 23, 12);
  });

  tearDown(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  Future<Box<dynamic>> box() => Hive.openBox<dynamic>('fork');
  BodyFatImport import() => BodyFatImport(source, box: box, clock: () => now);
  final store = MeasurementStore(box);

  Future<Map<String, double>> fat() async => {
    for (final m in await store.all())
      if (m.metric == BodyMetric.bodyFat)
        '${m.date.month}-${m.date.day}': m.value,
  };

  test('off until turned on; then each day keeps its latest reading', () async {
    source.readings = [
      HealthBodyFat('a', DateTime(2026, 10, 22, 7), 21.5),
      HealthBodyFat('b', DateTime(2026, 10, 22, 21), 21.9),
      HealthBodyFat('c', DateTime(2026, 10, 23, 7), 21.2),
    ];
    final importer = import();
    expect(await importer.runIfDue(), 0);
    expect(await fat(), isEmpty);

    expect(await importer.turnOn(), 2);
    expect(await fat(), {'10-22': 21.9, '10-23': 21.2});
    expect(await importer.isOn(), isTrue);
  });

  test('a refused permission leaves it off', () async {
    source.granted = false;
    expect(await import().turnOn(), isNull);
    expect(await import().isOn(), isFalse);
  });

  test('a value the user entered is never replaced', () async {
    await store.addDay(DateTime(2026, 10, 22), {
      BodyMetric.bodyFat: 19,
      BodyMetric.waist: 84,
    });
    source.readings = [HealthBodyFat('a', DateTime(2026, 10, 22, 7), 21.5)];
    expect(await import().turnOn(), 0);
    expect(await fat(), {'10-22': 19});
  });

  test('a newer reading replaces an imported one; a deleted day stays empty '
      'until a newer reading', () async {
    final importer = import();
    source.readings = [HealthBodyFat('a', DateTime(2026, 10, 22, 7), 21.5)];
    await importer.turnOn();

    now = now.add(const Duration(hours: 1));
    source.readings = [
      ...source.readings,
      HealthBodyFat('b', DateTime(2026, 10, 22, 20), 21.0),
    ];
    expect(await importer.runNow(), 1);
    expect(await fat(), {'10-22': 21.0});

    final row = (await store.all()).single;
    await store.remove(row.id);
    now = now.add(const Duration(hours: 1));
    expect(await importer.runNow(), 0);
    expect(await fat(), isEmpty);

    source.readings = [
      ...source.readings,
      HealthBodyFat('c', DateTime(2026, 10, 22, 22), 20.8),
    ];
    expect(await importer.runNow(), 1);
    expect(await fat(), {'10-22': 20.8});
  });

  test('runs at most every interval', () async {
    final importer = import();
    await importer.turnOn();
    source.readings = [HealthBodyFat('a', DateTime(2026, 10, 23, 7), 21.5)];
    expect(await importer.runIfDue(), 0);
    now = now.add(BodyFatImport.interval);
    expect(await importer.runIfDue(), 1);
  });

  test('a fraction is a percentage; an impossible value is dropped', () {
    expect(HealthStoreBodyFat.asPercent(0.215), closeTo(21.5, 1e-9));
    expect(HealthStoreBodyFat.asPercent(21.5), 21.5);
    expect(HealthStoreBodyFat.asPercent(90), isNull);
    expect(HealthStoreBodyFat.asPercent(0.01), isNull);
  });
}

class _Source implements BodyFatSource {
  bool granted = true;
  List<HealthBodyFat> readings = [];

  @override
  Future<bool> requestPermission() async => granted;

  @override
  Future<List<HealthBodyFat>> read(DateTime from, DateTime to) async => [
    for (final r in readings)
      if (!r.measuredAt.isBefore(from) && !r.measuredAt.isAfter(to)) r,
  ];
}
