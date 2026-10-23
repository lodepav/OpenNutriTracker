import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:logging/logging.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_store.dart';

/// An amount as typed on a food's page: the number and the unit picked.
typedef RememberedAmount = ({String unit, String quantity});

/// The amount last logged of each food, so its page opens at it
/// (MacroFactor's serving memory). Per profile, in the fork's box; keyed
/// by barcode or, without one, by name. Not in the backup: it rebuilds
/// itself with the next logs.
class RememberedAmounts {
  static const _key = 'amounts';

  /// Foods kept; the least recently logged go first.
  static const limit = 1000;
  static final _log = Logger('RememberedAmounts');

  /// The one the app uses, for the active profile; tests swap it.
  static RememberedAmounts current = RememberedAmounts();

  final Future<Box<dynamic>> Function() _box;

  RememberedAmounts([Future<Box<dynamic>> Function()? box])
    : _box = box ?? AdaptiveStore.openActiveBox;

  static String? _id(MealEntity meal) {
    final code = meal.code;
    if (code != null && code.isNotEmpty) return 'code:$code';
    final name = meal.name;
    return name == null || name.isEmpty ? null : 'name:$name';
  }

  /// Null for a food never logged, or when the box can't be read.
  Future<RememberedAmount?> of(MealEntity meal) async {
    final id = _id(meal);
    if (id == null) return null;
    try {
      final json = (await _box()).get(_key, defaultValue: {})[id];
      if (json is! Map) return null;
      return (
        unit: json['unit'] as String,
        quantity: json['quantity'] as String,
      );
    } catch (error, stack) {
      _log.warning('Could not read the remembered amount', error, stack);
      return null;
    }
  }

  /// Keeps [quantity] [unit] for [meal]; failures are logged, since a
  /// food is logged whether or not its amount is remembered.
  Future<void> remember(MealEntity meal, String unit, String quantity) async {
    final id = _id(meal);
    if (id == null) return;
    try {
      final box = await _box();
      final all = Map<dynamic, dynamic>.of(
        box.get(_key, defaultValue: {}) as Map,
      )..remove(id);
      // Insertion order is recency order: the oldest is first.
      while (all.length >= limit) {
        all.remove(all.keys.first);
      }
      all[id] = {'unit': unit, 'quantity': quantity};
      await box.put(_key, all);
    } catch (error, stack) {
      _log.warning('Could not remember the amount', error, stack);
    }
  }
}
