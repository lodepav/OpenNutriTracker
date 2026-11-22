import 'package:flutter/material.dart';
import 'package:opennutritracker/core/domain/entity/user_pal_entity.dart';
import 'package:opennutritracker/generated/l10n.dart';
// [fork] S592 fork English for stale strings
import 'package:opennutritracker/fork/onboarding/onboarding_copy.dart'
    as fork_copy;
// [/fork]

class SetPALCategoryDialog extends StatelessWidget {
  const SetPALCategoryDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return SimpleDialog(
      title: Text(S.of(context).selectPalCategoryLabel),
      children: [
        SimpleDialogOption(
          child: Text(S.of(context).palSedentaryLabel),
          onPressed: () {
            Navigator.pop(context, UserPALEntity.sedentary);
          },
        ),
        SimpleDialogOption(
          // [fork] S592 pal-labels: sentence case
          // child: Text(S.of(context).palLowLActiveLabel),
          child: const Text(fork_copy.palLowActiveLabel),
          // [/fork]
          onPressed: () {
            Navigator.pop(context, UserPALEntity.lowActive);
          },
        ),
        SimpleDialogOption(
          child: Text(S.of(context).palActiveLabel),
          onPressed: () {
            Navigator.pop(context, UserPALEntity.active);
          },
        ),
        SimpleDialogOption(
          // [fork] S592 pal-labels
          // child: Text(S.of(context).palVeryActiveLabel),
          child: const Text(fork_copy.palVeryActiveLabel),
          // [/fork]
          onPressed: () {
            Navigator.pop(context, UserPALEntity.veryActive);
          },
        ),
      ],
    );
  }
}
