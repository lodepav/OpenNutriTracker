import 'dart:async';

import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:logging/logging.dart';
import 'package:opennutritracker/core/data/dbo/favourite_meal_dbo.dart';
import 'package:opennutritracker/core/data/dbo/intake_dbo.dart';
import 'package:opennutritracker/core/data/dbo/meal_dbo.dart';
import 'package:opennutritracker/core/utils/hive_db_provider.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_store.dart';

/// The three dishes that moved to ids of their own.
///
/// openbite-v0.9.0 to v0.10.1 shipped chicken cutlets on Caesar wrap's id,
/// and from v0.9.1 pork cutlets on rassolnik's and chłodnik on Olivier
/// salad's. The bundled table now gives each its own id
/// (`test/fork/food/dish_ids_test.dart`), so what a phone saved for them
/// still carries the shared id: the diary's entries, which the recents,
/// the search's logged-first order and the remembered amounts group by
/// it; the favourites, whose key is built from it; the search cache,
/// which keeps one entry per id; and the meal plan, which logs its
/// snapshot as a new entry.
///
/// The stored name tells the two dishes on one id apart: every release
/// stored the table's name, and the three names never changed between
/// them. Only the leading title is compared (before the first comma or
/// bracket, any case), so the aliases in brackets may differ.
const movedDishIds = <String, ({List<String> titles, String to})>{
  // "Chicken cutlets, fried (cāļa kotletes, …)", v0.9.0 to v0.10.1.
  '30000024': (titles: ['chicken cutlets'], to: '30000047'),
  // "Pork cutlets, fried (cūkgaļas kotletes, …)", v0.9.1 to v0.10.1.
  '30000025': (titles: ['pork cutlets'], to: '30000048'),
  // "Chłodnik, cold beet soup with kefir (chlodnik, …)", v0.9.1 to v0.10.1.
  '30000026': (titles: ['chłodnik', 'chlodnik'], to: '30000049'),
};

/// The table's source of the fork's dishes (S72).
const _dishSource = 'fork_dishes';

final _log = Logger('MovedDishIds');

/// The new id of a dish stored under [code] with [name], or null when it
/// is not one of the moved three: another id, or the dish that kept the
/// id (Caesar wrap, rassolnik, Olivier salad), or any other name.
String? movedDishCode(String? code, String? name) {
  final moved = movedDishIds[code?.trim()];
  if (moved == null || name == null) return null;
  final title = name.split(RegExp('[,(]')).first.trim().toLowerCase();
  return moved.titles.contains(title) ? moved.to : null;
}

bool _isTableRow(MealSourceDBO source, String? backendSource) =>
    source == MealSourceDBO.fdc &&
    (backendSource == null || backendSource == _dishSource);

/// The same [meal] when it is not a moved dish, otherwise a copy under the
/// new id. Nothing else changes: the name, nutrients and serving are what
/// was saved.
MealDBO movedDishMeal(MealDBO meal) {
  if (!_isTableRow(meal.source, meal.backendSource)) return meal;
  final to = movedDishCode(meal.code, meal.name);
  if (to == null) return meal;
  return MealDBO(
    code: to,
    name: meal.name,
    brands: meal.brands,
    thumbnailImageUrl: meal.thumbnailImageUrl,
    mainImageUrl: meal.mainImageUrl,
    url: meal.url,
    mealQuantity: meal.mealQuantity,
    mealUnit: meal.mealUnit,
    servingQuantity: meal.servingQuantity,
    servingUnit: meal.servingUnit,
    servingSize: meal.servingSize,
    nutriments: meal.nutriments,
    source: meal.source,
    localImagePath: meal.localImagePath,
    detailed: meal.detailed,
    backendSource: meal.backendSource,
    machineTranslatedName: meal.machineTranslatedName,
    dataVersion: meal.dataVersion,
  );
}

/// The same [intake] when its meal did not move, otherwise a copy carrying
/// the moved meal; amount, unit, meal and date are kept.
IntakeDBO movedDishIntake(IntakeDBO intake) {
  final meal = movedDishMeal(intake.meal);
  if (identical(meal, intake.meal)) return intake;
  return IntakeDBO(
    id: intake.id,
    unit: intake.unit,
    amount: intake.amount,
    type: intake.type,
    meal: meal,
    dateTime: intake.dateTime,
  );
}

/// The same planned food (`PlannedFood.toJson`) when its meal did not
/// move, otherwise a copy with the meal's `code` rewritten.
Map<dynamic, dynamic> movedDishPlanned(Map<dynamic, dynamic> json) {
  final meal = json['meal'];
  if (meal is! Map) return json;
  if (meal['source'] != MealSourceDBO.fdc.name) return json;
  final backendSource = meal['backendSource'];
  if (backendSource != null && backendSource != _dishSource) return json;
  final to = movedDishCode(meal['code'] as String?, meal['name'] as String?);
  if (to == null) return json;
  return {
    ...json,
    'meal': {...meal, 'code': to},
  };
}

/// Moves what a phone saved for the three dishes to their new ids, once:
/// the shared search cache once per install, and each profile's diary,
/// favourites and meal plan once per profile, when it is first active on
/// this build. A flag is set only after its stores are written, so a pass
/// cut short runs again; a second pass finds nothing to move.
///
/// Not moved, as nothing stored tells the two dishes apart: the
/// remembered amounts and own portions (`lib/fork/amounts/`), kept by id
/// alone.
class MovedDishIds {
  /// In the install's `fork_flags` box, beside the starter recipes' flag.
  static const installFlag = 'movedDishIds';

