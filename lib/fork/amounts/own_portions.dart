import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:logging/logging.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_portion_entity.dart';
import 'package:opennutritracker/features/add_meal/util/portion_unit.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_store.dart';

/// A portion the user named for a food, "slice" at 35 g, where the food
/// had none or none that fit (S195).
class OwnPortionEntity extends MealPortionEntity {
  const OwnPortionEntity({required super.label, required super.gramWeight})
    : super(localized: true);
}

/// The [meal]'s portions with the user's [own] after them: the amount
/// picker offers them all, and the converter scales by them as by any
/// portion, so the diary stores grams as before. A food with no portions
/// but a serving keeps the serving first, so `serving` still means it.
MealEntity withOwnPortions(MealEntity meal, List<OwnPortionEntity> own) {
  final base = meal.portions.where((p) => p is! OwnPortionEntity).toList();
  if (own.isEmpty && base.length == meal.portions.length) return meal;
  final serving = meal.scalableServingQuantity;
  return meal.withPortions([
    if (base.isNotEmpty)
      ...base
    else if (serving != null && own.isNotEmpty)
      MealPortionEntity(
        label: meal.servingSize?.trim().isNotEmpty == true
            ? meal.servingSize!
            : 'serving',
        gramWeight: serving,
        localized: meal.servingSizeIsLocalized,
      ),
    ...own,
  ]);
}

/// The key a remembered amount keeps for an own portion: its name, so the
/// page opens at it even when the food's other portions moved its index.
const ownUnitPrefix = 'own:';

/// The unit to remember for [unit] on [meal]: an own portion by its name.
String rememberedUnitOf(MealEntity meal, String unit) {
  final portion = _portionOf(meal, unit);
  return portion is OwnPortionEntity ? '$ownUnitPrefix${portion.label}' : unit;
}

/// A remembered [unit] back to the picker's unit on [meal]: an own portion
/// by its name, null when that portion is gone.
String? unitFromRemembered(MealEntity meal, String unit) {
  if (!unit.startsWith(ownUnitPrefix)) return unit;
  final label = unit.substring(ownUnitPrefix.length);
  final index = meal.portions.indexWhere(
    (p) => p is OwnPortionEntity && p.label == label,
  );
  return index < 0 ? null : portionUnit(index);
}

MealPortionEntity? _portionOf(MealEntity meal, String unit) {
  if (!isPortionUnit(unit) || meal.portions.isEmpty) return null;
  final index = effectivePortionIndex(unit);
  return index < meal.portions.length ? meal.portions[index] : null;
}

/// The user's own portions, per food and per profile, in the fork's box;
/// keyed by barcode or, without one, by name, as remembered amounts are.
class OwnPortions {
  static const _key = 'ownPortions';
  static final _log = Logger('OwnPortions');

  /// The one the app uses, for the active profile; tests swap it.
  static OwnPortions current = OwnPortions();

  final Future<Box<dynamic>> Function() _box;

  OwnPortions([Future<Box<dynamic>> Function()? box])
    : _box = box ?? AdaptiveStore.openActiveBox;

  static String? _id(MealEntity meal) {
    final code = meal.code;
    if (code != null && code.isNotEmpty) return 'code:$code';
    final name = meal.name;
    return name == null || name.isEmpty ? null : 'name:$name';
  }

  /// Empty for a food with none, or when the box cannot be read.
  Future<List<OwnPortionEntity>> of(MealEntity meal) async {
    final id = _id(meal);
    if (id == null) return const [];
    try {
      final all = (await _box()).get(_key, defaultValue: {}) as Map;
      final list = all[id];
      if (list is! List) return const [];
      return [
        for (final p in list.whereType<Map>())
          if (p['label'] is String && p['grams'] is num && p['grams'] > 0)
            OwnPortionEntity(
              label: p['label'] as String,
              gramWeight: (p['grams'] as num).toDouble(),
            ),
      ];
    } catch (error, stack) {
      _log.warning('Could not read own portions', error, stack);
      return const [];
    }
  }

  /// Saves [label] at [grams] for [meal], in place of one of that name.
  Future<void> add(MealEntity meal, String label, double grams) async {
    final id = _id(meal);
    final name = label.trim();
    if (id == null || name.isEmpty || grams <= 0) return;
    try {
      final box = await _box();
      final all = Map<dynamic, dynamic>.of(
        box.get(_key, defaultValue: {}) as Map,
      );
      final list = [
        for (final p in (all[id] as List?) ?? const [])
          if (p is Map && p['label'] != name) p,
        {'label': name, 'grams': grams},
      ];
      all[id] = list;
      await box.put(_key, all);
    } catch (error, stack) {
      _log.warning('Could not save the portion', error, stack);
    }
  }

  /// Removes [label] from [meal]'s own portions.
  Future<void> remove(MealEntity meal, String label) async {
    final id = _id(meal);
    if (id == null) return;
    try {
      final box = await _box();
      final all = Map<dynamic, dynamic>.of(
        box.get(_key, defaultValue: {}) as Map,
      );
      all[id] = [
        for (final p in (all[id] as List?) ?? const [])
          if (p is Map && p['label'] != label) p,
      ];
      await box.put(_key, all);
    } catch (error, stack) {
      _log.warning('Could not remove the portion', error, stack);
    }
  }
}
