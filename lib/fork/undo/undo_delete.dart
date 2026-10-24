import 'dart:async';

import 'package:flutter/material.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/utils/tracked_day_lock.dart';
import 'package:opennutritracker/fork/basket/basket_ui.dart';
import 'package:opennutritracker/fork/copy/copy_entries.dart';

typedef RestoreIntakes =
    Future<void> Function(
      List<IntakeEntity> intakes,
      DateTime day,
      ProfileStamp startedOn,
    );

/// Writes the entries back under the tracked-day lock, into the profile they
/// were deleted from only, then refreshes Home and the Diary.
Future<void> restoreDeletedIntakes(
  List<IntakeEntity> intakes,
  DateTime day,
  ProfileStamp startedOn,
) async {
  await withTrackedDayLockOnProfile(
    () => CopyEntries.fromLocator().restoreIntakes(intakes, day),
    startedOn: startedOn,
  );
  refreshAfterLogging();
}

/// "Entry deleted · Undo" after a diary entry is deleted (seam S52), in place
/// of upstream's confirmation dialog: the delete happens at once, and Undo
/// writes the entries back with their ids, so meal groups and the Health
/// Connect export see them unchanged. Deletes of one day that follow each
/// other while the bar is up (a meal's "Delete all") gather into one bar, and
/// its Undo brings all of them back. [startedOn] is taken before the delete:
/// where the profile changed since, the delete did not happen there or the
/// entry belongs to another profile, so no bar is shown.
class DeletedEntries {
  /// The bar on screen and what its Undo restores; null once it has gone.
  static ({
    ScaffoldFeatureController<SnackBar, SnackBarClosedReason> bar,
    List<IntakeEntity> entries,
    DateTime day,
    ProfileStamp stamp,
  })?
  _open;

  static void show(
    BuildContext context,
    IntakeEntity intake,
    DateTime day, {
    required ProfileStamp startedOn,
    RestoreIntakes restore = restoreDeletedIntakes,
  }) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null || !startedOn.isCurrent) return;
    final open = _open;
    final sameDay =
        open != null &&
        DateUtils.isSameDay(open.day, day) &&
        open.stamp.isCurrent;
    final entries = [if (sameDay) ...open.entries, intake];
    messenger.removeCurrentSnackBar();
    late final ScaffoldFeatureController<SnackBar, SnackBarClosedReason> bar;
    void close() {
      if (identical(_open?.bar, bar)) _open = null;
    }

    bar = messenger.showSnackBar(
      SnackBar(
        // An action keeps a bar up until dismissed: this one goes, so later
        // bars are not held behind it and a later delete starts its own.
        persist: false,
        content: Text(
          entries.length == 1
              ? 'Entry deleted'
              : '${entries.length} entries deleted',
        ),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () {
            // Restored: a delete during the bar's exit must not gather them.
            close();
            if (!startedOn.isCurrent) {
              // They belong to the profile left since: nothing is restored.
              messenger.showSnackBar(
                const SnackBar(
                  content: Text('Not restored: the profile changed.'),
                ),
              );
              return;
            }
            unawaited(restore(entries, day, startedOn));
          },
        ),
      ),
    );
    _open = (bar: bar, entries: entries, day: day, stamp: startedOn);
    unawaited(bar.closed.then((_) => close()));
  }
}