  /// In each profile's fork box (`AdaptiveStore`).
  static const profileFlag = 'movedDishIds';

  /// `PlanStore`'s key in the same box.
  static const planKey = 'plannedFoods';

  final Future<Box<bool>> Function() _installFlags;
  final Future<Box<dynamic>> Function() _profileBox;
  final Box<IntakeDBO> Function() _intakes;
  final Box<FavouriteMealDBO> Function() _favourites;
  final Box<MealDBO> Function() _searchCache;
  final Box<int> Function() _searchCacheTimestamps;

  MovedDishIds({
    required Future<Box<bool>> Function() installFlags,
    required Future<Box<dynamic>> Function() profileBox,
    required Box<IntakeDBO> Function() intakes,
    required Box<FavouriteMealDBO> Function() favourites,
    required Box<MealDBO> Function() searchCache,
    required Box<int> Function() searchCacheTimestamps,
  }) : _installFlags = installFlags,
       _profileBox = profileBox,
       _intakes = intakes,
       _favourites = favourites,
       _searchCache = searchCache,
       _searchCacheTimestamps = searchCacheTimestamps;

  factory MovedDishIds.fromLocator() {
    final db = locator<HiveDBProvider>();
    return MovedDishIds(
      installFlags: () => Hive.openBox<bool>('fork_flags'),
      profileBox: AdaptiveStore.openActiveBox,
      intakes: () => db.intakeBox,
      favourites: () => db.favouriteMealBox,
      searchCache: () => db.cachedOffMealBox,
      searchCacheTimestamps: () => db.cachedOffMealTimestampsBox,
    );
  }

  /// Seam S6: runs for the active profile, and again for each profile
  /// switched to. Never throws.
  static Future<void> start() async {
    try {
      await MovedDishIds.fromLocator().run();
      locator<HiveDBProvider>().addListener(
        () => unawaited(MovedDishIds.fromLocator().run()),
      );
    } catch (error, stack) {
      _log.warning('Dish ids not moved', error, stack);
    }
  }

  /// Never throws: a start-up chore must not stop the app starting.
  Future<void> run() async {
    await _once('the search cache', _installFlags, installFlag, _moveCache);
    await _once('this profile', _profileBox, profileFlag, _moveProfile);
  }

  Future<void> _once<T>(
    String what,
    Future<Box<T>> Function() flags,
    String flag,
    Future<int> Function() move,
  ) async {
    try {
      final box = await flags();
      if (box.get(flag) == true) return;
      final moved = await move();
      await box.put(flag, true as T);
      if (moved > 0) _log.info('Moved $moved entries of $what to new dish ids');
    } catch (error, stack) {
      _log.warning('Dish ids of $what not moved', error, stack);
    }
  }

  Future<int> _moveProfile() async =>
      await _moveIntakes() + await _moveFavourites() + await _movePlan();

  Future<int> _moveIntakes() async {
    final box = _intakes();
    final moved = <dynamic, IntakeDBO>{
      for (final entry in box.toMap().entries)
        if (movedDishIntake(entry.value) case final fixed
            when !identical(fixed, entry.value))
          entry.key: fixed,
    };
    if (moved.isNotEmpty) await box.putAll(moved);
    return moved.length;
  }

  /// A favourite's key is built from its id, so a moved one goes under the
  /// new key; one already there is kept.
  Future<int> _moveFavourites() async {
    final box = _favourites();
    var count = 0;
    for (final entry in box.toMap().entries) {
      final meal = movedDishMeal(entry.value.meal);
      if (identical(meal, entry.value.meal)) continue;
      final key = FavouriteMealDBO.keyFor(meal.source, meal.code, meal.name);
      if (!box.containsKey(key)) {
        await box.put(
          key,
          FavouriteMealDBO(meal: meal, addedAt: entry.value.addedAt),
        );
      }
      await box.delete(entry.key);
      count++;
    }
    return count;
  }

  Future<int> _movePlan() async {
    final box = await _profileBox();
    final planned = box.get(planKey);
    if (planned is! List) return 0;
    var count = 0;
    final fixed = <dynamic>[];
    for (final json in planned) {
      final moved = json is Map ? movedDishPlanned(json) : json;
      if (!identical(moved, json)) count++;
      fixed.add(moved);
    }
    if (count > 0) await box.put(planKey, fixed);
    return count;
  }

  /// The cache keeps one entry per id, with its "last touched" time under
  /// the id; the time goes with a moved entry.
  Future<int> _moveCache() async {
    final box = _searchCache();
    final times = _searchCacheTimestamps();
    final moved = <dynamic, MealDBO>{};
    for (final entry in box.toMap().entries) {
      final meal = movedDishMeal(entry.value);
      if (!identical(meal, entry.value)) moved[entry.key] = meal;
    }
    if (moved.isEmpty) return 0;
    await box.putAll(moved);
    final stillHeld = {for (final meal in box.values) meal.code};
    for (final meal in moved.values) {
      final from = movedDishIds.entries
          .firstWhere((e) => e.value.to == meal.code)
          .key;
      final time = times.get(from);
      if (time == null) continue;
      if (!times.containsKey(meal.code)) await times.put(meal.code!, time);
      if (!stillHeld.contains(from)) await times.delete(from);
    }
    return moved.length;
  }
}
