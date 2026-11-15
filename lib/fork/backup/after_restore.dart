import 'package:flutter/widgets.dart';
import 'package:logging/logging.dart';
import 'package:opennutritracker/fork/backup/apply_restored_settings.dart';
import 'package:opennutritracker/fork/backup/auto_backup.dart';
import 'package:opennutritracker/fork/backup/backup_extras.dart';
import 'package:opennutritracker/fork/reminders/reminders.dart';

final _log = Logger('afterRestore');

/// What a finished restore does, from Settings' import (seam S38) and from
/// onboarding: shows the restored settings, notes on this phone that the
/// backup is off when it is, and asks for the notification permission when
/// a restored reminder would otherwise stay silent. Once per restore.
Future<void> afterRestore(
  BuildContext context, {
  AutoBackup? backup,
  Reminders? reminders,
}) async {
  // First, while the context is sure to be mounted.
  final settings = applyRestoredSettings(context);
  // Settings' dialog calls this after an export too, and on each rebuild.
  if (!BackupExtras.restored) return settings;
  BackupExtras.restored = false;
  try {
    await (backup ?? AutoBackup.instance).markRestoredWhileOff();
  } catch (error, stack) {
    _log.warning('Could not note the restore', error, stack);
  }
  try {
    await (reminders ?? Reminders()).askIfSilent();
  } catch (error, stack) {
    _log.warning('Could not ask for the notification permission', error, stack);
  }
  await settings;
}
