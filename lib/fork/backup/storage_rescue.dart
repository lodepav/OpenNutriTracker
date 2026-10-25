import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import 'package:logging/logging.dart';
import 'package:opennutritracker/core/utils/hive_db_provider.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/settings/domain/usecase/import_data_usecase.dart';
import 'package:opennutritracker/features/settings/presentation/bloc/export_import_bloc.dart';
import 'package:opennutritracker/fork/backup/auto_backup.dart';
import 'package:opennutritracker/fork/backup/backup_folder.dart';
import 'package:opennutritracker/fork/backup/onboarding_restore.dart';
import 'package:path_provider/path_provider.dart';

/// A way out when the local data will not open (seam S112): Android can
/// kill the app mid-write, and a box that then fails its checksum stops the
/// start on upstream's recovery screen, whose Retry fails the same way.
///
/// The files that will not open are never deleted: they are moved into a
/// `set-aside-…` folder beside them. Then either the newest automatic backup
/// is restored as the app starts again, or the app starts as new, where
/// onboarding can restore a backup file.
class StorageRescue {
  static const pendingKey = 'restorePending';

  /// Whether moving the files aside can help: only for data that will not
  /// open. A lost or broken key still fails with the files gone, as the
  /// kept backup box counts as data.
  static bool helps(String errorCode) =>
      errorCode == 'hive_wrong_key_or_corrupted';
  static final _log = Logger('StorageRescue');
  static final _stamp = DateFormat('yyyyMMdd-HHmmss');

  /// `openbite-2026-10-24.zip`, or with a profile's tag before the day.
  static final _backupFile = RegExp(
    r'^openbite-([^-]+-)?(\d{4}-\d{2}-\d{2})\.zip$',
  );

  final BackupFolder _folder;
  final Future<Directory> Function() _hiveDir;
  final Future<Box<dynamic>> Function() _box;
  final DateTime Function() _clock;

  StorageRescue({
    BackupFolder folder = const BackupFolder(),
    Future<Directory> Function()? hiveDir,
    Future<Box<dynamic>> Function()? box,
    DateTime Function()? clock,
  }) : _folder = folder,
       // Where Hive.initFlutter() keeps the boxes.
       _hiveDir = hiveDir ?? getApplicationDocumentsDirectory,
       _box = box ?? _autoBackupBox,
       _clock = clock ?? DateTime.now;

  /// The automatic backup's box: not encrypted, so it opens when the rest
  /// will not, and it says where the backups are.
  static Future<Box<dynamic>> _autoBackupBox() async {
    await Hive.initFlutter();
    return Hive.openBox<dynamic>(AutoBackup.boxName);
  }

  /// The newest automatic backup, or null when there is none to be had:
  /// the first profile's when it has one, as the app starts again with
  /// only that profile, whose backups another's would then prune.
  Future<({String name, DateTime day})?> latestBackup() async {
    try {
      final uri = (await _box()).get('folderUri') as String?;
      if (uri == null) return null;
      ({String name, DateTime day})? first, other;
      for (final name in await _folder.list(uri)) {
        final match = _backupFile.firstMatch(name);
        if (match == null) continue;
        final date = DateTime.parse(match.group(2)!);
        final newest = match.group(1) == null ? first : other;
        if (newest != null && !date.isAfter(newest.day)) continue;
        if (match.group(1) == null) {
          first = (name: name, day: date);
        } else {
          other = (name: name, day: date);
        }
      }
      return first ?? other;
    } catch (error, stackTrace) {
      _log.warning('No automatic backup to offer', error, stackTrace);
      return null;
    }
  }

  /// Moves the data files into a dated folder beside them, all but the
  /// automatic backup's box; the folder.
  Future<Directory> setAside() async {
    await Hive.close();
    if (locator.isRegistered<HiveDBProvider>()) await locator.reset();
    final dir = await _hiveDir();
    final aside = Directory('${dir.path}/set-aside-${_stamp.format(_clock())}');
    await aside.create();
    final keep = AutoBackup.boxName.toLowerCase();
    for (final file in dir.listSync().whereType<File>()) {
      final name = file.uri.pathSegments.last;
      if (!name.endsWith('.hive') && !name.endsWith('.lock')) continue;
      if (name.startsWith('$keep.')) continue;
      await file.rename('${aside.path}/$name');
    }
    await (await _box()).put(AutoBackup.setAsideOnKey, _clock());
    return aside;
  }

