import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:opennutritracker/core/domain/entity/body_weight_unit_entity.dart';
import 'package:opennutritracker/core/utils/tracked_day_lock.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_service.dart';
import 'package:opennutritracker/fork/adaptive/goal_plan.dart';
import 'package:opennutritracker/fork/goal/goal_actions.dart';
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

/// A trend weight of 90.4 kg today, once [read] completes (at once by
/// default).
class _Trend extends Fake implements AdaptiveService {
  final Future<void>? read;

  _Trend([this.read]);

  @override
  Future<GoalPlanInputs?> goalPlan({int pastDays = 60}) async {
    await read;
    return const GoalPlanInputs(
      pastTrendKg: [91, 90.4],
      trendKgPerDay: -0.05,
      expenditureKcal: 2500,
      bodyFatPercent: 25,
      targetWeightKg: 80,
      paceKgPerWeek: -0.5,
    );
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

      expect((await store.plan())?.toJson(), next.toJson());
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
    Future<void> pump(
      WidgetTester tester,
      _MemoryPhases store, {
      AdaptiveService? service,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: DietPhasesCard(
                store: store,
                clock: () => DateTime(2026, 10, 27, 10),
                unit: BodyWeightUnit.kg,
                service: service,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('shows the running phase and what follows', (tester) async {
      await pump(tester, _MemoryPhases(_plan));

      expect(find.text('Now: Cut, 2 weeks at -0.50 kg a week'), findsOneWidget);
      expect(find.text('Week 2 of 2, until Nov 2, 2026'), findsOneWidget);
      expect(
        find.text('Nov 2, 2026: Maintenance, 1 week at maintenance'),
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
      expect(
        find.text('Now: Cut, 11 weeks at -0.50 kg a week'),
        findsOneWidget,
      );
    });

    testWidgets('a phase until a weight: weeks from the pace', (tester) async {
      final store = _MemoryPhases();
      await pump(tester, store, service: _Trend());
      Future<void> tap(String key) async {
        await tester.ensureVisible(find.byKey(ValueKey(key)));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(ValueKey(key)));
        await tester.pumpAndSettle();
      }

      String ends(int i) =>
          tester.widget<Text>(find.byKey(ValueKey('phase-$i-ends'))).data!;

      await tap('phases-edit');
      // 12 weeks at -0.5 from 90.4.
      expect(ends(0), 'Ends about Jan 19, 2027, ~84.4 kg');
      await tap('phase-0-until');
      expect(find.text('Until 84.5 kg: about 12 weeks'), findsOneWidget);
      await tap('phase-0-lighter');
      await tap('phase-0-lighter');
      expect(find.text('Until 83.5 kg: about 14 weeks'), findsOneWidget);
      // It says the weight once: it ends at the one it names.
      expect(ends(0), 'Ends about Feb 2, 2027');

      // A later phase to a weight starts where this one ends.
      await tap('phase-0-for-time');
      await tap('phases-add');
      await tap('phase-1-cut');
      await tap('phase-1-until');
      // From ~83.4 after 14 weeks: to 82.5, two weeks.
      expect(find.text('Until 82.5 kg: about 2 weeks'), findsOneWidget);
      await tap('phase-0-shorter');
      // A week less before it: half a kilo more to lose.
      expect(find.text('Until 82.5 kg: about 3 weeks'), findsOneWidget);
      expect(ends(1), 'Ends about Feb 16, 2027');

      await tap('phases-save');
      final plan = store.saved!;
      expect(plan.startKg, 90.4);
      expect(
        [for (final p in plan.phases) (p.weeks, p.untilKg)],
        [(13, null), (3, 82.5)],
      );
      expect(
        find.text(
          'Jan 26, 2027: Cut to 82.5 kg, about 3 weeks at -0.50 kg a week',
        ),
        findsOneWidget,
      );
    });

    testWidgets('a cut at its heaviest says why + is greyed', (tester) async {
      final store = _MemoryPhases();
      await pump(tester, store, service: _Trend());
      Future<void> tap(String key) async {
        await tester.ensureVisible(find.byKey(ValueKey(key)));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(ValueKey(key)));
        await tester.pumpAndSettle();
      }

      await tap('phases-edit');
      await tap('phase-0-until');
      final limit = find.byKey(const ValueKey('phase-0-limit'));
      expect(limit, findsNothing);
      final heavier = find.byKey(const ValueKey('phase-0-heavier'));
      for (
        var n = 0;
        n < 30 && tester.widget<IconButton>(heavier).onPressed != null;
        n++
      ) {
        await tap('phase-0-heavier');
      }
      expect(tester.widget<IconButton>(heavier).onPressed, isNull);
      expect(
        tester.widget<Text>(limit).data,
        'A cut ends below your trend weight (90.4 kg).',
      );
    });

    testWidgets('the editor opens before the trend is read', (tester) async {
      final read = Completer<void>();
      await pump(tester, _MemoryPhases(), service: _Trend(read.future));
      await tester.tap(find.byKey(const ValueKey('phases-edit')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('phase-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('phase-0-until')), findsNothing);

      read.complete();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('phase-0-until')), findsOneWidget);
    });

    testWidgets('a plan saved before the trend is read keeps its weight', (
      tester,
    ) async {
      final read = Completer<void>();
      final store = _MemoryPhases();
      await pump(tester, store, service: _Trend(read.future));
      await tester.tap(find.byKey(const ValueKey('phases-edit')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('phases-save')));
      await tester.pumpAndSettle();
      expect(store.saved, isNull); // waiting on the read

      read.complete();
      await tester.pumpAndSettle();
      expect(store.saved?.startKg, 90.4);
    });

    testWidgets('a phase earlier ones get past runs by time', (tester) async {
      await pump(tester, _MemoryPhases(), service: _Trend());
      Future<void> tap(String key) async {
        await tester.ensureVisible(find.byKey(ValueKey(key)));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(ValueKey(key)));
        await tester.pumpAndSettle();
      }

      await tap('phases-edit');
      await tap('phases-add');
      await tap('phase-1-cut');
      await tap('phase-1-until');
      // From ~84.4 after 12 weeks: to 83.5.
      expect(find.text('Until 83.5 kg: about 2 weeks'), findsOneWidget);
      await tap('phase-0-longer');
      await tap('phase-0-longer');
      // A week left after the first, then the first ends at ~83.4, past it:
      // a week by time.
      expect(
        tester
            .widget<ChoiceChip>(find.byKey(const ValueKey('phase-1-for-time')))
            .selected,
        isTrue,
      );
      expect(find.text('1 week'), findsOneWidget);
    });

    testWidgets('a first target is past the start, the pace\'s way', (
      tester,
    ) async {
      await pump(tester, _MemoryPhases(), service: _Trend());
      await tester.tap(find.byKey(const ValueKey('phases-edit')));
      await tester.pumpAndSettle();
      for (var i = 0; i < 11; i++) {
        await tester.tap(find.byKey(const ValueKey('phase-0-shorter')));
        await tester.pump();
      }
      // The slowest pace: a week at -0.1 from 90.4 rounds to 90.5, above;
      // the next step under it is 90.0.
      await tester.drag(
        find.byKey(const ValueKey('phase-0-pace')),
        const Offset(-1000, 0),
      );
      await tester.pumpAndSettle();
      expect(find.text('Pace -0.10 kg a week'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('phase-0-until')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Until 90.0 kg'), findsOneWidget);
    });

    testWidgets('a phase to a weight past 52 weeks says where it ends', (
      tester,
    ) async {
      await pump(
        tester,
        _MemoryPhases(
          PhasePlan(
            start: _start,
            startKg: 90,
            phases: const [
              DietPhase(
                kind: PhaseKind.cut,
                kgPerWeek: -0.5,
                weeks: 52,
                untilKg: 60,
              ),
            ],
          ),
        ),
      );
      expect(
        find.text(
          'Now: Cut toward 60.0 kg, 52 weeks (the longest a phase runs) '
          'at -0.50 kg a week',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('~64.0 kg'), findsOneWidget);
    });

    testWidgets('without a weight, phases are by time only', (tester) async {
      await pump(tester, _MemoryPhases());
      await tester.tap(find.byKey(const ValueKey('phases-edit')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('phase-0-until')), findsNothing);
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('phase-0-ends'))).data,
        'Ends Jan 19, 2027',
      );
    });

    testWidgets('a plan is deleted', (tester) async {
      final store = _MemoryPhases(_plan);
      await pump(tester, store);

      await tester.tap(find.byKey(const ValueKey('phases-edit')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('phases-delete')));
      await tester.pumpAndSettle();
      // Asked first: cancelled, the plan stays.
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('phases-save')), findsOneWidget);
      expect(store.saved, isNotNull);

      await tester.tap(find.byKey(const ValueKey('phases-delete')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('phases-confirm')));
      await tester.pumpAndSettle();

      expect(store.saved, isNull);
      expect(find.text('Plan'), findsOneWidget);
    });

    testWidgets('back asks before changes are lost', (tester) async {
      final store = _MemoryPhases(_plan);
      await pump(tester, store);
      final save = find.byKey(const ValueKey('phases-save'));

      // Nothing changed: back just leaves.
      await tester.tap(find.byKey(const ValueKey('phases-edit')));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(save, findsNothing);

      await tester.tap(find.byKey(const ValueKey('phases-edit')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('phase-0-longer')));
      await tester.pump();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Discard your changes?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(save, findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('phases-confirm')));
      await tester.pumpAndSettle();
      expect(save, findsNothing);
      expect(store.saved!.phases.first.weeks, _plan.phases.first.weeks);
    });

    testWidgets('the steppers and the pace are named', (tester) async {
      await pump(tester, _MemoryPhases(_plan));
      await tester.tap(find.byKey(const ValueKey('phases-edit')));
      await tester.pumpAndSettle();

      Finder tip(String key) => find.descendant(
        of: find.byKey(ValueKey(key)),
        matching: find.byType(Tooltip),
      );
      expect(tester.widget<Tooltip>(tip('phase-0-shorter')).message, 'Shorter');
      expect(tester.widget<Tooltip>(tip('phase-0-longer')).message, 'Longer');
      final pace = tester.widget<Slider>(
        find.byKey(const ValueKey('phase-0-pace')),
      );
      expect(pace.semanticFormatterCallback!(0.5), 'Pace, -0.50 kg a week');
    });
  });
}
