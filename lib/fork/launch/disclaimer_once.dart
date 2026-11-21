import 'package:flutter/material.dart';
import 'package:opennutritracker/core/presentation/widgets/disclaimer_dialog.dart';

/// Home's first-launch disclaimer (S419): Home asks on every build while it
/// is not accepted, which queued a dialog on each; this shows one per Home,
/// closed only by its button, as the barrier and Back saved nothing.
class DisclaimerOnce {
  bool _shown = false;

  /// Shows the dialog after this frame unless it was already; [onAccepted]
  /// gets the button's answer.
  void show(BuildContext context, ValueChanged<bool> onAccepted) {
    if (_shown) return;
    _shown = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!context.mounted) return;
      final accepted = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        // Back would close it unsaved as well.
        builder: (context) =>
            const PopScope(canPop: false, child: DisclaimerDialog()),
      );
      if (accepted != null) onAccepted(accepted);
    });
  }
}
