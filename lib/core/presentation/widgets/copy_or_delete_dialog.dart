import 'package:flutter/material.dart';
import 'package:opennutritracker/generated/l10n.dart';

class CopyOrDeleteDialog extends StatelessWidget {
  // [fork] S24 copy-anywhere: an entry's copy opens a day and meal picker,
  // so it is "Copy…", without the text about copying to today
  final bool toPicker;

  const CopyOrDeleteDialog({super.key, this.toPicker = false});
  // [/fork]

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(S.of(context).copyOrDeleteTimeDialogTitle),
      // [fork] S24 copy-anywhere
      content: toPicker
          ? null
          : Text(S.of(context).copyOrDeleteTimeDialogContent),
      // [/fork]
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop(true);
          },
          // [fork] S24 copy-anywhere; S81 a11y-labels: sentence case, as
          // every other dialog
          child: Text(
            toPicker
                ? '${S.of(context).copyActionLabel}…'
                : S.of(context).dialogCopyLabel,
          ),
          // [/fork]
        ),
        TextButton(
          onPressed: () {
            Navigator.of(context).pop(false);
          },
          // [fork] S81 a11y-labels
          child: Text(S.of(context).dialogDeleteLabel),
          // [/fork]
        ),
      ],
    );
  }
}
