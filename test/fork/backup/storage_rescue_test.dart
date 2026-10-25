import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:opennutritracker/core/domain/usecase/add_config_usecase.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/settings/domain/usecase/import_data_usecase.dart';
import 'package:opennutritracker/fork/backup/auto_backup.dart';
import 'package:opennutritracker/fork/backup/backup_folder.dart';
import 'package:opennutritracker/fork/backup/storage_rescue.dart';

class _Folder extends BackupFolder {
  final List<String> files;
  _Folder(this.files);

  @override
  Future<List<String>> list(String uri) async => files;

  @override
  Future<Uint8List?> read(String uri, String name) async =>
      Uint8List.fromList(ZipEncoder().encode(Archive()));
}

class _Import extends Fake implements ImportDataUsecase {
  int imports = 0;

  @override
  Future<bool> importArchive(
    Archive archive,
    String userActivityJsonFileName,
    String userIntakeJsonFileName,
    String trackedDayJsonFileName,
    String recipeJsonFileName,
    String weightLogJsonFileName,
    String customActivityTemplateJsonFileName, {
    String goalSettingsJsonFileName = 'goal_settings.json',
    String favouriteJsonFileName = 'user_favourites.json',
    Object? startedOn,
  }) async {
    imports++;
    return true;
  }
}

class _Config extends Fake implements AddConfigUsecase {
  bool? policy;

  @override
  Future<void> setConfigHasAcceptedPolicy(bool hasAcceptedPolicy) async =>
      policy = hasAcceptedPolicy;

  @override
  Future<void> setConfigPolicyNoticeRevisionSeen(int revision) async {}

  @override
  Future<void> setConfigHasAcceptedAnonymousData(
    bool hasAcceptedAnonymousData,
  ) async {}

  @override
  Future<void> setConfigIsDemoData(bool isDemoData) async {}
}

void main() {
  late Directory dir;

  StorageRescue rescue(List<String> files) => StorageRescue(
    folder: _Folder(files),
    hiveDir: () async => dir,
    box: () => Hive.openBox<dynamic>(AutoBackup.boxName),
    clock: () => DateTime(2026, 10, 25, 14, 30),
  );

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('storage_rescue');
    Hive.init(dir.path);
    await (await Hive.openBox<dynamic>(
      AutoBackup.boxName,
    )).put('folderUri', 'content://backups');
  });

  tearDown(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  test('the newest automatic backup, of any profile', () async {
    final latest = await rescue([
      'openbite-2026-10-22.zip',
      'openbite-1a2b3c4d-2026-10-24.zip',
      'openbite-2026-10-23.zip',
      'notes.txt',
    ]).latestBackup();
    expect(latest?.name, 'openbite-1a2b3c4d-2026-10-24.zip');
    expect(latest?.day, DateTime(2026, 10, 24));
  });

  test('none without a backup folder', () async {
    await (await Hive.openBox<dynamic>(AutoBackup.boxName)).clear();
    expect(await rescue(['openbite-2026-10-22.zip']).latestBackup(), isNull);
  });

  test('the data files go aside, not away; the backup box stays', () async {
    for (final name in ['intakebox.hive', 'intakebox.lock', 'photo.jpg']) {
      await File('${dir.path}/$name').writeAsString('x');
    }
    final aside = await rescue(const []).setAside();
    expect(aside.path, endsWith('set-aside-20261025-143000'));
    expect(File('${aside.path}/intakebox.hive').existsSync(), isTrue);
    expect(File('${aside.path}/intakebox.lock').existsSync(), isTrue);
    expect(File('${dir.path}/intakebox.hive').existsSync(), isFalse);
    expect(File('${dir.path}/photo.jpg').existsSync(), isTrue);
    expect(
      File('${dir.path}/${AutoBackup.boxName.toLowerCase()}.hive').existsSync(),
      isTrue,
    );
  });

  group('restored at the next start', () {
    late _Import import;
    late _Config config;

    setUp(() {
      import = _Import();
      config = _Config();
      locator.registerSingleton<ImportDataUsecase>(import);
      locator.registerSingleton<AddConfigUsecase>(config);
    });

    tearDown(() async {
      await locator.unregister<ImportDataUsecase>();
      await locator.unregister<AddConfigUsecase>();
    });

    test('once, with the policy kept accepted', () async {
      final r = rescue(['openbite-2026-10-24.zip']);
      await r.restoreAtStart('openbite-2026-10-24.zip');
      expect(await r.finishPending(), isTrue);
      expect(import.imports, 1);
      expect(config.policy, isTrue);
      expect(await r.finishPending(), isFalse);
      expect(import.imports, 1);
    });

    test('nothing pending, nothing restored', () async {
      expect(
        await rescue(['openbite-2026-10-24.zip']).finishPending(),
        isFalse,
      );
      expect(import.imports, 0);
    });
  });

  testWidgets('the screen offers the backup, asks, and starts again', (
    tester,
  ) async {
    var retried = 0;
    String? restored;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StorageRescuePanel(
            rescue: _Rescue((name) => restored = name),
            onRetry: () async => retried++,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restore the backup of Oct 24, 2026'));
    await tester.pumpAndSettle();
    expect(find.textContaining('anything logged after it'), findsOneWidget);
    await tester.tap(find.text('Restore'));
    await tester.pumpAndSettle();
    expect(restored, 'openbite-2026-10-24.zip');
    expect(retried, 1);
  });
}

class _Rescue extends StorageRescue {
  final void Function(String) onRestore;
  _Rescue(this.onRestore);

  @override
  Future<({String name, DateTime day})?> latestBackup() async =>
      (name: 'openbite-2026-10-24.zip', day: DateTime(2026, 10, 24));

  @override
  Future<void> restoreAtStart(String backup) async => onRestore(backup);
}
