import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/fork/health/steps.dart';
import 'package:opennutritracker/fork/health/steps_card.dart';

/// 1,000 steps a day times the day of the month; counts the reads.
class _Source implements StepSource {
  final reads = <DateTime>[];
  var granted = true;
  var refused = false;

  @override
  Future<bool> requestPermission() async => granted;

  @override
  Future<int> stepsBetween(DateTime from, DateTime to) async {
    if (refused) throw StateError('No permission');
    reads.add(from);
    return from.day * 1000;
  }
}

/// In memory, as real Hive hangs under `testWidgets`.
class _MemorySteps extends StepCounts {
  final _Source source;
  bool on;
  int _goal = StepCounts.defaultGoal;
  Map<DateTime, int> days;

  _MemorySteps(this.source, {this.on = false, this.days = const {}})
    : super(source);

  @override
  Future<bool> isOn() async => on;

  @override
  Future<int> goal() async => _goal;

  @override
  Future<void> setGoal(int steps) async {
    _goal = steps;
    StepCounts.changes.value++;
  }

  @override
  Future<bool> turnOn() async {
    if (!await source.requestPermission()) return false;
    on = true;
    StepCounts.changes.value++;
    return true;
  }

  @override
  Future<void> turnOff() async {
    on = false;
    StepCounts.changes.value++;
  }

  @override
  Future<Map<DateTime, int>> daily(DateTime today, int count) async {
    if (source.refused) throw StateError('No permission');
    return days;
  }
}

final _now = DateTime(2026, 10, 23, 15);

void main() {
  group('counts', () {
    late Directory dir;
    late _Source source;
    late StepCounts steps;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('steps');
      Hive.init(dir.path);
      source = _Source();
      steps = StepCounts(source, () => Hive.openBox<dynamic>('steps'));
    });

    tearDown(() async {
      await Hive.close();
      await dir.delete(recursive: true);
    });

    test('off until the permission is granted', () async {
      expect(await steps.isOn(), isFalse);
      source.granted = false;
      expect(await steps.turnOn(), isFalse);
      expect(await steps.isOn(), isFalse);
      source.granted = true;
      expect(await steps.turnOn(), isTrue);
      expect(await steps.isOn(), isTrue);
    });

    test('reads the last 30 days once, then only the last two', () async {
      final week = await steps.daily(_now, 7);
      expect(week.keys, [for (var d = 17; d <= 23; d++) DateTime(2026, 10, d)]);
      expect(week[DateTime(2026, 10, 20)], 20000);
      expect(source.reads, hasLength(StepCounts.backfill));
      // Across the 25 October clock change, a day each.
      expect(source.reads.first, DateTime(2026, 9, 24));

      source.reads.clear();
      await steps.daily(_now, 7);
      expect(source.reads, [DateTime(2026, 10, 22), DateTime(2026, 10, 23)]);
    });

    test('days before the read reach are missing until cached', () async {
      final range = await steps.daily(_now, 90);
      expect(range.keys.first, DateTime(2026, 9, 24));
      expect(range, hasLength(30));
    });

    test('the goal is kept', () async {
      expect(await steps.goal(), StepCounts.defaultGoal);
      await steps.setGoal(10000);
      expect(await steps.goal(), 10000);
    });

    test('a refused read throws rather than reading as no steps', () async {
      source.refused = true;
      expect(steps.daily(_now, 7), throwsStateError);
    });
  });

  group('card', () {
    Future<void> pump(WidgetTester tester, _MemorySteps steps) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: StepsCard(
                rangeDays: 7,
                palette: AppPalette.light,
                steps: steps,
                clock: () => _now,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('connecting shows the days', (tester) async {
      final steps = _MemorySteps(
        _Source(),
        days: {
          DateTime(2026, 10, 21): 9000,
          DateTime(2026, 10, 22): 5000,
          DateTime(2026, 10, 23): 3000,
        },
      );
      await pump(tester, steps);
      expect(find.text('Today'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('steps-on')));
      await tester.pumpAndSettle();

      expect(find.text('3,000'), findsOneWidget);
      // Today stays out of the average and the goal count.
      expect(find.text('7,000'), findsOneWidget);
      expect(find.text('1 of 2'), findsOneWidget);
    });

    testWidgets('a refused permission stays off and says why', (tester) async {
      final steps = _MemorySteps(_Source()..granted = false);
      await pump(tester, steps);

      await tester.tap(find.byKey(const ValueKey('steps-on')));
      await tester.pumpAndSettle();

      expect(steps.on, isFalse);
      expect(
        find.text('Steps need the Health Connect permission.'),
        findsOneWidget,
      );
    });

    testWidgets('a refused read says so', (tester) async {
      await pump(tester, _MemorySteps(_Source()..refused = true, on: true));
      expect(find.textContaining('refused the read'), findsOneWidget);
    });

    testWidgets('the goal is edited', (tester) async {
      final steps = _MemorySteps(
        _Source(),
        on: true,
        days: {DateTime(2026, 10, 22): 9000},
      );
      await pump(tester, steps);
      expect(find.text('1 of 1'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('steps-goal')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('steps-goal-field')),
        '10000',
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('Goal 10,000'), findsOneWidget);
      expect(find.text('0 of 1'), findsOneWidget);
    });
  });
}
