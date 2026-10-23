import 'dart:async';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/widgets.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import 'package:logging/logging.dart';
import 'package:opennutritracker/core/utils/hive_db_provider.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/settings/domain/usecase/export_data_usecase.dart';
import 'package:opennutritracker/features/settings/presentation/bloc/export_import_bloc.dart';
import 'package:opennutritracker/fork/backup/backup_folder.dart';

/// The automatic backup's state, kept on the device (not per profile): the
/// folder, and how the last attempt went.
class AutoBackupState {
  final String? folderUri;
  final String? folderName;
  final DateTime? lastSuccessAt;
  final DateTime? lastErrorAt;
  final String? lastError;

  const AutoBackupState({
    this.folderUri,
    this.folderName,
    this.lastSuccessAt,
    this.lastErrorAt,
    this.lastError,
  });

  bool get isOn => folderUri != null;
}

/// Writes upstream's JSON backup zip, with the fork's files (S21), into a
/// folder the user picked, once an hour at most, when the app goes to the
/// background (phase 2). Today's file is overwritten, and only the newest
/// [keep] of the profile are kept. A sync app takes the folder off the phone.
///
/// The shape follows theoleuthardt's `AutoBackupService` (one run shared by
/// concurrent calls, rotation by file name, the error stored, never thrown),
/// without its WebDAV target.
class AutoBackup {
  static const keep = 14;
  static const interval = Duration(hours: 1);
  static const boxName = 'ForkAutoBackupBox';
  static final _day = DateFormat('yyyy-MM-dd');
  static final _log = Logger('AutoBackup');

  static final state = ValueNotifier(const AutoBackupState());

  final BackupFolder _folder;
  final Future<Archive> Function() _assemble;
  final String Function() _profile;
  final DateTime Function() _clock;
  final Future<Box<dynamic>> Function() _box;
  Future<bool>? _running;

  AutoBackup({
    BackupFolder folder = const BackupFolder(),
    Future<Archive> Function()? assemble,
    String Function()? profile,
    DateTime Function()? clock,
    Future<Box<dynamic>> Function()? box,
  }) : _folder = folder,
       _assemble = assemble ?? _assembleExport,
       _profile = profile ?? _activeProfile,
       _clock = clock ?? DateTime.now,
       _box = box ?? (() => Hive.openBox<dynamic>(boxName));

  static AutoBackup? _instance;

  /// Run at start-up (seam S6): loads [state] and backs up whenever the app
  /// goes to the background.
  static Future<void> start() async {
    final backup = _instance = AutoBackup();
    await backup.load();
    WidgetsBinding.instance.addObserver(
      _Lifecycle(() => unawaited(backup.runIfDue())),
    );
  }

  static AutoBackup get instance => _instance ??= AutoBackup();

  // Upstream marks assembleArchive visible for testing, as the seam its own
  // export writes through; the backup needs the same archive without the
  // save dialog, so it is called here rather than an upstream file edited.
  static Future<Archive> _assembleExport() =>
      // ignore: invalid_use_of_visible_for_testing_member
      locator<ExportDataUsecase>().assembleArchive(
        format: ExportFormat.json,
        userActivityJsonFileName: ExportImportBloc.userActivityJsonFileName,
        userIntakeJsonFileName: ExportImportBloc.userIntakeJsonFileName,
        trackedDayJsonFileName: ExportImportBloc.trackedDayJsonFileName,
        recipeJsonFileName: ExportImportBloc.recipeJsonFileName,
        weightLogJsonFileName: ExportImportBloc.weightLogJsonFileName,
        customActivityTemplateJsonFileName:
            ExportImportBloc.customActivityTemplateJsonFileName,
        goalSettingsJsonFileName: ExportImportBloc.goalSettingsJsonFileName,
      );

  /// The active profile's tag: empty for the first profile, else the start
  /// of its box suffix (a UUID), enough to keep two profiles' files apart.
  static String _activeProfile() {
    final db = locator<HiveDBProvider>();
    final suffix = db.profileBox.get(db.activeProfileId)?.boxSuffix ?? '';
    return suffix.length > 8 ? suffix.substring(0, 8) : suffix;
  }

  /// `openbite-2026-10-23.zip`, or `openbite-<tag>-2026-10-23.zip` for
  /// another profile.
  String _fileName(DateTime day) {
    final profile = _profile();
    return 'openbite-${profile.isEmpty ? '' : '$profile-'}${_day.format(day)}.zip';
  }

  RegExp get _profileFiles {
    final profile = _profile();
    return RegExp(
      '^openbite-${profile.isEmpty ? '' : '${RegExp.escape(profile)}-'}'
      r'\d{4}-\d{2}-\d{2}\.zip$',
    );
  }

  Future<void> load() async {
    final box = await _box();
    state.value = AutoBackupState(
      folderUri: box.get('folderUri') as String?,
      folderName: box.get('folderName') as String?,
      lastSuccessAt: box.get('lastSuccessAt') as DateTime?,
      lastErrorAt: box.get('lastErrorAt') as DateTime?,
      lastError: box.get('lastError') as String?,
    );
  }

  Future<void> _put(Map<String, Object?> values) async {
    await (await _box()).putAll(values);
    await load();
  }

  /// Lets the user pick the folder and backs up into it at once; false when
  /// they cancelled.
  Future<bool> chooseFolder() async {
    final picked = await _folder.pick();
    if (picked == null) return false;
    await _put({'folderUri': picked.uri, 'folderName': picked.name});
    await runNow();
    return true;
  }

  Future<void> turnOff() async {
    await (await _box()).clear();
    await load();
  }

  Future<bool> runIfDue() async {
    final current = state.value;
    if (!current.isOn) return false;
    final last = current.lastSuccessAt;
    if (last != null && _clock().difference(last) < interval) return false;
    return runNow();
  }

  /// Backs up now; true when it worked. Concurrent calls share one run.
  Future<bool> runNow() =>
      _running ??= _run().whenComplete(() => _running = null);

  Future<bool> _run() async {
    final uri = state.value.folderUri;
    if (uri == null) return false;
    try {
      final now = _clock();
      final bytes = ZipEncoder().encode(await _assemble());
      final written = _fileName(now);
      await _folder.write(uri, written, Uint8List.fromList(bytes));
      final ours = (await _folder.list(
        uri,
      )).where(_profileFiles.hasMatch).toList()..sort((a, b) => b.compareTo(a));
      // The file just written stays even if a clock set back makes it
      // sort among the oldest (after openGym's pruneAutoBackups).
      ours.remove(written);
      for (final old in ours.skip(keep - 1)) {
        await _folder.delete(uri, old);
      }
      await _put({
        'lastSuccessAt': now,
        'lastErrorAt': null,
        'lastError': null,
      });
      return true;
    } catch (error, stackTrace) {
      _log.warning('Automatic backup failed', error, stackTrace);
      await _put({
        'lastErrorAt': _clock(),
        'lastError': error is BackupFolderException ? error.code : 'io',
      });
      return false;
    }
  }
}

class _Lifecycle with WidgetsBindingObserver {
  final VoidCallback _onPaused;

  _Lifecycle(this._onPaused);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) _onPaused();
  }
}
