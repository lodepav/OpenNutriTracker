import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import 'package:opennutritracker/core/presentation/widgets/app_card.dart';
import 'package:opennutritracker/fork/backup/auto_backup.dart';
import 'package:opennutritracker/fork/backup/auto_backup_ui.dart';

final _ok = DateTime(2026, 11, 10, 9);
final _fail = DateTime(2026, 11, 12, 9);

void main() {
  group('backupLine', () {
    test('off, on, backed up, failed', () {
      expect(backupLine(const AutoBackupState(), 'en_US'), 'Backup off');
      expect(
        backupLine(const AutoBackupState(folderUri: 'f'), 'en_US'),
        'Backup on',
      );
      expect(
        backupLine(
          AutoBackupState(folderUri: 'f', lastSuccessAt: _ok),
          'en_US',
        ),
        'Backed up ${DateFormat.yMMMd().add_jm().format(_ok)}',
      );
      expect(
        backupLine(
          AutoBackupState(
            folderUri: 'f',
            lastSuccessAt: _ok,
            lastErrorAt: _fail,
          ),
          'en_US',
        ),
        'Last backup failed',
      );
    });
  });

  group('backupNotice', () {
    AutoBackupState failed({DateTime? dismissed, DateTime? at}) =>
        AutoBackupState(
          folderUri: 'f',
          lastSuccessAt: _ok,
          lastErrorAt: at ?? _fail,
          dismissedErrorAt: dismissed,
        );

    test('a failure shows until dismissed; a newer one shows again', () {
      expect(backupNotice(failed()), BackupNotice.failed);
      expect(backupNotice(failed(dismissed: _fail)), BackupNotice.none);
      expect(
        backupNotice(
          failed(dismissed: _fail, at: _fail.add(const Duration(hours: 1))),
        ),
        BackupNotice.failed,
      );
    });

    test('a failure before the last success shows nothing', () {
      expect(
        backupNotice(
          AutoBackupState(
            folderUri: 'f',
            lastSuccessAt: _fail,
            lastErrorAt: _ok,
          ),
        ),
        BackupNotice.none,
      );
    });

    test('a restore while off shows until dismissed or a folder chosen', () {
      expect(
        backupNotice(const AutoBackupState(restoredWhileOff: true)),
        BackupNotice.offAfterRestore,
      );
      expect(backupNotice(const AutoBackupState()), BackupNotice.none);
      expect(
        backupNotice(
          const AutoBackupState(folderUri: 'f', restoredWhileOff: true),
        ),
        BackupNotice.none,
      );
    });
  });

  group('the stored marks', () {
    late Box<dynamic> box;
    late AutoBackup backup;

    setUp(() async {
      box = await Hive.openBox<dynamic>('notice_marks', bytes: Uint8List(0));
      backup = AutoBackup(box: () async => box);
    });

    tearDown(() async {
      await box.close();
      AutoBackup.state.value = const AutoBackupState();
    });

    test('a restore is noted only while the backup is off', () async {
      await backup.markRestoredWhileOff();
      expect(AutoBackup.state.value.restoredWhileOff, isTrue);
      await backup.dismissRestoreNotice();
      expect(AutoBackup.state.value.restoredWhileOff, isFalse);

      await box.put('folderUri', 'content://f');
      await backup.markRestoredWhileOff();
      expect(box.get('restoredWhileOff'), isNull);
    });

    test('a dismissal keeps the failure it hid', () async {
      await box.putAll({
        'folderUri': 'content://f',
        'lastErrorAt': _fail,
        'lastError': 'io',
      });
      await backup.load();
      await backup.dismissFailure();
      expect(backupNotice(AutoBackup.state.value), BackupNotice.none);
      await backup.turnOff();
      expect(backupNotice(AutoBackup.state.value), BackupNotice.none);
    });
  });

  group('card', () {
    late Box<dynamic> box;

    setUpAll(() async {
      box = await Hive.openBox<dynamic>('notice_card', bytes: Uint8List(0));
    });

    tearDownAll(() async {
      await box.close();
      AutoBackup.state.value = const AutoBackupState();
    });

    testWidgets('shows a failure, and Dismiss hides it', (tester) async {
      final backup = AutoBackup(box: () async => box);
      await tester.runAsync(() async {
        await box.putAll({
          'folderUri': 'content://f',
          'lastErrorAt': _fail,
          'lastError': 'io',
        });
        await backup.load();
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: BackupNoticeCard(backup: backup)),
        ),
      );
      expect(find.text('The last backup failed'), findsOneWidget);
      expect(find.text("The backup couldn't be written."), findsOneWidget);

      await tester.runAsync(() async {
        await tester.tap(find.byTooltip('Dismiss'));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();
      expect(find.text('The last backup failed'), findsNothing);
      expect(box.get('dismissedErrorAt'), _fail);
    });

    testWidgets('shows nothing with nothing to say', (tester) async {
      AutoBackup.state.value = const AutoBackupState(folderUri: 'f');
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: BackupNoticeCard())),
      );
      expect(find.byType(AppCard), findsNothing);
      expect(find.byTooltip('Dismiss'), findsNothing);
    });
  });
}
