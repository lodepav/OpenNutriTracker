import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:opennutritracker/fork/backup/auto_backup.dart';
import 'package:opennutritracker/fork/backup/backup_folder.dart';

void main() {
  late Directory dir;
  late _Folder folder;
  late DateTime now;
  var profile = '';

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('auto_backup');
    Hive.init(dir.path);
    folder = _Folder();
    now = DateTime(2026, 10, 23, 12);
    profile = '';
  });

  tearDown(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  AutoBackup backup() => AutoBackup(
    folder: folder,
    assemble: () async => Archive(),
    profile: () => profile,
    clock: () => now,
    box: () => Hive.openBox<dynamic>(AutoBackup.boxName),
  );

  test('off until a folder is chosen, then backs up at once', () async {
    final b = backup();
    await b.load();
    expect(await b.runIfDue(), isFalse);
    expect(folder.files, isEmpty);

    expect(await b.chooseFolder(), isTrue);
    expect(folder.files.keys, ['openbite-2026-10-23.zip']);
    expect(AutoBackup.state.value.folderName, 'Backups');
    expect(AutoBackup.state.value.lastSuccessAt, now);
  });

  test('at most once an hour; the day\'s file is replaced', () async {
    final b = backup();
    await b.chooseFolder();
    folder.writes = 0;

    now = now.add(const Duration(minutes: 30));
    expect(await b.runIfDue(), isFalse);
    now = now.add(const Duration(minutes: 31));
    expect(await b.runIfDue(), isTrue);
    expect(folder.writes, 1);
    expect(folder.files.length, 1);
  });

  test(
    'keeps the newest 14 of the profile and leaves the rest alone',
    () async {
      folder.files['openbite-p2-2026-01-01.zip'] = Uint8List(0);
      folder.files['notes.txt'] = Uint8List(0);
      final b = backup();
      await b.chooseFolder();
      for (var i = 1; i <= 20; i++) {
        now = now.add(const Duration(days: 1));
        await b.runNow();
      }
      final ours =
          folder.files.keys
              .where((n) => RegExp(r'^openbite-\d').hasMatch(n))
              .toList()
            ..sort();
      expect(ours.length, AutoBackup.keep);
      expect(ours.last, 'openbite-2026-11-12.zip');
      expect(folder.files, contains('openbite-p2-2026-01-01.zip'));
      expect(folder.files, contains('notes.txt'));
    },
  );

  test('a second profile writes its own files', () async {
    final b = backup();
    await b.chooseFolder();
    profile = 'p2';
    await b.runNow();
    expect(folder.files.keys, contains('openbite-p2-2026-10-23.zip'));
  });

  test('a lost grant is stored, not thrown, and retried next time', () async {
    final b = backup();
    await b.chooseFolder();
    folder.fail = const BackupFolderException('access_denied');
    now = now.add(const Duration(hours: 2));
    expect(await b.runIfDue(), isFalse);
    expect(AutoBackup.state.value.lastError, 'access_denied');

    folder.fail = null;
    now = now.add(const Duration(minutes: 1));
    expect(await b.runIfDue(), isTrue);
    expect(AutoBackup.state.value.lastError, isNull);
  });
}

class _Folder extends BackupFolder {
  final files = <String, Uint8List>{};
  var writes = 0;
  BackupFolderException? fail;

  @override
  Future<({String uri, String name})?> pick() async =>
      (uri: 'content://tree/backups', name: 'Backups');

  @override
  Future<List<String>> list(String uri) async => files.keys.toList();

  @override
  Future<void> write(String uri, String name, Uint8List bytes) async {
    if (fail != null) throw fail!;
    writes++;
    files[name] = bytes;
  }

  @override
  Future<void> delete(String uri, String name) async => files.remove(name);
}
