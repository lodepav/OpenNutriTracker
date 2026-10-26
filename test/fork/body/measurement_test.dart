import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/fork/body/body_card.dart';
import 'package:opennutritracker/fork/body/measurement_store.dart';

final _today = DateTime(2026, 10, 23);

void main() {
  group('store', () {
    late Directory dir;
    late MeasurementStore store;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('measure');
      Hive.init(dir.path);
      store = MeasurementStore(() => Hive.openBox<dynamic>('measure'));
    });

    tearDown(() async {
      await Hive.close();
      await dir.delete(recursive: true);
    });

    test('a second entry on a day replaces that metric only', () async {
      await store.addDay(_today, {BodyMetric.waist: 90, BodyMetric.hips: 100});
      await store.addDay(_today.add(const Duration(hours: 20)), {
        BodyMetric.waist: 89,
      });

      final all = await store.all();
      expect(
        {for (final m in all) m.metric: m.value},
        {BodyMetric.waist: 89, BodyMetric.hips: 100},
      );

      await store.remove(all.first.id);
      await store.merge(all);
      expect(await store.all(), hasLength(2));
    });

    test('body fat counts for the estimate for 90 days', () async {
      await store.addDay(_today.subtract(const Duration(days: 100)), {
        BodyMetric.bodyFat: 30,
      });
      expect(await store.recentBodyFat(_today), isNull);

      await store.addDay(_today.subtract(const Duration(days: 10)), {
        BodyMetric.bodyFat: 22,
      });
      expect(await store.recentBodyFat(_today), 22);
    });

    test('an arm or thigh stored before they had sides is the right one', () {
      Measurement read(String metric) => Measurement.fromJson({
        'id': '1',
        'date': '2026-10-23T00:00:00.000',
        'metric': metric,
        'value': 32,
      });
      expect(read('arm').metric, BodyMetric.rightArm);
      expect(read('thigh').metric, BodyMetric.rightThigh);
      expect(read('leftArm').metric, BodyMetric.leftArm);
    });
  });

  testWidgets('the card adds a day of measurements, inches stored as cm', (
    tester,
  ) async {
    final memory = _Memory();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: BodyMeasurementsCard(
              rangeDays: 30,
              palette: AppPalette.light,
              imperial: true,
              store: memory,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('add a measurement'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('measure-add')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('measure-waist')), '32');
    await tester.enterText(find.byKey(const ValueKey('measure-bodyFat')), '18');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(memory.saved[BodyMetric.waist], closeTo(81.28, 1e-9));
    expect(memory.saved[BodyMetric.bodyFat], 18);
    expect(find.text('18.0 %'), findsOneWidget);
    await tester.tap(find.text('Waist'));
    await tester.pumpAndSettle();
    expect(find.text('32.0 in'), findsOneWidget);
  });

  testWidgets('a deleted measurement comes back with Undo', (tester) async {
    final memory = _Memory()
      ..entries.add(
        Measurement(
          id: 'w',
          date: DateTime.now(),
          metric: BodyMetric.waist,
          value: 80,
        ),
      );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: BodyMeasurementsCard(
              rangeDays: 30,
              palette: AppPalette.light,
              imperial: false,
              store: memory,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Waist'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Waist entries'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('measure-delete-w')));
    await tester.pumpAndSettle();
    expect(memory.entries, isEmpty);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(memory.entries.single.value, 80);
  });

  testWidgets('a value out of range is refused', (tester) async {
    final memory = _Memory();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: BodyMeasurementsCard(
              rangeDays: 30,
              palette: AppPalette.light,
              imperial: false,
              store: memory,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('measure-add')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('measure-bodyFat')), '95');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Body fat is not a measurement.'), findsOneWidget);
    expect(memory.saved, isEmpty);
  });
}

class _Memory extends Fake implements MeasurementStore {
  final saved = <BodyMetric, double>{};
  final entries = <Measurement>[];

  @override
  Future<List<Measurement>> all() async => [...entries];

  @override
  Future<void> addDay(DateTime date, Map<BodyMetric, double> values) async {
    saved.addAll(values);
    for (final e in values.entries) {
      entries.add(
        Measurement(id: e.key.name, date: date, metric: e.key, value: e.value),
      );
    }
    MeasurementStore.changes.value++;
  }

  @override
  Future<void> remove(String id) async {
    entries.removeWhere((m) => m.id == id);
    MeasurementStore.changes.value++;
  }

  @override
  Future<void> merge(List<Measurement> measurements) async {
    entries.addAll(measurements);
    MeasurementStore.changes.value++;
  }
}
