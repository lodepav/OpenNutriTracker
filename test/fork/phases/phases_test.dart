import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:opennutritracker/core/utils/tracked_day_lock.dart';
import 'package:opennutritracker/fork/phases/phases.dart';
import 'package:opennutritracker/fork/phases/phases_ui.dart';

// Monday 19 October 2026; the clocks change on the 25th.
final _start = DateTime(2026, 10, 19);

final _plan = PhasePlan(
  start: _start,
  phases: const [
    DietPhase(kind: PhaseKind.cut, kgPerWeek: -0.5, weeks: 2),
    DietPhase(kind: PhaseKind.maintain, kgPerWeek: 0, weeks: 1),
    DietPhase(kind: PhaseKind.bulk, kgPerWeek: 0.25, weeks: 3),
  ],
);

/// In memory, as real Hive hangs under `testWidgets`.
class _MemoryPhases extends PhaseStore {
  PhasePlan? saved;

  _MemoryPhases([this.saved]);

  @override
  Future<PhasePlan?> plan() async => saved;

  @override
  Future<void> save(PhasePlan? plan) async {
    saved = plan;
    PhaseStore.changes.value++;
  }
}

void main() {
  group('the plan', () {
    test('phases follow each other by calendar day', () {
      expect(_plan.startOf(1), DateTime(2026, 11, 2));
      expect(_plan.startOf(2), DateTime(2026, 11, 9));
      expect(_plan.end, DateTime(2026, 11, 30));
    });

    test('the pace of a day: none before, maintenance after', () {
      expect(_plan.paceOn(DateTime(2026, 10, 18, 23)), isNull);
      expect(_plan.paceOn(DateTime(2026, 10, 25, 12)), -0.5);
      expect(_plan.indexOn(DateTime(2026, 11, 1, 23, 59)), 0);
      expect(_plan.paceOn(DateTime(2026, 11, 2)), 0);
      expect(_plan.paceOn(DateTime(2026, 11, 9)), 0.25);
      expect(_plan.paceOn(DateTime(2026, 12, 1)), 0);
      expect(_plan.indexOn(DateTime(2026, 12, 1)), 3);
    });

    test('round-trips, and a phase of no weeks is refused', () {
      expect(PhasePlan.fromJson(_plan.toJson()).toJson(), _plan.toJson());
      expect(
        () => DietPhase.fromJson({'kind': 'cut', 'kgPerWeek': -1, 'weeks': 0}),
        throwsFormatException,
      );
    });
  });

  group('the runner', () {
    late Directory dir;
    late PhaseStore store;
    late List<double> paces;
    var now = DateTime(2026, 10, 20, 9);

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('phases');
      Hive.init(dir.path);
      store = PhaseStore(() => Hive.openBox<dynamic>('phases'));
      paces = [];
      now = DateTime(2026, 10, 20, 9);
    });

    tearDown(() async {
      await Hive.close();
      await dir.delete(recursive: true);
    });

    var saves = true;
    PhaseRunner runner() => PhaseRunner(
      store: store,
      setPace: (kg, startedOn) async {
        paces.add(kg);
        return saves && startedOn.isCurrent;
      },
      clock: () => now,
    );

    test('a pace a profile switch dropped is tried again', () async {
      await store.save(_plan);
      saves = false;
      expect(await runner().run(), isFalse);
      saves = true;
      expect(await runner().run(), isTrue);
      expect(paces, [-0.5, -0.5]);
    });

    test('a profile switch while the plan is read sets no pace', () async {
      await store.save(_plan);
      var switched = false;
      final switching = PhaseStore(() async {
        // The switch lands as the run reads the plan.
        if (!switched) {
          switched = true;
          await withProfileSwitchLock(() async {});
        }
        return Hive.openBox<dynamic>('phases');
      });
      final run = PhaseRunner(
        store: switching,
        setPace: (kg, startedOn) async => startedOn.isCurrent,
        clock: () => now,
      );

      expect(await run.run(), isFalse);
      expect(await store.applied(), isNull);
    });

    test('a phase sets its pace once, as it begins', () async {
      expect(await runner().run(), isFalse);
      await store.save(_plan);

      expect(await runner().run(), isTrue);
      // A pace changed by hand meanwhile stands until the next phase.
      expect(await runner().run(), isFalse);
      now = DateTime(2026, 11, 3, 8);
      await runner().run();
      now = DateTime(2026, 12, 2);
      await runner().run();

      expect(paces, [-0.5, 0, 0]);
    });

    test('saving the plan applies its phase afresh', () async {
      await store.save(_plan);
      await runner().run();
      await store.save(_plan);
      await runner().run();
      expect(paces, [-0.5, -0.5]);
    });

    test('before the start the profile keeps its pace', () async {
      now = DateTime(2026, 10, 1);
      await store.save(_plan);
      expect(await runner().run(), isFalse);
      expect(paces, isEmpty);
    });

    test('a profile switch runs it once the switch is through', () async {
      final stamps = <bool>[];
      await withProfileSwitchLock(() async {
        PhaseRunner.afterSwitch(() => stamps.add(ProfileStamp.now().isCurrent));
        await Future<void>.delayed(Duration.zero);
        expect(stamps, isEmpty);
      });
      await Future<void>.delayed(Duration.zero);
      expect(stamps, [isTrue]);
    });
  });

  group('the card', () {
    Future<void> pump(WidgetTester tester, _MemoryPhases store) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: DietPhasesCard(
                store: store,
                clock: () => DateTime(2026, 10, 27, 10),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('shows the running phase and what follows', (tester) async {
      await pump(tester, _MemoryPhases(_plan));

      expect(find.text('Now: Cut, 2 weeks -0.50 kg a week'), findsOneWidget);
      expect(find.text('Week 2 of 2, until 2026-11-02'), findsOneWidget);
      expect(
        find.text('2026-11-02: Maintenance, 1 week at maintenance'),
        findsOneWidget,
      );
    });

    testWidgets('a plan is built: a cut, then a diet break', (tester) async {
      final store = _MemoryPhases();
      await pump(tester, store);

      await tester.tap(find.byKey(const ValueKey('phases-edit')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('phase-0')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('phase-0-shorter')));
      await tester.tap(find.byKey(const ValueKey('phases-add')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('phases-save')));
      await tester.pumpAndSettle();

      final plan = store.saved!;
      expect(plan.start, DateTime(2026, 10, 27));
      expect(
        [for (final p in plan.phases) (p.kind, p.kgPerWeek, p.weeks)],
        [(PhaseKind.cut, -0.5, 11), (PhaseKind.maintain, 0, 2)],
      );
      expect(find.text('Now: Cut, 11 weeks -0.50 kg a week'), findsOneWidget);
    });

    testWidgets('a plan is deleted', (tester) async {
      final store = _MemoryPhases(_plan);
      await pump(tester, store);

      await tester.tap(find.byKey(const ValueKey('phases-edit')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('phases-delete')));
      await tester.pumpAndSettle();

      expect(store.saved, isNull);
      expect(find.text('Plan'), findsOneWidget);
    });
  });
}
