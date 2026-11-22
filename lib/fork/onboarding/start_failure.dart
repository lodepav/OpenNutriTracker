import 'package:flutter/material.dart';
import 'package:logging/logging.dart';

/// Runs onboarding's Start (seam S466). A save that throws is logged and
/// said, as the goal planner's Start does, so the user knows the profile is
/// not saved and can tap Start again.
Future<void> startOrSay(
  BuildContext context,
  Future<void> Function() start,
) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    await start();
  } catch (error, stackTrace) {
    Logger('OnboardingScreen').severe('Start failed', error, stackTrace);
    messenger?.showSnackBar(
      const SnackBar(content: Text('Not saved. Try again.')),
    );
  }
}
