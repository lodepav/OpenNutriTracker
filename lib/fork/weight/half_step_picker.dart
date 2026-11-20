import 'dart:math';

import 'package:opennutritracker/features/profile/presentation/utils/profile_picker_bounds.dart';

/// Bounds for the target weight ruler so it steps by 0.5 (kg or lb) with
/// the given weight, rounded to the nearest half, as its centre item.
///
/// horizontal_picker places item i at min + (max - min) / divisions * i and
/// starts on item divisions ~/ 2, so the range is symmetric around the
/// centre: upstream's span on each side, cut short near upstream's floor.
({double min, double max, int divisions}) halfStepPickerBounds(
  double displayWeight,
  bool usesImperialUnits,
) {
  final centre = (displayWeight * 2).round() / 2;
  final upstreamMin = minSelectableWeight(centre, usesImperialUnits);
  final floor = (upstreamMin * 2).ceil() / 2;
  // At least one step each side: the picker asserts min < max.
  final stepsEachSide = max(1, ((centre - floor) * 2).floor());
  final half = stepsEachSide / 2;
  return (min: centre - half, max: centre + half, divisions: stepsEachSide * 2);
}
