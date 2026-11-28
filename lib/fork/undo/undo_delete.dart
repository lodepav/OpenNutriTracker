import 'dart:async';

import 'package:flutter/material.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/utils/tracked_day_lock.dart';
import 'package:opennutritracker/fork/basket/basket_ui.dart';
import 'package:opennutritracker/fork/copy/copy_entries.dart';

/// How long an Undo bar stays up. It always goes, even under a screen reader:
/// accessibleNavigation also turns on for autofill services, and a bar that
/// never goes looks stuck.
const undoBarTime = Duration(seconds: 5);

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

/// "Food deleted · Undo" after a diary entry is deleted (seam S52), in place
/// of upstream's confirmation dialog: the delete happens at once, and Undo
/// writes the entries back with their ids, so meal groups and the Health
/// Connect export see them unchanged. Deletes of one day that follow each
/// other within the bar's time (a meal's "Delete all") gather into one bar,
/// and its Undo brings all of them back. [startedOn] is taken before the delete:
/// where the profile changed since, the delete did not happen there or the
/// entry belongs to another profile, so no bar is shown.
class DeletedEntries {
  /// The bar on screen and what its Undo restores; null once it has gone or
  /// its time is up.
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

    final name = entries.length == 1 ? entries.single.meal.name : null;
    bar = messenger.showSnackBar(
      SnackBar(
        persist: false,
        duration: undoBarTime,
        content: _Gathering(
          onEnd: close,
          child: Text(
            // the food by name, so a wrong swipe shows which one went
            entries.length == 1
                ? '${name ?? 'Food'} deleted'
                : '${entries.length} foods deleted',
          ),
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

/// Ends the bar's gathering after its time: the timer lives with the bar's
/// content, so it goes when the bar does.
class _Gathering extends StatefulWidget {
  final VoidCallback onEnd;
  final Widget child;

  const _Gathering({required this.onEnd, required this.child});

  @override
  State<_Gathering> createState() => _GatheringState();
}

class _GatheringState extends State<_Gathering> {
  late final Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(undoBarTime, widget.onEnd);
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
