import 'package:flutter/material.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/utils/tracked_day_lock.dart';
import 'package:opennutritracker/fork/basket/basket_ui.dart'
    show refreshAfterLogging;
import 'package:opennutritracker/fork/copy/copy_entries.dart';

/// Takes back what a log wrote, in the profile it began in. Tests swap it.
Future<bool> Function(Placed placed, {required ProfileStamp startedOn})
undoLogged = (placed, {required startedOn}) =>
    CopyEntries.fromLocator().undoPlace(placed, startedOn: startedOn);

/// Takes [placed] back and then, once the entries are gone, what
/// [alsoUndo] takes back. Null when the profile changed and nothing was
/// undone; otherwise whether [alsoUndo] finished.
Future<bool?> takeBackLogged(
  Placed placed, {
  required ProfileStamp startedOn,
  Future<bool> Function()? alsoUndo,
}) async {
  if (!await undoLogged(placed, startedOn: startedOn)) return null;
  return alsoUndo == null ? true : await alsoUndo();
}

/// Says [text] with an Undo that takes [written] back off [day], as the
/// one-tap plus, a recipe's plus and the basket's "Log all" do; and then
/// [alsoUndo]'s part, false when it could not finish.
void showLoggedBar(
  ScaffoldMessengerState messenger,
  String text, {
  required DateTime day,
  required List<IntakeEntity> written,
  required ProfileStamp stamp,
  Future<bool> Function()? alsoUndo,
}) {
  messenger.removeCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      // An action keeps a bar up until dismissed: this one goes.
      persist: false,
      content: Text(text),
      action: SnackBarAction(
        label: 'Undo',
        onPressed: () async {
          final undone = await takeBackLogged(
            (day: DateUtils.dateOnly(day), written: written),
            startedOn: stamp,
            alsoUndo: alsoUndo,
          );
          refreshAfterLogging();
          if (undone == null) {
            messenger.showSnackBar(
              const SnackBar(content: Text('Not undone: the profile changed.')),
            );
          } else if (!undone) {
            messenger.showSnackBar(
              const SnackBar(
                content: Text(
                  "Undone, but the meal's grouping or photo record "
                  "couldn't be removed.",
                ),
              ),
            );
          }
        },
      ),
    ),
  );
}

/// Says a food was not added: the write [failed], or a profile switch
/// stopped it.
void showNotAdded(ScaffoldMessengerState messenger, {required bool failed}) {
  messenger
    ..removeCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(
          failed
              ? "Not added: it couldn't be saved."
              : 'Not added: the profile changed.',
        ),
      ),
    );
}
