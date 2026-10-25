import 'package:flutter/material.dart';
import 'package:opennutritracker/generated/l10n.dart';

/// Asks before Back leaves a screen whose [pending] work would be lost
/// (seam S90, "Add several items"). It draws nothing, so it can sit in any
/// list of children; a PopScope speaks for its whole route.
class DiscardGuard extends StatelessWidget {
  final bool pending;

  const DiscardGuard({super.key, required this.pending});

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !pending,
    onPopInvokedWithResult: (didPop, _) async {
      if (didPop) return;
      final s = S.of(context);
      final discard = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: Text(s.discardChangesTitle),
          content: Text(s.discardChangesContent),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialog).pop(false),
              child: Text(s.dialogCancelLabel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialog).pop(true),
              child: Text(s.discardChangesConfirmLabel),
            ),
          ],
        ),
      );
      if (discard == true && context.mounted) Navigator.of(context).pop();
    },
    child: const SizedBox.shrink(),
  );
}
