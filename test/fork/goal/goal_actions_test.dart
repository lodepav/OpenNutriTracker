import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/utils/tracked_day_lock.dart';
import 'package:opennutritracker/fork/goal/goal_actions.dart';
import 'package:opennutritracker/fork/goal/goal_planner.dart';
import 'package:opennutritracker/fork/phases/phases.dart';

final _plan = GoalDraft(
  kind: PhaseKind.cut,
  startKg: 86.4,
  targetKg: 80,
  start: DateTime(2026, 10, 5),
).toPlan();

/// The phase store in memory, logging its writes to [log].
class _LoggedPhases extends PhaseStore {
  final List<String> log;
  PhasePlan? saved;

  _LoggedPhases(this.log);

  @override
  Future<void> save(PhasePlan? plan) async {
    saved = plan;
    log.add('plan');
  }

  @override
  Future<void> addToHistory(List<GoalRecord> records) async =>
      log.add('history');
}

void main() {
  test('a profile switch after the actions were made drops them', () async {
    final log = <String>[];
    final store = _LoggedPhases(log);
    final actions = GoalActions(
      store: store,
      save: (_, _) async {
        log.add('profile');
        return true;
      },
      clock: () => DateTime(2026, 10, 6),
    );
    await withProfileSwitchLock(() async {});

    expect(await actions.start(_plan), isFalse);
    expect(await actions.complete(_plan, 80), isFalse);
    expect(await actions.extend(_plan), isFalse);
    expect(log, isEmpty);
  });

  test('a profile switch waits for the plan and the history', () async {
    final log = <String>[];
    Future<void>? switching;
    final actions = GoalActions(
      store: _LoggedPhases(log),
      save: (_, _) async {
        log.add('profile');
        // The switch starts while the pace is being saved, from outside
        // the lock's zone, as a tap would.
        switching = Zone.root.run(
          () => withProfileSwitchLock(() async => log.add('switch')),
        );
        return true;
      },
      clock: () => DateTime(2026, 10, 6),
    );

    expect(await actions.start(_plan, replacing: _plan, nowKg: 84), isTrue);
    await switching;
    expect(log, ['profile', 'history', 'plan', 'switch']);
  });
}
