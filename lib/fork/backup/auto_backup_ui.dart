import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:opennutritracker/fork/backup/auto_backup.dart';

/// Settings → "Automatic backup" (seam S23), beside upstream's export.
class AutoBackupTile extends StatelessWidget {
  const AutoBackupTile({super.key});

  @override
  Widget build(BuildContext context) => ListTile(
    leading: const Icon(Icons.backup_rounded),
    title: const Text('Automatic backup'),
    subtitle: ValueListenableBuilder(
      valueListenable: AutoBackup.state,
      builder: (context, state, _) => Text(_summary(state)),
    ),
    onTap: () => Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const AutoBackupScreen())),
  );
}

String _when(DateTime at) => DateFormat.yMMMd().add_Hm().format(at);

String _summary(AutoBackupState state) {
  if (!state.isOn) return 'Off';
  final error = state.lastErrorAt;
  final success = state.lastSuccessAt;
  if (error != null && (success == null || error.isAfter(success))) {
    return 'Last backup failed';
  }
  return success == null ? 'On' : 'Last backup ${_when(success)}';
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
          final success = state.lastSuccessAt;
          final failed =
              error != null && (success == null || error.isAfter(success));
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'When you leave the app, at most once an hour, it saves a '
                "backup of this profile's diary, recipes, foods, weights, "
                "water, fasts and goals into a folder you choose. Today's "
                'file is updated during the day, and the newest '
                '${AutoBackup.keep} days are kept.',
                style: textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'The files stay on this phone. To keep a copy in Google Drive, '
                'sync the folder with an app such as Autosync for Google '
                'Drive or FolderSync. The files are not encrypted.',
                style: textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'To restore, go to Settings → Export / Import app data → '
                'Import, and pick a backup file from the folder.',
                style: textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.folder_rounded),
                title: Text(state.folderName ?? 'No folder chosen'),
                subtitle: Text(_summary(state)),
              ),
              if (failed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    '${_errorText(state.lastError)} (${_when(error)})',
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
            ],
          );
        },
      ),
    );
  }
}
