import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:opennutritracker/core/data/dbo/profile_dbo.dart';
import 'package:opennutritracker/core/utils/hive_db_provider.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_store.dart';
import 'package:opennutritracker/fork/backup/profile_wipe.dart';
import 'package:opennutritracker/fork/body/measurement_store.dart';
import 'package:opennutritracker/fork/health/weight_import.dart';
import 'package:opennutritracker/fork/photos/photo_store.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import '../../helpers/fake_hive_db_provider.dart';
import '../../helpers/hive_test_setup.dart';

/// Profiles' scoped boxes as plain boxes on disk.
class _Provider extends FakeHiveDBProvider {
  _Provider({required super.profileBox}) : super(activeProfileId: 'a');

  @override
  Future<Box<E>> openScopedBox<E>(String baseName, String boxSuffix) =>
      Hive.openBox<E>(HiveDBProvider.boxNameFor(baseName, boxSuffix));
}

class _Paths extends PathProviderPlatform with MockPlatformInterfaceMixin {
  final String root;

  _Paths(this.root);

  @override
  Future<String?> getApplicationDocumentsPath() async => root;
}

void main() {
  late Directory dir;
  late PathProviderPlatform paths;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('profile_wipe');
    paths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(dir.path);
    Hive.init(dir.path);
    registerHiveAdaptersOnce();
    final profiles = await Hive.openBox<ProfileDBO>('profiles');
    for (final id in ['a', 'b']) {
      await profiles.put(
        id,
        ProfileDBO(
          id: id,
          name: id,
          createdAt: DateTime(2026),
          boxSuffix: '_$id',
        ),
      );
    }
    locator.registerSingleton<HiveDBProvider>(_Provider(profileBox: profiles));
  });

  tearDown(() async {
    PathProviderPlatform.instance = paths;
    await locator.unregister<HiveDBProvider>();
    AdaptiveStore.settings.value = const AdaptiveSettings();
    await Hive.deleteFromDisk();
    await dir.delete(recursive: true);
  });

  test('a deleted profile\'s measurements, targets and Health Connect '
      'state go; another profile\'s stay', () async {
    final db = locator<HiveDBProvider>();
    for (final suffix in ['_a', '_b']) {
      for (final name in forkProfileBoxes) {
        await (await db.openScopedBox<dynamic>(name, suffix)).put('k', 1);
      }
    }
    await MeasurementStore().addDay(DateTime(2026, 5, 1), {
      BodyMetric.waist: 90,
    });
    await AdaptiveStore().save(const AdaptiveSettings(smoothedTrend: true));
    await AdaptiveStore().load();

    await clearForkProfileData();

    expect(await MeasurementStore().all(), isEmpty);
    expect(AdaptiveStore.settings.value.smoothedTrend, isFalse);
    for (final name in [AdaptiveStore.boxName, WeightImport.boxName]) {
      expect((await db.openScopedBox<dynamic>(name, '_a')).isEmpty, isTrue);
      expect((await db.openScopedBox<dynamic>(name, '_b')).get('k'), 1);
    }
  });

  test('a reset profile\'s progress photos go; an image another profile '
      'also holds, and another profile\'s own, stay', () async {
    final db = locator<HiveDBProvider>();
    PhotoStore store(String suffix) => PhotoStore(
      () => db.openScopedBox<dynamic>(AdaptiveStore.boxName, suffix),
      () async => dir,
    );
    final own = await store('_a').add(DateTime(2026, 5, 1), [1]);
    final theirs = await store('_b').add(DateTime(2026, 5, 2), [2]);
    // As a backup restored into both profiles leaves them.
    final shared = ProgressPhoto(id: 'shared', date: DateTime(2026, 5, 3));
    await store('_a').merge(
      [shared],
      {
        'shared': [3],
      },
    );
    await store('_b').merge([shared], {});
    final unrelated = File('${dir.path}/${PhotoStore.dir}/other.jpg');
    await unrelated.writeAsBytes([4]);

    await clearForkProfileData();

    expect(await store('_a').all(), isEmpty);
    expect(await (await store('_a').file(own)).exists(), isFalse);
    expect(await (await store('_b').file(theirs)).readAsBytes(), [2]);
    expect(await (await store('_b').file(shared)).readAsBytes(), [3]);
    expect(await unrelated.exists(), isTrue);
    expect(
      (await store('_b').all()).map((p) => p.id),
      unorderedEquals([theirs.id, 'shared']),
    );
  });

  test('deleting a profile takes all of its fork boxes', () {
    expect(HiveDBProvider.perProfileBoxNames, containsAll(forkProfileBoxes));
  });
}
