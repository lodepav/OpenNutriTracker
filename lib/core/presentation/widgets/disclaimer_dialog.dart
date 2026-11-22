import 'package:flutter/material.dart';
import 'package:opennutritracker/generated/l10n.dart';
// [fork] S595 fork English for stale strings
import 'package:opennutritracker/fork/onboarding/onboarding_copy.dart'
    as fork_copy;
// [/fork]

class DisclaimerDialog extends StatelessWidget {
  const DisclaimerDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true, // [fork] S467 disclaimer-scroll: long at 200% font
      title: Text(S.of(context).settingsDisclaimerLabel),
      // [fork] S595 disclaimer-you-tab: the tab is "You", not "Profile"
      // content: Text(S.of(context).disclaimerText),
      content: const Text(fork_copy.disclaimerText),
      // [/fork]
      actions: [
        // Not the shared OK label: dismissing this dialog records an
        // acknowledgement in ConfigEntity.hasAcceptedDisclaimer.
        TextButton(
          onPressed: () {
            Navigator.of(context).pop(true);
          },
          child: Text(S.of(context).disclaimerAcknowledgeLabel),
        ),
      ],
    );
  }
}
