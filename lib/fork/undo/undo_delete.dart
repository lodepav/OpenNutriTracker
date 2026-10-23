import 'dart:async';

import 'package:flutter/material.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/utils/tracked_day_lock.dart';
import 'package:opennutritracker/fork/basket/basket_ui.dart';
import 'package:opennutritracker/fork/copy/copy_entries.dart';

typedef RestoreIntakes =
    Future<void> Function(List<IntakeEntity> intakes, DateTime day);

/// Writes the entries back under the tracked-day lock, then refreshes Home
/// and the Diary.
Future<void> restoreDeletedIntakes(
  List<IntakeEntity> intakes,
  DateTime day,
) async {
  await withTrackedDayLockOnProfile(
    () => CopyEntries.fromLocator().restoreIntakes(intakes, day),
  );
  refreshAfterLogging();
}

/// "Entry deleted · Undo" after a diary entry is deleted (seam S52), in place
/// of upstream's confirmation dialog: the delete happens at once, and Undo
/// writes the entries back with their ids, so meal groups and the Health
/// Connect export see them unchanged. Deletes of one day that follow each
/// other while the bar is up (a meal's "Delete all") gather into one bar, and
/// its Undo brings all of them back.
class DeletedEntries {
  static List<IntakeEntity> _entries = const [];
  static DateTime? _day;
  static ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? _bar;

  static void show(
    BuildContext context,
    IntakeEntity intake,
    DateTime day, {
    RestoreIntakes restore = restoreDeletedIntakes,
  }) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    final previous = _day;
    final sameDay =
        _bar != null && previous != null && DateUtils.isSameDay(previous, day);
    final entries = _entries = [if (sameDay) ..._entries, intake];
    _day = day;
    messenger.removeCurrentSnackBar();
    final bar = _bar = messenger.showSnackBar(
      SnackBar(
        content: Text(
          entries.length == 1
              ? 'Entry deleted'
              : '${entries.length} entries deleted',
        ),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => unawaited(restore(entries, day)),
        ),
      ),
    );
    unawaited(
      bar.closed.then((_) {
        if (!identical(_bar, bar)) return;
        _bar = null;
        _entries = const [];
        _day = null;
      }),
    );
  }
}
