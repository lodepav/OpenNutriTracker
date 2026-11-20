// Writes the fork's own state onto the data write_fixture.dart left in
// FIXTURE_DIR, and records it in fixture.json as `forkState`, so
// upgrade_test.dart reads each key back with later code against what this
// release wrote. fork/tools/upgrade_fixture.sh runs it from a release's own
// tree and never copies it into an older one: it may use today's code.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:opennutritracker/core/utils/hive_db_provider.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/fork/backup/auto_backup.dart';
import 'package:opennutritracker/fork/backup/storage_rescue.dart';
import 'package:opennutritracker/fork/bulk/photo_meal_memory_store.dart';

import '../backup/stored_fields.dart';
import '../helpers/fork_state.dart';
import 'boot_app.dart';

/// What a fixture cannot hold, by `box.key` or box: each is gone or
/// changed by the time any later code starts on it.
const notInFixture = {
  // Consumed by the first start after it is set (storage_rescue.dart).
  '${AutoBackup.boxName}.${StorageRescue.pendingKey}',
  // Its records expire after the days kept (photo_meal_memory.dart).
  PhotoMealMemoryStore.boxName,
};

void main() {
  test('write the fork state', () async {
    final out = Directory(Platform.environment['FIXTURE_DIR']!);
    await bootApp(out);
    final db = locator<HiveDBProvider>();
    await fillForkState(
      today: DateTime.now(),
      meal: MealEntity.fromMealDBO(db.intakeBox.values.first.meal),
      photos: out,
    );
    await (await openForkBox(
      AutoBackup.boxName,
    )).delete(StorageRescue.pendingKey);
    await (await openForkBox(PhotoMealMemoryStore.boxName)).clear();

    final fields = <String, Map<String, Object?>>{};
    for (final MapEntry(key: name, value: keys) in storedFields.entries) {
      final box = await openForkBox(name);
      fields[name] = {
        for (final key in keys.keys)
          if (!notInFixture.contains('$name.$key')) key: jsonOf(box.get(key)),
      };
    }
    final boxes = {
      for (final name in storedBoxes.keys)
        if (!notInFixture.contains(name))
          name: jsonOf((await openForkBox(name)).toMap()),
    };
    final unset = [
      for (final MapEntry(key: name, value: values) in fields.entries)
        for (final MapEntry(:key, :value) in values.entries)
          if (value == null) '$name.$key',
      for (final MapEntry(key: name, value: entries) in boxes.entries)
        if ((entries! as Map).isEmpty) name,
    ];
    expect(unset, isEmpty, reason: 'fillForkState must set these');
    await Hive.close();

    final file = File('${out.path}/fixture.json');
    final facts = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    facts['forkState'] = {
      'fields': fields,
      'boxes': boxes,
      'utcOffsetMinutes': DateTime.now().timeZoneOffset.inMinutes,
    };
    file.writeAsStringSync(jsonEncode(facts));
  }, timeout: const Timeout(Duration(minutes: 5)));
}
