import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:logging/logging.dart';
import 'package:opennutritracker/core/data/data_source/intake_data_source.dart';
import 'package:opennutritracker/core/data/dbo/intake_dbo.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_store.dart';

/// An amount as typed on a food's page: the number and the unit picked.
typedef RememberedAmount = ({String unit, String quantity});

/// The amount last logged of each food, so its page opens at it
/// (MacroFactor's serving memory). Per profile, in the fork's box; keyed
/// by barcode or, without one, by name. Not in the backup: it rebuilds
/// itself with the next logs. A food with nothing remembered, because it
/// came in by import, copy or an edit, opens at the amount of its latest
/// entry in grams or millilitres.
class RememberedAmounts {
  static const _key = 'amounts';

  /// Foods kept; the least recently logged go first.
  static const limit = 1000;
  static final _log = Logger('RememberedAmounts');

  /// The one the app uses, for the active profile; tests swap it.
  static RememberedAmounts current = RememberedAmounts();

  final Future<Box<dynamic>> Function() _box;
  final Future<List<IntakeDBO>> Function() _history;

  RememberedAmounts([
    Future<Box<dynamic>> Function()? box,
    Future<List<IntakeDBO>> Function()? history,
  ]) : _box = box ?? AdaptiveStore.openActiveBox,
       _history =
           history ?? (() => locator<IntakeDataSource>().getAllIntakes());

  static String? _id(MealEntity meal) {
    final code = meal.code;
    if (code != null && code.isNotEmpty) return 'code:$code';
    final name = meal.name;
    return name == null || name.isEmpty ? null : 'name:$name';
  }

  /// Null for a food never logged, or when neither the box nor the diary
  /// can be read.
  Future<RememberedAmount?> of(MealEntity meal) async {
    final id = _id(meal);
    if (id == null) return null;
    try {
      final json = (await _box()).get(_key, defaultValue: {})[id];
      if (json is! Map) return _latestEntry(id);
      return (
        unit: json['unit'] as String,
        quantity: json['quantity'] as String,
      );
    } catch (error, stack) {
      _log.warning('Could not read the remembered amount', error, stack);
      return null;
    }
  }

  /// The latest diary entry of the food [id] names, when its amount is in
  /// grams or millilitres: an entry in servings or ounces may be stored
  /// in another unit than it reads.
  Future<RememberedAmount?> _latestEntry(String id) async {
    try {
      IntakeDBO? latest;
      for (final dbo in await _history()) {
        if (!const {'g', 'ml', 'g/ml'}.contains(dbo.unit)) continue;
        if (dbo.amount <= 0) continue;
        final code = dbo.meal.code;
        final name = dbo.meal.name;
        final dboId = code != null && code.isNotEmpty
            ? 'code:$code'
            : (name == null || name.isEmpty ? null : 'name:$name');
        if (dboId != id) continue;
        if (latest == null || dbo.dateTime.isAfter(latest.dateTime)) {
          latest = dbo;
        }
      }
      if (latest == null) return null;
      final quantity = latest.amount
          .toStringAsFixed(1)
          .replaceFirst(RegExp(r'\.0$'), '');
      return (unit: latest.unit, quantity: quantity);
    } catch (error, stack) {
      _log.warning('Could not read the latest entry', error, stack);
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
