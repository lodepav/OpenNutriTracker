import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import 'package:opennutritracker/core/domain/entity/user_gender_entity.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/fork/body/body_card.dart';
import 'package:opennutritracker/fork/body/measurement_store.dart';
import 'package:opennutritracker/fork/body/side_compare.dart';
import 'package:opennutritracker/fork/body/waist_ratio.dart';

import '../../helpers/ux_checks.dart';

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

  testWidgets("a picked metric's last entry gone, the card shows one left", (
    tester,
  ) async {
    final memory = _Memory()
      ..entries.addAll([
        Measurement(
          id: 'b',
          date: DateTime.now(),
          metric: BodyMetric.bodyFat,
          value: 20,
        ),
        Measurement(
          id: 'w',
          date: DateTime.now(),
          metric: BodyMetric.waist,
          value: 80,
        ),
      ]);
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

    expect(find.text('Waist entries'), findsNothing);
    expect(find.text('Body fat entries'), findsOneWidget);
  });

  testWidgets('saving over a day says what went, and Undo brings it back', (
    tester,
  ) async {
    final memory = _Memory()
      ..entries.add(
        Measurement(
          id: 'old',
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
    await tester.tap(find.byKey(const ValueKey('measure-add')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('measure-waist')), '75');
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Replaced waist 80.0 cm'), findsOneWidget);
    expect(memory.entries.single.value, 75);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(memory.entries.single.id, 'old');
    expect(memory.entries.single.value, 80);
  });

  test('addDay reports what it added and replaced', () async {
    Hive.init(Directory.systemTemp.createTempSync('m').path);
    final box = await Hive.openBox<dynamic>('addDay');
    addTearDown(box.deleteFromDisk);
    final store = MeasurementStore(() async => box);
    final day = DateTime(2026, 10, 25);
    await store.addDay(day, {BodyMetric.waist: 80});
    final saved = await store.addDay(day, {
      BodyMetric.waist: 75,
      BodyMetric.hips: 100,
    });
    expect(saved.replaced.single.value, 80);
    expect(saved.added.map((m) => m.value), [75, 100]);
    expect((await store.all()).length, 2);
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
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Enter a body fat between 2 and 70 %'), findsOneWidget);
    expect(memory.saved, isEmpty);
  });

  test('each field is checked against its own range, at the edges', () {
    String? check(BodyMetric m, String text, {bool imperial = false}) =>
        measurementError(m, text, imperial: imperial);
    expect(check(BodyMetric.bodyFat, ''), isNull);
    expect(check(BodyMetric.bodyFat, '2'), isNull);
    expect(check(BodyMetric.bodyFat, '70'), isNull);
    expect(check(BodyMetric.bodyFat, '69,9'), isNull);
    for (final bad in ['1.9', '70.1', 'abc', '-5']) {
      expect(
        check(BodyMetric.bodyFat, bad),
        'Enter a body fat between 2 and 70 %',
        reason: bad,
      );
    }
    // A dropped digit is refused: a 3 cm arm, a 9 cm waist.
    expect(
      check(BodyMetric.rightArm, '3'),
      'Enter a right arm between 15 and 70 cm',
    );
    expect(check(BodyMetric.waist, '9'), 'Enter a waist between 40 and 200 cm');
    expect(check(BodyMetric.waist, '40'), isNull);
    expect(check(BodyMetric.waist, '200'), isNull);
    expect(check(BodyMetric.waist, '200.1'), isNotNull);
    const cm = {
      BodyMetric.waist: (40, 200),
      BodyMetric.hips: (50, 200),
      BodyMetric.chest: (50, 200),
      BodyMetric.neck: (20, 60),
      BodyMetric.leftArm: (15, 70),
      BodyMetric.rightArm: (15, 70),
      BodyMetric.leftThigh: (30, 100),
      BodyMetric.rightThigh: (30, 100),
    };
    for (final MapEntry(key: m, value: (low, high)) in cm.entries) {
      expect(check(m, '$low'), isNull, reason: '$m $low');
      expect(check(m, '$high'), isNull, reason: '$m $high');
      expect(check(m, '${low - 1}'), isNotNull, reason: '$m below');
      expect(check(m, '${high + 1}'), isNotNull, reason: '$m above');
    }
    // Inches: whole ones inside the cm range, checked as worded.
    expect(
      check(BodyMetric.leftArm, '5', imperial: true),
      'Enter a left arm between 6 and 27 in',
    );
    expect(check(BodyMetric.leftArm, '6', imperial: true), isNull);
    expect(check(BodyMetric.leftArm, '27', imperial: true), isNull);
    expect(check(BodyMetric.leftArm, '28', imperial: true), isNotNull);
    expect(
      check(BodyMetric.hips, '10', imperial: true),
      'Enter hips between 20 and 78 in',
    );
  });

  Future<void> pumpCard(
    WidgetTester tester,
    _Memory memory, {
    int rangeDays = 30,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: BodyMeasurementsCard(
              rangeDays: rangeDays,
              palette: AppPalette.light,
              imperial: false,
              store: memory,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the dialog: units from the start, an error on each field, '
      'room between fields', (tester) async {
    await pumpCard(tester, _Memory());
    await tester.tap(find.byKey(const ValueKey('measure-add')));
    await tester.pumpAndSettle();

    // Nothing typed yet, the units show.
    for (final unit in ['%', 'cm']) {
      final opacity = tester.widget<AnimatedOpacity>(
        find.ancestor(
          of: find.text(unit).first,
          matching: find.byType(AnimatedOpacity),
        ),
      );
      expect(opacity.opacity, 1, reason: unit);
    }
    final fat = tester.getRect(find.byKey(const ValueKey('measure-bodyFat')));
    final waist = tester.getRect(find.byKey(const ValueKey('measure-waist')));
    expect(waist.top - fat.bottom, inInclusiveRange(8, 12));

    await tester.enterText(find.byKey(const ValueKey('measure-bodyFat')), '1');
    await tester.enterText(find.byKey(const ValueKey('measure-hips')), '500');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    InputDecoration decoration(String key) => tester
        .widget<TextField>(find.byKey(ValueKey('measure-$key')))
        .decoration!;
    expect(
      decoration('bodyFat').errorText,
      'Enter a body fat between 2 and 70 %',
    );
    expect(decoration('hips').errorText, 'Enter hips between 50 and 200 cm');
    expect(decoration('waist').errorText, isNull);
    // The first refused field takes the focus, so it scrolls into view.
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('measure-bodyFat')))
          .focusNode!
          .hasFocus,
      isTrue,
    );

    // Typed again, its error goes before any Save; the other stays.
    await tester.enterText(find.byKey(const ValueKey('measure-hips')), '5');
    await tester.pump();
    expect(decoration('hips').errorText, isNull);
    expect(decoration('bodyFat').errorText, isNotNull);

    // Corrected, the day saves.
    await tester.enterText(find.byKey(const ValueKey('measure-bodyFat')), '');
    await tester.enterText(find.byKey(const ValueKey('measure-hips')), '90');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('measure-bodyFat')), findsNothing);
  });

  testWidgets('the dialog: a labelled date to edit, Next between fields, '
      'Save off until a value is typed', (tester) async {
    await pumpCard(tester, _Memory());
    await tester.tap(find.byKey(const ValueKey('measure-add')));
    await tester.pumpAndSettle();

    final date = find.byKey(const ValueKey('measure-date'));
    expect(find.descendant(of: date, matching: find.text('Date')), findsOne);
    expect(
      find.descendant(of: date, matching: find.byIcon(Icons.edit_outlined)),
      findsOne,
    );

    TextInputAction? action(BodyMetric m) => tester
        .widget<TextField>(find.byKey(ValueKey('measure-${m.name}')))
        .textInputAction;
    for (final m in BodyMetric.values) {
      expect(
        action(m),
        m == BodyMetric.values.last
            ? TextInputAction.done
            : TextInputAction.next,
        reason: m.name,
      );
    }

    TextButton save() =>
        tester.widget<TextButton>(find.widgetWithText(TextButton, 'Save'));
    expect(save().onPressed, isNull);
    await tester.enterText(find.byKey(const ValueKey('measure-waist')), '80');
    await tester.pump();
    expect(save().onPressed, isNotNull);
    await tester.enterText(find.byKey(const ValueKey('measure-waist')), ' ');
    await tester.pump();
    expect(save().onPressed, isNull);
  });

  testWidgets('the chart states its ends and the range, with a true minus', (
    tester,
  ) async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day - 5);
    final end = DateTime(now.year, now.month, now.day);
    final memory = _Memory()
      ..entries.addAll([
        Measurement(
          id: 'a',
          date: start,
          metric: BodyMetric.bodyFat,
          value: 22.5,
        ),
        Measurement(
          id: 'b',
          date: end,
          metric: BodyMetric.bodyFat,
          value: 21.8,
        ),
      ]);
    await pumpCard(tester, memory, rangeDays: 7);

    expect(find.text('Change, last 7 days'), findsOneWidget);
    // Body fat's change is in percentage points, not a relative %.
    expect(find.text('\u22120.7 pts'), findsOneWidget);
    expect(
      find.text(
        '22.5 % on ${DateFormat.MMMd().format(start)} \u2192 '
        '21.8 % on ${DateFormat.MMMd().format(end)}',
      ),
      findsOneWidget,
    );
  });

  testWidgets("in the app's theme a floating label clears the field above", (
    tester,
  ) async {
    await pumpOnPhone(
      tester,
      BodyMeasurementsCard(
        rangeDays: 30,
        palette: AppPalette.light,
        imperial: false,
        store: _Memory(),
      ),
      textScale: 1,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('measure-add')));
    await tester.pumpAndSettle();
    final fat = tester.getRect(find.byKey(const ValueKey('measure-bodyFat')));
    final label = tester.getRect(
      find.descendant(
        of: find.byKey(const ValueKey('measure-waist')),
        matching: find.text('Waist'),
      ),
    );
    expect(label.top, greaterThanOrEqualTo(fat.bottom));
  });

  testWidgets('at 200% text the rows of metric chips keep apart', (
    tester,
  ) async {
    final memory = _Memory()
      ..entries.addAll([
        for (final m in BodyMetric.values)
          Measurement(id: m.name, date: DateTime.now(), metric: m, value: 30),
      ]);
    await pumpOnPhone(
      tester,
      SingleChildScrollView(
        child: BodyMeasurementsCard(
          rangeDays: 30,
          palette: AppPalette.light,
          imperial: false,
          store: memory,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final chips = find.byType(ChoiceChip);
    final rects = [
      for (var i = 0; i < chips.evaluate().length; i++)
        tester.getRect(chips.at(i)),
    ];
    final rows = {for (final r in rects) r.top}.toList()..sort();
    expect(rows.length, greaterThan(1));
    for (var i = 1; i < rows.length; i++) {
      final above = rects.where((r) => r.top == rows[i - 1]).first;
      expect(rows[i] - above.bottom, greaterThanOrEqualTo(8));
    }
  });

  group('links', () {
    final frame = loadBodyFrame;
    tearDown(() {
      loadBodyFrame = frame;
      SidePartPref.current.value = SidePart.arms;
    });

    Measurement m(BodyMetric metric, double value) => Measurement(
      id: metric.name,
      date: DateTime.now(),
      metric: metric,
      value: value,
    );

    testWidgets('none without the data for them', (tester) async {
      loadBodyFrame = () async => null;
      await pumpCard(
        tester,
        _Memory()
          ..entries.addAll([
            m(BodyMetric.waist, 90),
            m(BodyMetric.leftArm, 35),
          ]),
      );
      expect(find.byKey(const ValueKey('measure-waist-ratio')), findsNothing);
      expect(find.byKey(const ValueKey('measure-sides')), findsNothing);
    });

    testWidgets('a waist and a height open Waist to height', (tester) async {
      loadBodyFrame = () async =>
          (heightCm: 180.0, gender: UserGenderEntity.male);
      await pumpCard(tester, _Memory()..entries.add(m(BodyMetric.waist, 90)));
      expect(find.byKey(const ValueKey('measure-sides')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('measure-waist-ratio')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(WaistRatioPage), findsOneWidget);
    });

    testWidgets('both thighs open left and right on the thighs', (
      tester,
    ) async {
      loadBodyFrame = () async => null;
      await pumpCard(
        tester,
        _Memory()
          ..entries.addAll([
            m(BodyMetric.leftThigh, 58),
            m(BodyMetric.rightThigh, 59),
            m(BodyMetric.leftArm, 35),
          ]),
      );
      await tester.tap(find.byKey(const ValueKey('measure-sides')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(SideComparePage), findsOneWidget);
      expect(SidePartPref.current.value, SidePart.thighs);
    });

    testWidgets('the part picked on the page is kept when both have pairs', (
      tester,
    ) async {
      loadBodyFrame = () async => null;
      await pumpCard(
        tester,
        _Memory()
          ..entries.addAll([
            m(BodyMetric.leftThigh, 58),
            m(BodyMetric.rightThigh, 59),
            m(BodyMetric.leftArm, 35),
            m(BodyMetric.rightArm, 35.5),
          ]),
      );
      // Picked on the page since the card was built.
      SidePartPref.current.value = SidePart.thighs;
      await tester.tap(find.byKey(const ValueKey('measure-sides')));
      await tester.pump();
      expect(SidePartPref.current.value, SidePart.thighs);
    });
  });
}

class _Memory extends Fake implements MeasurementStore {
  final saved = <BodyMetric, double>{};
  final entries = <Measurement>[];

  @override
  Future<List<Measurement>> all() async => [...entries];

  @override
  Future<({List<Measurement> added, List<Measurement> replaced})> addDay(
    DateTime date,
    Map<BodyMetric, double> values,
  ) async {
    saved.addAll(values);
    final replaced = [
      for (final m in entries)
        if (values.containsKey(m.metric) && DateUtils.isSameDay(m.date, date))
          m,
    ];
    entries.removeWhere(replaced.contains);
    final added = [
      for (final e in values.entries)
        Measurement(id: e.key.name, date: date, metric: e.key, value: e.value),
    ];
    entries.addAll(added);
    MeasurementStore.changes.value++;
    return (added: added, replaced: replaced);
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
