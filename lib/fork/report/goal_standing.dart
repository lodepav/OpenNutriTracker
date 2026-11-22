import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/fork/trends/detail_stats.dart';

/// How a nutrient stands against its goal.
enum GoalStanding {
  /// A target met, or energy within [onTargetShare] of its goal: green.
  reached,

  /// A target not met yet: grey.
  toReach,

  /// A limit not passed: green, as a goal met is.
  under,

  /// A limit passed, or energy above its band: red.
  over,
}

/// Where [perDay] stands against [goal]. A [isBand] goal (energy, carbs,
/// fat) is reached within [onTargetShare] of it either way and over above
/// that, as the weekly report's energy reads. A band with no goal is not
/// over; a target or limit with none is not reached, so not green.
GoalStanding goalStanding({
  required bool isLimit,
  required double perDay,
  required double? goal,
  bool isBand = false,
}) {
  if (isLimit) {
    if (goal == null) return GoalStanding.toReach;
    return perDay > goal ? GoalStanding.over : GoalStanding.under;
  }
  if (goal == null || goal <= 0) return GoalStanding.toReach;
  if (isBand) {
    final share = (perDay - goal) / goal;
    return share > onTargetShare
        ? GoalStanding.over
        : share < -onTargetShare
        ? GoalStanding.toReach
        : GoalStanding.reached;
  }
  return perDay >= goal ? GoalStanding.reached : GoalStanding.toReach;
}

/// The bar colour for [standing], as [goalStandingKey] reads it.
Color goalStandingColor(
  GoalStanding standing,
  AppPalette palette,
  ColorScheme scheme,
) => switch (standing) {
  GoalStanding.reached || GoalStanding.under => palette.accent,
  GoalStanding.toReach => palette.textMuted,
  GoalStanding.over => scheme.error,
};

/// The word shown and spoken beside a bar, so its colour is not the only
/// sign; null where grey says it.
String? goalStandingWord(
  GoalStanding standing, {
  required bool isLimit,
  bool isBand = false,
}) => switch (standing) {
  GoalStanding.reached => isBand ? 'on target' : 'reached',
  GoalStanding.under => 'within limit',
  GoalStanding.over => isLimit ? 'over the limit' : 'over',
  GoalStanding.toReach => null,
};

/// The key under every list coloured by [goalStandingColor].
const goalStandingKey =
    'Green: reached, on target, or within a limit. Red: over. Grey: not '
    'there yet.';

/// The range a nutrient page averages over: "Oct 23 – Nov 21 · 30 days,
/// 28 logged", for [locale].
String nutrientRangeLine(
  DateTime first,
  DateTime last,
  int logged, {
  String? locale,
}) {
  // A range across New Year names both years, so a long one is not read
  // as within one.
  final format = first.year == last.year
      ? DateFormat.MMMd(locale)
      : DateFormat.yMMMd(locale);
  // UTC dates, so a clock change inside the range does not lose a day.
  final days =
      DateTime.utc(
        last.year,
        last.month,
        last.day,
      ).difference(DateTime.utc(first.year, first.month, first.day)).inDays +
      1;
  final span = days == 1
      ? format.format(first)
      : '${format.format(first)} – ${format.format(last)}';
  return '$span · $days day${days == 1 ? '' : 's'}, $logged logged';
}
