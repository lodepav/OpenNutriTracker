import 'dart:math' as math;

import 'package:flutter/material.dart';

/// An app bar's height for a title of up to two lines (A6): the usual
/// height, or at large text two lines of titleLarge (28 high) and a margin,
/// where scaling 56 alone lets the second line spill over the page.
double twoLineToolbarHeight(BuildContext context) {
  final scaler = MediaQuery.textScalerOf(context);
  return scaler.scale(10) > 13
      ? math.max(scaler.scale(kToolbarHeight), scaler.scale(28) * 2 + 16)
      : kToolbarHeight;
}
