import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:opennutritracker/core/presentation/widgets/app_card.dart';
import 'package:opennutritracker/fork/backup/auto_backup.dart';
import 'package:opennutritracker/fork/display/settings_tile.dart';
import 'package:opennutritracker/fork/layout/width_cap.dart';

/// Settings → "Automatic backup" (seam S23), beside upstream's export.
class AutoBackupTile extends StatelessWidget {
  const AutoBackupTile({super.key});

  @override
  Widget build(BuildContext context) => ForkSettingsTile(
    icon: Icons.backup_rounded,
    title: 'Automatic backup',
    subtitle: ValueListenableBuilder(
      valueListenable: AutoBackup.state,
      builder: (context, state, _) => Text(_summary(state)),
    ),
    onTap: () => Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const AutoBackupScreen())),
  );
}

String _when(DateTime at) => DateFormat.yMMMd().add_jm().format(at);

String _summary(AutoBackupState state) {
  if (!state.isOn) return 'Off';
  if (state.failed) return 'Last backup failed';
  final success = state.lastSuccessAt;
  return success == null ? 'On' : 'Last backup ${_when(success)}';
}

/// The backup's state on Settings' Data row.
String backupLine(AutoBackupState state) {
  if (!state.isOn) return 'Backup off';
  if (state.failed) return 'Last backup failed';
  final success = state.lastSuccessAt;
  return success == null ? 'Backup on' : 'Backed up ${_when(success)}';
}

enum BackupNotice { none, failed, offAfterRestore }

/// What Home says about the backup: a failure until dismissed, then
/// nothing while the same one repeats; after a restore left it off, that, until
/// dismissed or a folder is chosen.
BackupNotice backupNotice(AutoBackupState state) {
  final dismissed = state.dismissedErrorAt;
  if (state.failed &&
      (dismissed == null || state.lastErrorAt!.isAfter(dismissed))) {
    return BackupNotice.failed;
  }
  if (state.restoredWhileOff && !state.isOn) {
    return BackupNotice.offAfterRestore;
  }
  return BackupNotice.none;
}

String _errorText(String? code) => switch (code) {
  'access_denied' =>
    "The app can no longer open the folder (after a reinstall, for "
        'example). Choose it again.',
  _ => "The backup couldn't be written.",
};

class AutoBackupScreen extends StatefulWidget {
  final AutoBackup? backup;

  const AutoBackupScreen({super.key, this.backup});

  @override
  State<AutoBackupScreen> createState() => _AutoBackupScreenState();
}

class _AutoBackupScreenState extends State<AutoBackupScreen> {
  late final AutoBackup _backup = widget.backup ?? AutoBackup.instance;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _backup.load();
  }

  Future<void> _do(Future<bool> Function() action, String done) async {
    setState(() => _busy = true);
    final ok = await action();
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(done)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Automatic backup')),
      body: ValueListenableBuilder(
        valueListenable: AutoBackup.state,
        builder: (context, state, _) {
          final error = state.lastErrorAt;
          return ListView(
            padding: EdgeInsets.fromLTRB(
              16,
              16,
              16,
              16 + MediaQuery.paddingOf(context).bottom,
            ),
            children: [
              Text(
                'When you leave the app, at most once an hour, it saves a '
                "backup of every profile's diary, recipes, foods, weights, "
                'water, fasts, goals, body measurements and progress photos '
                "into a folder you choose. Today's "
                'file is updated during the day, and the newest '
                '${AutoBackup.keep} days are kept.',
                style: textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'The files stay on this phone. To keep a copy in Google Drive, '
                'sync the folder with an app such as Autosync for Google '
                'Drive or FolderSync. The files are not encrypted, photos '
                'included.',
                style: textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'To restore, go to Settings → Data → Export / import app '
                'data → Import, and pick a backup file from the folder.',
                style: textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.folder_rounded),
                title: Text(state.folderName ?? 'No folder chosen'),
                subtitle: Text(_summary(state)),
              ),
              if (state.failed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    '${_errorText(state.lastError)} (${_when(error!)})',
                    style: textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              FilledButton.icon(
                key: const Key('fork-backup-choose'),
                onPressed: _busy
                    ? null
                    : () => _do(_backup.chooseFolder, 'Backed up'),
                icon: const Icon(Icons.create_new_folder_rounded),
                label: Text(
                  state.isOn ? 'Choose another folder' : 'Choose folder',
                ),
              ),
              if (state.isOn) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  key: const Key('fork-backup-now'),
                  onPressed: _busy
                      ? null
                      : () => _do(_backup.runNow, 'Backed up'),
                  icon: const Icon(Icons.backup_rounded),
                  label: const Text('Back up now'),
                ),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => _do(() async {
                          await _backup.turnOff();
                          return true;
                        }, 'Automatic backup is off'),
                  child: const Text('Turn off'),
                ),
              ],
            ].map<Widget>((c) => WidthCap(child: c)).toList(),
          );
        },
      ),
    );
  }
}

/// Seam S219: Home's notice of a failed backup, or of a restore that left
/// the backup off on this phone ([backupNotice]).
class BackupNoticeCard extends StatelessWidget {
  final AutoBackup? backup;

  const BackupNoticeCard({super.key, this.backup});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: AutoBackup.state,
    builder: (context, state, _) {
      final backup = this.backup ?? AutoBackup.instance;
      final (title, body, dismiss) = switch (backupNotice(state)) {
        BackupNotice.none => (null, null, null),
        BackupNotice.failed => (
          'The last backup failed',
          _errorText(state.lastError),
          backup.dismissFailure,
        ),
        BackupNotice.offAfterRestore => (
          'Automatic backup is off on this phone',
          "A restore doesn't bring the backup folder. Choose one to keep "
              'backing up.',
          backup.dismissRestoreNotice,
        ),
      };
      if (title == null) return const SizedBox.shrink();
      final text = Theme.of(context).textTheme;
      return Padding(
        // Home's sections bring their own margins; the card has none.
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: AppCard(
          padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => AutoBackupScreen(backup: this.backup),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: text.titleMedium),
                    Text(body!),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Dismiss',
                icon: const Icon(Icons.close),
                onPressed: dismiss,
              ),
            ],
          ),
        ),
      );
    },
  );
}
