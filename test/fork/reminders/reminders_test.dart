import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:opennutritracker/fork/adaptive/check_in.dart';
import 'package:opennutritracker/fork/reminders/reminders.dart';
import 'package:opennutritracker/fork/reminders/reminders_ui.dart';

class _Scheduler implements ReminderScheduler {
  final scheduled = <ReminderKind, PlannedReminder>{};
  final bodies = <ReminderKind, String?>{};
  var granted = true;

  @override
  Future<bool> requestPermission() async => granted;

  @override
  Future<void> schedule(PlannedReminder reminder, {String? body}) async {
    scheduled[reminder.kind] = reminder;
    bodies[reminder.kind] = body;
  }

  @override
  Future<void> cancel(ReminderKind kind) async => scheduled.remove(kind);
}

// Friday 23 October 2026, 08:00.
final _now = DateTime(2026, 10, 23, 8);
const _morning = (hour: 7, minute: 30);
const _nine = (hour: 9, minute: 0);

void main() {
  group('plan', () {
    List<PlannedReminder> plan({
      ReminderTime? weighIn,
      ReminderTime? checkIn,
      bool weighedToday = false,
      DateTime? due,
      DateTime? now,
    }) => planReminders(
      now: now ?? _now,
      weighIn: weighIn,
      checkIn: checkIn,
      weighedToday: weighedToday,
      checkInDueDay: due,
    );

    test('nothing is on by default', () {
      expect(plan(due: DateTime(2026, 10, 20)), isEmpty);
    });

    test('a weigh-in past today goes off tomorrow, daily', () {
      expect(plan(weighIn: _morning), [
        (
          kind: ReminderKind.weighIn,
          at: DateTime(2026, 10, 24, 7, 30),
          repeatsDaily: true,
        ),
      ]);
    });

    test('a weigh-in later today waits for tomorrow once weighed', () {
      final early = DateTime(2026, 10, 23, 6);
      expect(
        plan(weighIn: _morning, now: early).single.at,
        DateTime(2026, 10, 23, 7, 30),
      );
      expect(
        plan(weighIn: _morning, now: early, weighedToday: true).single.at,
        DateTime(2026, 10, 24, 7, 30),
      );
    });

    test('a check-in goes off once, on its day', () {
      expect(plan(checkIn: _nine, due: DateTime(2026, 10, 27)), [
        (
          kind: ReminderKind.checkIn,
          at: DateTime(2026, 10, 27, 9),
          repeatsDaily: false,
        ),
      ]);
    });

    test('a check-in already due goes off at the next time', () {
      expect(
        plan(checkIn: _nine, due: DateTime(2026, 10, 1)).single.at,
        DateTime(2026, 10, 23, 9),
      );
      expect(
        plan(
          checkIn: _nine,
          due: DateTime(2026, 10, 1),
          now: DateTime(2026, 10, 23, 10),
        ).single.at,
        DateTime(2026, 10, 24, 9),
      );
    });

    test('no check-in without the adaptive target', () {
      expect(plan(checkIn: _nine), isEmpty);
    });

    test('across the clock change the time of day holds', () {
      // 25 October 2026 ends summer time in Europe.
      expect(
        plan(checkIn: _nine, due: DateTime(2026, 10, 26)).single.at,
        DateTime(2026, 10, 26, 9),
      );
    });
  });

  group('check-in message', () {
    CheckIn checkIn({int logged = 6, double target = 2140}) => CheckIn(
      averageIntakeKcal: 2100,
      loggedDays: logged,
      weighIns: 5,
      trendKg: 80,
      weekChangeKg: -0.4,
      expenditureKcal: 2640.4,
      uncappedTargetKcal: target,
      proposedTargetKcal: target,
      daysToTargetAtGoal: null,
      daysToTargetAtTrend: null,
    );

    test('expenditure, the new target and its change', () {
      expect(
        checkInMessage(checkIn(), previousKcal: 2200),
        'Expenditure 2,640 kcal, new target 2,140 kcal, \u221260. '
        'Open OpenBite to confirm it.',
      );
      expect(
        checkInMessage(checkIn(target: 2250), previousKcal: 2200),
        startsWith('Expenditure 2,640 kcal, new target 2,250 kcal, +50.'),
      );
      expect(
        checkInMessage(checkIn(), previousKcal: 2140),
        contains('2,140 kcal, no change.'),
      );
    });

    test('the first check-in has no change; kilojoules when chosen', () {
      expect(
        checkInMessage(checkIn()),
        startsWith('Expenditure 2,640 kcal, new target 2,140 kcal. '),
      );
      expect(
        checkInMessage(checkIn(), previousKcal: 2200, kilojoules: true),
        startsWith('Expenditure 11,047 kJ, new target 8,954 kJ, \u2212251.'),
      );
    });

    test('too little data gives no result', () {
      expect(checkInMessage(checkIn(logged: 3), previousKcal: 2200), isNull);
    });
  });

  group('reminders', () {
    late Directory dir;
    late _Scheduler scheduler;
    var weighed = false;
    DateTime? due;
    String? Function() result = () => null;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('reminders');
      Hive.init(dir.path);
      scheduler = _Scheduler();
      weighed = false;
      due = DateTime(2026, 10, 27);
      result = () => null;
    });

    tearDown(() async {
      await Hive.close();
      await dir.delete(recursive: true);
    });

    Reminders reminders() => Reminders(
      scheduler: scheduler,
      box: () => Hive.openBox<dynamic>('reminders'),
      weighed: (_) async => weighed,
      checkInDueDay: () async => due,
      checkInResult: () async => result(),
      clock: () => _now,
    );

    test('the check-in tells its result; the weigh-in its own text; a failed '
        'estimate leaves the check-in its own', () async {
      result = () => 'Expenditure 2,640 kcal';
      final r = reminders();
      await r.set(ReminderKind.weighIn, _morning);
      await r.set(ReminderKind.checkIn, _nine);
      expect(scheduler.bodies, {
        ReminderKind.weighIn: null,
        ReminderKind.checkIn: 'Expenditure 2,640 kcal',
      });

      result = () => throw StateError('no profile');
      await r.replan();
      expect(scheduler.bodies[ReminderKind.checkIn], isNull);
      expect(scheduler.scheduled.keys, contains(ReminderKind.checkIn));
    });

    test('turned on, kept, scheduled; turned off, cancelled', () async {
      final r = reminders();
      expect(await r.set(ReminderKind.weighIn, _morning), isTrue);
      expect(await r.set(ReminderKind.checkIn, _nine), isTrue);

      expect(await reminders().timeOf(ReminderKind.weighIn), _morning);
      expect(scheduler.scheduled.keys, {
        ReminderKind.weighIn,
        ReminderKind.checkIn,
      });

      await r.set(ReminderKind.weighIn, null);
      expect(await r.timeOf(ReminderKind.weighIn), isNull);
      expect(scheduler.scheduled.keys, {ReminderKind.checkIn});
    });

    test('a refused permission keeps it off', () async {
      scheduler.granted = false;
      final r = reminders();
      expect(await r.set(ReminderKind.weighIn, _morning), isFalse);
      expect(await r.timeOf(ReminderKind.weighIn), isNull);
      expect(scheduler.scheduled, isEmpty);
    });

    test('the check-in is cancelled when the target stops adapting', () async {
      final r = reminders();
      await r.set(ReminderKind.checkIn, _nine);
      due = null;
      await r.replan();
      expect(scheduler.scheduled, isEmpty);
    });
  });

  group('tile', () {
    testWidgets('switching the weigh-in on shows its time', (tester) async {
      final scheduler = _Scheduler();
      final times = <ReminderKind, ReminderTime?>{};
      final r = _MemoryReminders(scheduler, times);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: RemindersTile(reminders: r)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Off'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('reminders-tile')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('reminder-weighIn')));
      await tester.pumpAndSettle();

      expect(times[ReminderKind.weighIn], (hour: 7, minute: 30));
      expect(find.text('7:30 AM'), findsOneWidget);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.text('Weigh-in 7:30 AM'), findsOneWidget);
    });
  });
}

/// In memory, as real Hive hangs under `testWidgets`.
class _MemoryReminders extends Reminders {
  final Map<ReminderKind, ReminderTime?> times;

  _MemoryReminders(_Scheduler scheduler, this.times)
    : super(scheduler: scheduler);

  @override
  Future<ReminderTime?> timeOf(ReminderKind kind) async => times[kind];

  @override
  Future<bool> set(ReminderKind kind, ReminderTime? time) async {
    times[kind] = time;
    Reminders.changes.value++;
    return true;
  }
}
