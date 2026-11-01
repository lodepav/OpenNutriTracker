import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:opennutritracker/core/utils/tracked_day_lock.dart';
import 'package:opennutritracker/fork/goal/goal_actions.dart';
import 'package:opennutritracker/fork/phases/phases.dart';

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

    test('weights: each phase moves it, one to a weight stops there', () {
      final plan = PhasePlan(
        start: _start,
        startKg: 90,
        phases: const [
          DietPhase(kind: PhaseKind.cut, kgPerWeek: -0.5, weeks: 2),
          DietPhase(
            kind: PhaseKind.cut,
            kgPerWeek: -0.5,
            weeks: 5,
            untilKg: 87,
          ),
          DietPhase(kind: PhaseKind.bulk, kgPerWeek: 0.25, weeks: 4),
        ],
      );
      expect(plan.weightAt(0), 90);
      expect(plan.weightAt(1), 89);
      expect(plan.weightAt(2), 87); // not 86.5: it stops at 87
      expect(plan.weightAt(3), 88);
      expect(_plan.weightAt(1), isNull); // a plan with no weights
      expect(DietPhase.weeksTo(89, 87, -0.5), 4);
      expect(DietPhase.weeksTo(89, 86.9, -0.5), 5); // rounded up
      expect(DietPhase.weeksTo(89, 91, -0.5), 1); // the wrong way
      expect(DietPhase.weeksTo(89, 40, -0.5), 52);

      final copy = PhasePlan.fromJson(jsonDecode(jsonEncode(plan.toJson())));
      expect(copy.startKg, 90);
      expect(copy.phases[1].untilKg, 87);
      expect(copy.phases[0].untilKg, isNull);
      expect(_plan.toJson().containsKey('startKg'), isFalse);
      expect(PhasePlan.fromJson(_plan.toJson()).startKg, isNull);
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

    test('completed goals of one start day are both kept', () async {
      GoalRecord goal(DateTime end, double endKg) => GoalRecord(
        kind: PhaseKind.cut,
        start: DateTime(2026, 10, 20),
        end: end,
        startKg: 80,
        endKg: endKg,
      );
      await store.addToHistory([goal(DateTime(2026, 10, 20), 80)]);
      await store.addToHistory([goal(DateTime(2026, 12, 1), 76)]);
      // A backup restored again replaces its own goal.
      await store.addToHistory([goal(DateTime(2026, 12, 1), 75.5)]);

      expect((await store.history()).map((r) => r.endKg), [80, 75.5]);
    });

    test('the upcoming goals are kept in order, and cleared', () async {
      await store.saveUpcoming([_plan, _plan]);
      expect((await store.upcoming()).map((p) => p.start), [
        _plan.start,
        _plan.start,
      ]);
      await store.saveUpcoming([]);
      expect(await store.upcoming(), isEmpty);
    });

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

    test('a queued goal starts on its day, the one before kept', () async {
      // _plan runs 6 weeks from Oct 19, to Nov 30.
      final next = PhasePlan(
        start: DateTime(2026, 11, 30),
        startKg: 80,
        phases: const [
          DietPhase(kind: PhaseKind.cut, kgPerWeek: -0.75, weeks: 4),
        ],
      );
      await store.save(_plan);
      await store.saveUpcoming([next]);
      final profile = <(double?, double?)>[];
      PhaseRunner run() => PhaseRunner(
        store: store,
        setPace: (kg, startedOn) async {
          paces.add(kg);
          return true;
        },
        clock: () => now,
        startNext: (store, startedOn) => GoalActions(
          store: store,
          startedOn: startedOn,
          save: (pace, target) async {
            profile.add((pace, target));
            return true;
          },
          clock: () => now,
        ).startNextIfDue(80.4),
      );

      now = DateTime(2026, 11, 29, 9);
      await run().run();
      expect((await store.plan())?.start, _start);
      now = DateTime(2026, 11, 30, 9);
      await run().run();

      // As planned, from the weight it really begins at.
      expect((await store.plan())?.toJson(), {
        ...next.toJson(),
        'startKg': 80.4,
      });
      expect(await store.upcoming(), isEmpty);
      final kept = (await store.history()).single;
      expect(
        (kept.start, kept.end, kept.endKg),
        (_start, DateTime(2026, 11, 30), 80.4),
      );
      expect(profile, [(-0.75, null)]);
      expect(paces.last, -0.75);
    });

    test(
      'a run while a goal is completed waits, and sets no old pace',
      () async {
        // Just saved, so its phase is not applied yet.
        await store.save(_plan);
        var profile = -0.5;
        final runner = PhaseRunner(
          store: store,
          setPace: (kg, startedOn) async {
            profile = kg;
            return true;
          },
          clock: () => now,
        );
        Future<bool>? run;
        final actions = GoalActions(
          store: store,
          save: (pace, target) async {
            if (pace != null) profile = pace;
            // A change notice lands while the goal is being saved.
            run = runner.run();
            return true;
          },
          clock: () => now,
        );

        expect(await actions.complete(_plan, 80), isTrue);
        expect(await run, isFalse);
        expect(profile, 0);
      },
    );

    group('the goal notice', () {
      late double goal;
      PhaseRunner noticing() => PhaseRunner(
        store: store,
        setPace: (kg, startedOn) async {
          goal = 2500 + kg * 1000;
          return true;
        },
        homeGoal: () async => goal,
        clock: () => now,
      );

      setUp(() => goal = 2500);
      tearDown(() => PhaseStore.goalNotice.value = null);

      test('says the goal moved the day a phase comes due', () async {
        await store.save(_plan);
        await noticing().run();
        expect(await store.savedGoalNotice(), isNull);

        now = DateTime(2026, 11, 3, 9);
        final phase = _plan.indexOn(now);
        expect(phase, greaterThan(0));
        await noticing().run();

        expect(PhaseStore.goalNotice.value, (
          title: 'New phase: ${_plan.phases[phase].kind.label}',
          fromKcal: 2000.0,
          toKcal: 2500 + _plan.phases[phase].kgPerWeek * 1000,
        ));
      });

      test('a plan the user just saved is no news', () async {
        await store.save(_plan);
        await noticing().run();
        await store.save(_plan);
        goal = 2400;
        await noticing().run();
        expect(PhaseStore.goalNotice.value, isNull);
      });

      test('nothing when a target sets the goal', () async {
        await store.save(_plan);
        await noticing().run();
        now = DateTime(2026, 11, 3, 9);
        await PhaseRunner(
          store: store,
          setPace: (kg, startedOn) async => true,
          homeGoal: () async => null,
          clock: () => now,
        ).run();
        expect(PhaseStore.goalNotice.value, isNull);
      });

      test('it stays until dismissed, across runs', () async {
        await store.save(_plan);
        await noticing().run();
        now = DateTime(2026, 11, 3, 9);
        await noticing().run();
        PhaseStore.goalNotice.value = null;

        await noticing().run();
        expect(PhaseStore.goalNotice.value, isNotNull);

        await store.dismissGoalNotice();
        await noticing().run();
        expect(PhaseStore.goalNotice.value, isNull);
      });

      test('a goal unread cannot stop the phase', () async {
        await store.save(_plan);
        final run = PhaseRunner(
          store: store,
          setPace: (kg, startedOn) async => true,
          homeGoal: () async => throw StateError('no goal'),
          clock: () => now,
        );
        expect(await run.run(), isTrue);
      });
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
}