  /// Sets the files aside and leaves [backup] for the next start to
  /// restore ([finishPending]).
  Future<void> restoreAtStart(String backup) async {
    await setAside();
    await (await _box()).put(pendingKey, backup);
  }

  /// At start-up, once the locator is up (seam S6): restores the backup
  /// [restoreAtStart] left, as onboarding's restore does. Tried once: a
  /// backup that fails leaves the app as new, where onboarding can restore
  /// a file. True when a backup was restored.
  Future<bool> finishPending() async {
    final box = await _box();
    final name = box.get(pendingKey) as String?;
    if (name == null) return false;
    await box.delete(pendingKey);
    try {
      final uri = box.get('folderUri') as String?;
      final bytes = uri == null ? null : await _folder.read(uri, name);
      if (bytes == null) return false;
      await locator<ImportDataUsecase>().importArchive(
        ZipDecoder().decodeBytes(bytes),
        ExportImportBloc.userActivityJsonFileName,
        ExportImportBloc.userIntakeJsonFileName,
        ExportImportBloc.trackedDayJsonFileName,
        ExportImportBloc.recipeJsonFileName,
        ExportImportBloc.weightLogJsonFileName,
        ExportImportBloc.customActivityTemplateJsonFileName,
        goalSettingsJsonFileName: ExportImportBloc.goalSettingsJsonFileName,
        favouriteJsonFileName: ExportImportBloc.favouriteJsonFileName,
      );
      // Accepted before the files broke; crash reports stay off until
      // asked again.
      await OnboardingRestore().accept(dataCollection: false);
      // The data is the backup's again, safe to back up.
      await box.delete(AutoBackup.setAsideOnKey);
      return true;
    } catch (error, stackTrace) {
      _log.severe('Restoring $name failed', error, stackTrace);
      return false;
    }
  }
}

/// The recovery screen's way out (seam S112): restore the newest automatic
/// backup, or start again; either sets the files aside first.
class StorageRescuePanel extends StatefulWidget {
  /// Starts the app again, as the screen's Retry does.
  final Future<void> Function() onRetry;
  final StorageRescue? rescue;

  const StorageRescuePanel({super.key, required this.onRetry, this.rescue});

  @override
  State<StorageRescuePanel> createState() => _StorageRescuePanelState();
}

class _StorageRescuePanelState extends State<StorageRescuePanel> {
  late final _rescue = widget.rescue ?? StorageRescue();
  late final _latest = _rescue.latestBackup();
  bool _busy = false;

  Future<void> _run({
    required String title,
    required String body,
    required String action,
    required Future<void> Function() step,
  }) async {
    final go = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(action),
          ),
        ],
      ),
    );
    if (go != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await step();
      await widget.onRetry();
    } catch (error, stackTrace) {
      StorageRescue._log.severe('Recovery step failed', error, stackTrace);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'That did not work. Nothing was deleted; try again, or '
              'start again.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: _latest,
    builder: (context, snapshot) {
      final latest = snapshot.data;
      const aside =
          'The files that will not open are moved aside on the phone, not '
          'deleted.';
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (latest != null) ...[
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              key: const ValueKey('storage-rescue-restore'),
              onPressed: _busy
                  ? null
                  : () => _run(
                      title: 'Restore the automatic backup?',
                      body:
                          '$aside Your backup of '
                          '${DateFormat.yMMMd().format(latest.day)} is '
                          'restored, so anything logged after it is not '
                          'there.',
                      action: 'Restore',
                      step: () => _rescue.restoreAtStart(latest.name),
                    ),
              icon: const Icon(Icons.settings_backup_restore_rounded),
              label: Text(
                'Restore the backup of '
                '${DateFormat.yMMMd().format(latest.day)}',
              ),
            ),
          ],
          const SizedBox(height: 12),
          TextButton(
            key: const ValueKey('storage-rescue-fresh'),
            onPressed: _busy
                ? null
                : () => _run(
                    title: 'Start again?',
                    body:
                        '$aside The app starts as new; its setup can '
                        'restore a backup file.',
                    action: 'Start again',
                    step: _rescue.setAside,
                  ),
            child: const Text('Start again without this data'),
          ),
        ],
      );
    },
  );
}
