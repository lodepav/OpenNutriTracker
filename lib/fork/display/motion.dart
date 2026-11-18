import 'package:flutter/widgets.dart';

/// Whether the system's Remove animations setting is on, so a change shows
/// at once instead of moving (WCAG 2.3.3).
bool animationsOff(BuildContext context) =>
    MediaQuery.disableAnimationsOf(context);

/// [duration], or none while animations are off.
Duration motionDuration(BuildContext context, Duration duration) =>
    animationsOff(context) ? Duration.zero : duration;
