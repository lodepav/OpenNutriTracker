import 'package:flutter/material.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';

/// How a nutrient stands against its goal.
enum GoalStanding {
  /// A target: green, however far along.
  toReach,

  /// A limit not passed: grey.
  under,

  /// A limit passed: red.
  over,
}

/// Where [perDay] stands against [goal]; a limit with no goal is not over.
GoalStanding goalStanding({
  required bool isLimit,
  required double perDay,
  required double? goal,
}) => !isLimit
    ? GoalStanding.toReach
    : perDay > (goal ?? double.infinity)
    ? GoalStanding.over
    : GoalStanding.under;

/// The bar colour for [standing], as [goalStandingKey] reads it.
Color goalStandingColor(
  GoalStanding standing,
  AppPalette palette,
  ColorScheme scheme,
) => switch (standing) {
  GoalStanding.toReach => palette.accent,
  GoalStanding.under => palette.textMuted,
  GoalStanding.over => scheme.error,
};

/// The key under every list coloured by [goalStandingColor].
const goalStandingKey = 'Green: reach it. Grey: stay under. Red: over a limit.';
