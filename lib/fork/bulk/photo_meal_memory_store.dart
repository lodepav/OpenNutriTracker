import 'dart:convert';

import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:logging/logging.dart';
import 'package:opennutritracker/core/utils/hive_db_provider.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/fork/bulk/photo_meal_memory.dart';

/// The photo meal memory of the active profile, in an encrypted box of its
/// own as the fork's other per-profile stores are: one JSON string per
/// record, keyed by when it was logged, so no adapter. Never in a backup or
/// an export; emptied with the profile's data (`clearForkProfileData`) and
/// deleted with the profile (`HiveDBProvider.perProfileBoxNames`, S214).
class PhotoMealMemoryStore {
  static const boxName = 'ForkPhotoMealBox';

  final Future<Box<dynamic>> Function()? _box;

  /// The active profile's memory, or one over [box] in tests. Without the
  /// app's database (a widget test) it holds nothing and keeps nothing.
  PhotoMealMemoryStore([this._box]);

  Future<Box<dynamic>?> _open() async {
    if (_box case final box?) return box();
    if (!locator.isRegistered<HiveDBProvider>()) return null;
    final db = locator<HiveDBProvider>();
    final suffix = db.profileBox.get(db.activeProfileId)?.boxSuffix ?? '';
    return db.openScopedBox<dynamic>(boxName, suffix);
  }

  /// The records kept at [now], unordered; one that does not read is
  /// skipped.
  Future<List<PhotoMealRecord>> records({DateTime? now}) async {
    final box = await _open();
    if (box == null) return const [];
    final at = now ?? DateTime.now();
    final records = <PhotoMealRecord>[];
    for (final value in box.values) {
      try {
        final record = PhotoMealRecord.fromJson(
          jsonDecode(value as String) as Map,
        );
        if (!record.expiredAt(at)) records.add(record);
      } catch (_) {}
    }
    return records;
  }

  /// Keeps [record], and lets go of every record past the days kept.
  Future<void> add(PhotoMealRecord record, {DateTime? now}) async {
    final box = await _open();
    if (box == null) return;
    await box.put(
      record.loggedAt.microsecondsSinceEpoch.toString(),
      jsonEncode(record.toJson()),
    );
    await prune(box, now ?? DateTime.now());
  }

  /// Deletes the records past the days kept at [now], and any that does
  /// not read.
  static Future<void> prune(Box<dynamic> box, DateTime now) async {
    final old = <dynamic>[];
    for (final key in box.keys) {
      try {
        final json = jsonDecode(box.get(key) as String) as Map;
        if (PhotoMealRecord.fromJson(json).expiredAt(now)) old.add(key);
      } catch (_) {
        old.add(key);
      }
    }
    if (old.isNotEmpty) await box.deleteAll(old);
  }
}

/// Keeps [record] in [store]. The meal is already logged by then, so a
/// failure here only loses the memory, and is logged rather than reported.
Future<void> rememberPhotoMeal(
  PhotoMealRecord record,
  PhotoMealMemoryStore store,
) async {
  try {
    await store.add(record);
  } catch (e, stackTrace) {
    Logger(
      'PhotoMealMemory',
    ).warning('Keeping a photo meal failed', e, stackTrace);
  }
}
