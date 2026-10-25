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
  final bool readable;
  _Folder(this.files, {this.readable = true});

  @override
  Future<List<String>> list(String uri) async => files;

  @override
  Future<Uint8List?> read(String uri, String name) async =>
      readable ? Uint8List.fromList(ZipEncoder().encode(Archive())) : null;
}

class _Import extends Fake implements ImportDataUsecase {
  int imports = 0;
  bool fails = false;

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
    if (fails) throw const FormatException('not a backup');
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

  StorageRescue rescue(List<String> files, {bool readable = true}) =>
      StorageRescue(
        folder: _Folder(files, readable: readable),
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

  test("the first profile's newest backup, as the app starts again with "
      'only that profile', () async {
    final latest = await rescue([
      'openbite-2026-10-22.zip',
      'openbite-1a2b3c4d-2026-10-24.zip',
      'openbite-2026-10-23.zip',
      'notes.txt',
    ]).latestBackup();
    expect(latest?.name, 'openbite-2026-10-23.zip');
    expect(latest?.day, DateTime(2026, 10, 23));
  });

  test("another profile's newest when the first has none", () async {
    final latest = await rescue([
      'openbite-1a2b3c4d-2026-10-22.zip',
      'openbite-1a2b3c4d-2026-10-24.zip',
    ]).latestBackup();
    expect(latest?.name, 'openbite-1a2b3c4d-2026-10-24.zip');
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
    // Holds today's backup back from being written over (AutoBackup).
    expect(
      (await Hive.openBox<dynamic>(
        AutoBackup.boxName,
      )).get(AutoBackup.setAsideOnKey),
      DateTime(2026, 10, 25, 14, 30),
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
      expect(
        (await Hive.openBox<dynamic>(
          AutoBackup.boxName,
        )).containsKey(AutoBackup.setAsideOnKey),
        isFalse,
      );
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

    test('a backup that is gone or will not import is tried once, and the '
        'app starts as new', () async {
      final gone = rescue(['openbite-2026-10-24.zip'], readable: false);
      await gone.restoreAtStart('openbite-2026-10-24.zip');
      expect(await gone.finishPending(), isFalse);
      expect(import.imports, 0);

      import.fails = true;
      final broken = rescue(['openbite-2026-10-24.zip']);
      await broken.restoreAtStart('openbite-2026-10-24.zip');
      expect(await broken.finishPending(), isFalse);
      expect(import.imports, 1);
      expect(config.policy, isNull);
      expect(await broken.finishPending(), isFalse);
      expect(import.imports, 1);
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

    await tester.tap(find.text('Start again without this data'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(retried, 1);
    await tester.tap(find.text('Start again without this data'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Start again'));
    await tester.pumpAndSettle();
    expect(asides, 1);
    expect(retried, 2);
  });

  testWidgets('a step that fails says nothing was deleted and does not '
      'start again', (tester) async {
    var retried = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StorageRescuePanel(
            rescue: _Rescue((_) => throw const FileSystemException('busy')),
            onRetry: () async => retried++,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restore the backup of Oct 24, 2026'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restore'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Nothing was deleted'), findsOneWidget);
    expect(retried, 0);
  });
}

var asides = 0;

class _Rescue extends StorageRescue {
  final void Function(String) onRestore;
  _Rescue(this.onRestore);

  @override
  Future<({String name, DateTime day})?> latestBackup() async =>
      (name: 'openbite-2026-10-24.zip', day: DateTime(2026, 10, 24));

  @override
  Future<void> restoreAtStart(String backup) async => onRestore(backup);

  @override
  Future<Directory> setAside() async {
    asides++;
    return Directory.systemTemp;
  }
}
