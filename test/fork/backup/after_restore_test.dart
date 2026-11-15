import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:opennutritracker/fork/backup/after_restore.dart';
import 'package:opennutritracker/fork/backup/auto_backup.dart';
import 'package:opennutritracker/fork/backup/backup_extras.dart';
import 'package:opennutritracker/fork/reminders/reminders.dart';

class _Scheduler implements ReminderScheduler {
  var asked = 0;
  var granted = true;
  var scheduled = 0;

  @override
  Future<bool> requestPermission() async {
    asked++;
    return granted;
  }

  @override
  Future<void> schedule(PlannedReminder reminder, {String? body}) async =>
      scheduled++;

  @override
  Future<void> cancel(ReminderKind kind) async {}
}

class _Reminders extends Reminders {
  final Map<ReminderKind, ReminderTime?> times;

  _Reminders(
    _Scheduler scheduler,
    this.times, {
    required bool allowed,
    bool dailyOn = false,
  }) : super(
         scheduler: scheduler,
         notificationsAllowed: () async => allowed,
         dailyReminderOn: () async => dailyOn,
         weighed: (_) async => false,
         checkInDueDay: () async => null,
         checkInResult: () async => null,
       );

  @override
  Future<ReminderTime?> timeOf(ReminderKind kind) async => times[kind];
}

const _morning = (hour: 7, minute: 30);

void main() {
  late Box<dynamic> box;
  late _Scheduler scheduler;

  setUp(() async {
    box = await Hive.openBox<dynamic>('after_restore', bytes: Uint8List(0));
    scheduler = _Scheduler();
    BackupExtras.restored = true;
  });

  tearDown(() async {
    await box.close();
    BackupExtras.restored = false;
    AutoBackup.state.value = const AutoBackupState();
  });

  Future<void> run(WidgetTester tester, Reminders reminders) async {
    late BuildContext context;
    await tester.pumpWidget(
      Builder(
        builder: (c) {
          context = c;
          return const SizedBox();
        },
      ),
    );
    // No ConfigRepository is registered, so the settings part does nothing.
    await tester.runAsync(
      () => afterRestore(
        context,
        backup: AutoBackup(box: () async => box),
        reminders: reminders,
      ),
    );
  }

  testWidgets('a reminder on without the permission: asked once, then '
      'planned', (tester) async {
    await run(
      tester,
      _Reminders(scheduler, {ReminderKind.weighIn: _morning}, allowed: false),
    );
    expect(scheduler.asked, 1);
    expect(scheduler.scheduled, 1);
  });

  testWidgets('upstream daily reminder on counts too', (tester) async {
    await run(tester, _Reminders(scheduler, {}, allowed: false, dailyOn: true));
    expect(scheduler.asked, 1);
  });

  testWidgets('not asked with the permission, or with no reminder on', (
    tester,
  ) async {
    await run(
      tester,
      _Reminders(scheduler, {ReminderKind.checkIn: _morning}, allowed: true),
    );
    BackupExtras.restored = true;
    await run(tester, _Reminders(scheduler, {}, allowed: false));
    expect(scheduler.asked, 0);
  });

  testWidgets('a restore notes that the backup is off', (tester) async {
    await run(tester, _Reminders(scheduler, {}, allowed: true));
    expect(AutoBackup.state.value.restoredWhileOff, isTrue);
  });

  testWidgets('after an export it does nothing new', (tester) async {
    BackupExtras.restored = false;
    await run(
      tester,
      _Reminders(scheduler, {ReminderKind.weighIn: _morning}, allowed: false),
    );
    expect(scheduler.asked, 0);
    expect(box.get('restoredWhileOff'), isNull);
  });
}
