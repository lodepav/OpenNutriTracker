import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:opennutritracker/fork/reminders/reminders.dart';
import 'package:opennutritracker/fork/reminders/reminders_ui.dart';

class _Scheduler implements ReminderScheduler {
  final scheduled = <ReminderKind, PlannedReminder>{};
  var granted = true;

  @override
  Future<bool> requestPermission() async => granted;

  @override
  Future<void> schedule(PlannedReminder reminder) async =>
      scheduled[reminder.kind] = reminder;

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

  group('reminders', () {
    late Directory dir;
    late _Scheduler scheduler;
    var weighed = false;
    DateTime? due;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('reminders');
      Hive.init(dir.path);
      scheduler = _Scheduler();
      weighed = false;
      due = DateTime(2026, 10, 27);
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
      clock: () => _now,
    );

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
