import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/fork/body/body_card.dart';
import 'package:opennutritracker/fork/body/measurement_store.dart';
import 'package:opennutritracker/fork/photos/photo_card.dart';
import 'package:opennutritracker/fork/photos/photo_store.dart';

class _Measurements extends Fake implements MeasurementStore {
  final entries = <Measurement>[];

  @override
  Future<List<Measurement>> all() async => [...entries];
}

class _Photos extends PhotoStore {
  @override
  Future<List<ProgressPhoto>> all() async => [];

  @override
  Future<File> file(ProgressPhoto photo) async => File(photo.relativePath);
}

Future<void> _pump(WidgetTester tester, Widget card) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: card)),
    ),
  );
  await tester.pumpAndSettle();
}

BodyMeasurementsCard _body(MeasurementStore store) => BodyMeasurementsCard(
  rangeDays: 30,
  palette: AppPalette.light,
  imperial: false,
  store: store,
);

void main() {
  testWidgets('Trends card titles are headings TalkBack can jump to', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    for (final (title, card) in [
      ('Body measurements', _body(_Measurements())),
      ('Progress photos', ProgressPhotosCard(store: _Photos())),
    ]) {
      await _pump(tester, card);
      final data = tester.getSemantics(find.text(title)).getSemanticsData();
      expect(data.label, title);
      expect(data.flagsCollection.isHeader, isTrue, reason: title);
    }
    semantics.dispose();
  });

  testWidgets('a body measurement date reads as a date, not ISO', (
    tester,
  ) async {
    final store = _Measurements()
      ..entries.add(
        Measurement(
          id: 'w',
          date: DateTime(2026, 11, 18),
          metric: BodyMetric.waist,
          value: 80,
        ),
      );
    await _pump(tester, _body(store));
    await tester.tap(find.text('Waist'));
    await tester.pumpAndSettle();

    expect(find.textContaining('2026-11-18'), findsNothing);
    expect(find.text('Latest (Nov 18, 2026)'), findsOneWidget);
  });
}
