import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/body_weight_unit_entity.dart';
import 'package:opennutritracker/core/domain/entity/tracked_day_entity.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/fork/body/body_card.dart';
import 'package:opennutritracker/fork/body/measurement_store.dart';
import 'package:opennutritracker/fork/goal/goal_card.dart';
import 'package:opennutritracker/fork/health/steps.dart';
import 'package:opennutritracker/fork/phases/phases.dart' show GoalRecord;
import 'package:opennutritracker/fork/health/steps_card.dart';
import 'package:opennutritracker/fork/photos/photo_card.dart';
import 'package:opennutritracker/fork/photos/photo_store.dart';
import 'package:opennutritracker/fork/report/trends_layout.dart';
import 'package:opennutritracker/fork/report/weekly_report.dart';
import 'package:opennutritracker/generated/l10n.dart';

class _Measurements extends Fake implements MeasurementStore {
  final entries = <Measurement>[];

  @override
  Future<List<Measurement>> all() async => [...entries];
}

class _Steps extends Fake implements StepCounts {
  @override
  Future<bool> isOn() async => false;

  @override
  Future<int> goal() async => 10000;
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
      // The goal card names the weight unit as the app does.
      localizationsDelegates: const [S.delegate],
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
    final today = DateTime(2026, 11, 18, 12);
    // by the ids of the page's cards, so a new card fails here until added
    final cards = <String, Widget>{
      'weekly': WeeklyReportCard(
        days: [
          TrackedDayEntity(
            day: DateTime(2026, 11, 17),
            calorieGoal: 2000,
            caloriesTracked: 1800,
          ),
        ],
        rangeDays: 7,
        palette: AppPalette.light,
        clock: () => today,
      ),
      'goalPlan': GoalCard(
        unit: BodyWeightUnit.kg,
        load: () async => (
          progress: null,
          nowKg: null,
          plan: null,
          history: const <GoalRecord>[],
          pace: null,
        ),
      ),
      'body': _body(_Measurements()),
      'steps': StepsCard(
        rangeDays: 7,
        palette: AppPalette.light,
        steps: _Steps(),
        clock: () => today,
      ),
      'photos': ProgressPhotosCard(store: _Photos()),
    };
    expect(cards.keys.toSet(), trendCards.keys.toSet());
    for (final MapEntry(key: id, value: card) in cards.entries) {
      final title = trendCards[id]!;
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
