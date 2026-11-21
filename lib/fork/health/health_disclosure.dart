import 'package:flutter/material.dart';
import 'package:opennutritracker/generated/l10n.dart';

/// The disclosure a health card puts up before its permission request, in the
/// shape of upstream's Workouts in one (`HealthDisclosureDialog`, #926): a
/// scrolling dialog, Cancel and Continue, no barrier dismissal.
class HealthDataDisclosure extends StatelessWidget {
  final String title;

  /// What is read or written, where it goes, and how to stop.
  final String body;

  const HealthDataDisclosure({
    super.key,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return AlertDialog(
      scrollable: true,
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(s.dialogCancelLabel),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(s.healthSyncDisclosureContinueAction),
        ),
      ],
    );
  }
}

/// True only on Continue: a back press returns null, which is a refusal.
Future<bool> confirmHealthDisclosure(
  BuildContext context, {
  required String title,
  required String body,
}) async =>
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => HealthDataDisclosure(title: title, body: body),
    ) ??
    false;
