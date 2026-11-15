import 'package:logging/logging.dart';
import 'package:opennutritracker/fork/bulk/photo_meal_memory.dart';
import 'package:opennutritracker/fork/bulk/photo_meal_memory_store.dart';
import 'package:opennutritracker/fork/leftovers/meal_groups.dart';

/// What one Log on the Log with AI screen wrote beside its entries, taken
/// back by its Undo once the entries are gone: the meal group of
/// [intakeIds] with its kept photo, and the photo meal [memory] record when
/// the Log added one, after [remembering] (the write of it) finishes.
/// False when either stays, so the bar can say so.
Future<bool> forgetBulkLog({
  required List<String> intakeIds,
  PhotoMealRecord? memory,
  Future<void>? remembering,
  required PhotoMealMemoryStore memoryStore,
  MealGroupStore? groups,
}) async {
  final log = Logger('BulkLogUndo');
  var all = true;
  try {
    await (groups ?? MealGroupStore()).forget(intakeIds);
  } catch (e, stackTrace) {
    log.warning('Forgetting a meal group failed', e, stackTrace);
    all = false;
  }
  if (memory != null) {
    try {
      await remembering;
      await memoryStore.remove(memory.loggedAt);
    } catch (e, stackTrace) {
      log.warning('Forgetting a photo meal failed', e, stackTrace);
      all = false;
    }
  }
  return all;
}
