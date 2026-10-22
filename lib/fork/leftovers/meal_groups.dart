import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:logging/logging.dart';

/// The entries one bulk-add save wrote together (D14): what the leftovers
/// of "the whole meal" are taken from. Upstream writes each row as its own
/// intake with nothing joining them, so the fork keeps the join.
class MealGroup {
  final List<String> intakeIds;
  final DateTime loggedAt;

  const MealGroup(this.intakeIds, this.loggedAt);

  Map<String, Object> toJson() => {
    'intakeIds': intakeIds,
    'loggedAt': loggedAt.toIso8601String(),
  };

  static MealGroup fromJson(Map<dynamic, dynamic> json) => MealGroup(
    (json['intakeIds'] as List).cast<String>(),
    DateTime.parse(json['loggedAt'] as String),
  );
}

/// Groups in a box of the fork's own, keyed by each member's intake id so
/// any entry finds its group in one read. Plain maps, so no adapter and no
/// change to upstream's boxes or their backup format.
class MealGroupStore {
  static const boxName = 'fork_meal_groups';

  final Future<Box<Map>> Function() _box;

  MealGroupStore([Future<Box<Map>> Function()? box])
    : _box = box ?? (() => Hive.openBox<Map>(boxName));

  /// Records [intakeIds] as one meal. A single entry is not a group: its
  /// own edit already covers it.
  Future<void> record(List<String> intakeIds, DateTime loggedAt) async {
    if (intakeIds.length < 2) return;
    final json = MealGroup(intakeIds, loggedAt).toJson();
    await (await _box()).putAll({for (final id in intakeIds) id: json});
  }

  Future<MealGroup?> groupOf(String intakeId) async {
    final json = (await _box()).get(intakeId);
    return json == null ? null : MealGroup.fromJson(json);
  }
}

/// Seam S8: records one bulk-add save's entries as a meal. The entries are
/// already written by then, so a failure here only loses the grouping and
/// is logged rather than reported as a failed save.
Future<void> recordMealGroup(
  List<String> intakeIds, {
  MealGroupStore? store,
}) async {
  try {
    await (store ?? MealGroupStore()).record(intakeIds, DateTime.now());
  } catch (e, stackTrace) {
    Logger(
      'MealGroups',
    ).warning('Recording a meal group failed', e, stackTrace);
  }
}
