import 'dart:math';

import 'package:opennutritracker/core/data/data_source/intake_data_source.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/utils/locator.dart';

/// How far back a log counts towards a food's place in the recents.
const recentsWindowDays = 90;

/// A log in another meal counts this much of one in the meal being added.
const otherMealWeight = 0.25;

/// A log's weight halves every this many days.
const recentsHalfLifeDays = 30;

/// How many hours from now's time of day a log may be and still count
/// in full; further off it fades towards [otherTimeWeight].
const sameTimeHours = 2.0;

/// A log at the opposite time of day counts this much of one logged now.
const otherTimeWeight = 0.4;

/// A log's weight by how near its time of day is to [now]'s (MacroFactor's
/// suggestions by time): oats logged at 7:00 lead at 7:30, not at 19:00.
/// A log at midnight was added to a day with no time picked, and counts
/// as halfway.
double timeOfDayWeight(DateTime log, DateTime now) {
  if (log.hour == 0 && log.minute == 0 && log.second == 0) {
    return (1 + otherTimeWeight) / 2;
  }
  final minutes = (log.hour * 60 + log.minute) - (now.hour * 60 + now.minute);
  final apart = min(minutes.abs(), 24 * 60 - minutes.abs()) / 60;
  final fade = exp(-pow(apart / (2 * sameTimeHours), 2));
  return otherTimeWeight + (1 - otherTimeWeight) * fade;
}

/// Upstream's key for one food in the recents (`getRecentlyAddedIntake`).
String recentKey(IntakeEntity intake) =>
    intake.meal.code ?? intake.meal.name ?? '';

/// [recents] (upstream's unique foods: custom meals, then newest) ranked
/// for [meal]: a food scores its logs in [history] over the last
/// [recentsWindowDays], each halving every [recentsHalfLifeDays], a log in
/// another meal counting [otherMealWeight], and each weighed by
/// [timeOfDayWeight]. So breakfast's oats come first at breakfast, and a
/// food not logged in the window keeps upstream's order below the rest.
List<IntakeEntity> rankRecentsForMeal(
  List<IntakeEntity> recents,
  List<IntakeEntity> history,
  IntakeTypeEntity meal,
  DateTime now,
) {
  final scores = <String, double>{};
  for (final log in history) {
    final ageDays = now.difference(log.dateTime).inHours / 24;
    if (ageDays < 0 || ageDays > recentsWindowDays) continue;
    final weight =
        (log.type == meal ? 1.0 : otherMealWeight) *
        timeOfDayWeight(log.dateTime, now) *
        pow(0.5, ageDays / recentsHalfLifeDays);
    scores.update(recentKey(log), (s) => s + weight, ifAbsent: () => weight);
  }
  final ranked = [...recents.indexed];
  // Stable: equal scores keep upstream's order.
  ranked.sort((a, b) {
    final byScore = (scores[recentKey(b.$2)] ?? 0).compareTo(
      scores[recentKey(a.$2)] ?? 0,
    );
    return byScore != 0 ? byScore : a.$1.compareTo(b.$1);
  });
  return [for (final (_, intake) in ranked) intake];
}

/// Seam S19: [recents] ranked for [meal], or as they are when no meal is
/// being added to (the recipe editor's search) or the history can't be read.
Future<List<IntakeEntity>> recentsForMeal(
  List<IntakeEntity> recents,
  IntakeTypeEntity? meal, {
  IntakeDataSource? source,
  DateTime? now,
}) async {
  if (meal == null || recents.length < 2) return recents;
  final at = now ?? DateTime.now();
  final since = at.subtract(const Duration(days: recentsWindowDays));
  try {
    final history = [
      for (final dbo
          in await (source ?? locator<IntakeDataSource>()).getAllIntakes())
        if (dbo.dateTime.isAfter(since)) IntakeEntity.fromIntakeDBO(dbo),
    ];
    return rankRecentsForMeal(recents, history, meal, at);
  } catch (_) {
    return recents;
  }
}
