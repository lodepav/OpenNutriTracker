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

/// Says [text] with an Undo that takes [written] back off [day], as the
/// one-tap plus, a recipe's plus and the basket's "Log all" do.
void showLoggedBar(
  ScaffoldMessengerState messenger,
  String text, {
  required DateTime day,
  required List<IntakeEntity> written,
  required ProfileStamp stamp,
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
          final undone = await undoLogged((
            day: DateUtils.dateOnly(day),
            written: written,
          ), startedOn: stamp);
          refreshAfterLogging();
          if (!undone) {
            messenger.showSnackBar(
              const SnackBar(content: Text('Not undone: the profile changed.')),
            );
          }
        },
      ),
    ),
  );
}
