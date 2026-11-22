import 'package:flutter/foundation.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:logging/logging.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';

final _log = Logger('CustomFoodModes');

/// Which custom foods were typed per serving. The simple form (#232) stores
/// one serving's figures in the per-100 fields, so the Custom foods list
/// must say "per serving" for those. Kept in a box of the fork's own, as
/// upstream's custom food library is shared by every profile; a food saved
/// before this has no entry and reads per 100 g. In the backup beside the
/// custom foods (`BackupExtras`), install-wide as they are.
class CustomFoodModes {
  static const boxName = 'fork_custom_food_modes';
  static const _key = 'perServing';

  /// Library keys ([keyOf]) of the foods saved per serving.
  static final perServing = ValueNotifier<Set<String>>(const {});

  static Future<void>? _loading;

  final Future<Box<dynamic>> Function() _box;

  CustomFoodModes([Future<Box<dynamic>> Function()? box])
    : _box = box ?? (() => Hive.openBox<dynamic>(boxName));

  /// The key the library knows [meal] by, as the Custom foods list reads it.
  static String keyOf(MealEntity meal) => meal.code ?? meal.name ?? '';

  /// Reads the box into [perServing] once.
  static Future<void> ensureLoaded() => _loading ??= CustomFoodModes().load();

  Future<void> load() async {
    try {
      final stored = (await _box()).get(_key, defaultValue: const []) as List;
      perServing.value = {for (final key in stored) '$key'};
    } catch (e) {
      // The list then reads per 100 g, as before; nothing is lost.
      _log.warning('Could not read custom food modes: $e');
    }
  }

  /// The keys stored, for a backup.
  Future<List<String>> stored() async => [
    for (final key in (await _box()).get(_key, defaultValue: const []) as List)
      '$key',
  ];

  /// After a restore wrote the custom foods keyed [restored]: each of them
  /// is per serving when [perServing] says so, as in the backup; other
  /// foods keep theirs.
  Future<void> restore(
    Iterable<String> perServing, {
    required Set<String> restored,
  }) async {
    final keys = {...await stored()}
      ..removeAll(restored)
      ..addAll(perServing);
    await (await _box()).put(_key, keys.toList());
    CustomFoodModes.perServing.value = keys;
  }

  /// Forgets every mark, when the custom foods themselves are cleared.
  Future<void> clear() async {
    await (await _box()).delete(_key);
    CustomFoodModes.perServing.value = const {};
  }

  /// Records whether the food saved under [key] was typed per serving.
  /// [previousKey] is the key it had before an edit changed its code or
  /// name, dropped so it can't mark another food later.
  Future<void> record(
    String key, {
    required bool perServing,
    String? previousKey,
  }) async {
    void apply(Set<String> keys) {
      if (previousKey != null) keys.remove(previousKey);
      perServing ? keys.add(key) : keys.remove(key);
    }

    var keys = {...CustomFoodModes.perServing.value};
    apply(keys);
    CustomFoodModes.perServing.value = {...keys};
    try {
      final box = await _box();
      keys = {
        for (final k in box.get(_key, defaultValue: const []) as List) '$k',
      };
      apply(keys);
      await box.put(_key, keys.toList());
    } catch (e) {
      // The food itself is saved; the label holds until the app restarts.
      apply(keys);
      _log.warning('Could not save the custom food mode: $e');
    }
    CustomFoodModes.perServing.value = keys;
  }
}
