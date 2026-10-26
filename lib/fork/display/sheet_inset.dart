import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// The space a bottom sheet keeps clear at its foot: the keyboard while it
/// is up, else the system navigation bar, which edge-to-edge draws over
/// the sheet. A sheet padded only by the keyboard puts its last button
/// under the bar.
double sheetBottomInset(BuildContext context) => math.max(
  MediaQuery.viewInsetsOf(context).bottom,
  MediaQuery.viewPaddingOf(context).bottom,
);
