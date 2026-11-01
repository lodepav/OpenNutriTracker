import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:opennutritracker/core/data/repository/profile_repository.dart';
import 'package:opennutritracker/core/domain/entity/profile_entity.dart';
import 'package:opennutritracker/core/domain/usecase/delete_profile_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/switch_profile_usecase.dart';
import 'package:opennutritracker/core/utils/hive_db_provider.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_store.dart';
import 'package:opennutritracker/fork/photos/photo_store.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

// Seam S191: a deleted profile's progress photos leave the disk with it.

class _Paths extends PathProviderPlatform with MockPlatformInterfaceMixin {
  final String root;

  _Paths(this.root);

  @override
  Future<String?> getApplicationDocumentsPath() async => root;
}

class _Db extends Fake implements HiveDBProvider {
  @override
  String activeProfileId = 'other';

  final deleted = <String>[];

  /// Whether the image was still there when the boxes went.
  bool Function() atBoxDelete = () => false;
  bool? imageAtBoxDelete;

  @override
  Future<Box<E>> openScopedBox<E>(String baseName, String boxSuffix) =>
      Hive.openBox<E>(HiveDBProvider.boxNameFor(baseName, boxSuffix));

  @override
  Future<void> closeScopedBox<E>(String baseName, String boxSuffix) async {
    final name = HiveDBProvider.boxNameFor(baseName, boxSuffix);
    if (Hive.isBoxOpen(name)) await Hive.box<E>(name).close();
  }

  @override
  Future<void> deleteProfileBoxes(String boxSuffix) async {
    imageAtBoxDelete = atBoxDelete();
    deleted.add(boxSuffix);
    await Hive.deleteBoxFromDisk(
      HiveDBProvider.boxNameFor(AdaptiveStore.boxName, boxSuffix),
    );
  }
}

class _Profiles extends Fake implements ProfileRepository {
  _Profiles(this.profiles);

  final List<ProfileEntity> profiles;

  @override
  List<ProfileEntity> getAllProfiles() => profiles;

  @override
  Future<void> deleteProfile(String id) async =>
      profiles.removeWhere((p) => p.id == id);
}

class _Switch extends Fake implements SwitchProfileUsecase {}

void main() {
  final gone = ProfileEntity(
    id: 'gone',
    name: 'Gone',
    createdAt: DateTime(2026),
    boxSuffix: '_gone',
  );
  final other = ProfileEntity(
    id: 'other',
    name: 'Other',
    createdAt: DateTime(2026),
    boxSuffix: '_other',
  );
  final idle = ProfileEntity(
    id: 'idle',
    name: 'Idle',
    createdAt: DateTime(2026),
    boxSuffix: '_idle',
  );

  late Directory root;
  late PathProviderPlatform paths;
  late _Db db;
  late _Profiles profiles;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('fork_delete_profile_');
    paths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(root.path);
    Hive.init(root.path);
    db = _Db();
    profiles = _Profiles([gone, other, idle]);
  });

  tearDown(() async {
    await Hive.close();
    PathProviderPlatform.instance = paths;
    await root.delete(recursive: true);
  });

  PhotoStore storeOf(ProfileEntity p) => PhotoStore(
    () => db.openScopedBox<dynamic>(AdaptiveStore.boxName, p.boxSuffix),
  );

  Future<void> delete(ProfileEntity p) =>
      DeleteProfileUsecase(profiles, db, _Switch()).deleteProfile(p);

  test(
    "deleting a profile deletes its photos' images, no one else's",
    () async {
      final mine = await storeOf(gone).add(DateTime(2026, 10, 1), [1]);
      final theirs = await storeOf(other).add(DateTime(2026, 10, 1), [2]);
      final mineFile = await storeOf(gone).file(mine);
      db.atBoxDelete = mineFile.existsSync;

      await delete(gone);

      expect(await mineFile.exists(), isFalse);
      expect(db.imageAtBoxDelete, isFalse);
      expect(await (await storeOf(other).file(theirs)).exists(), isTrue);
      expect(db.deleted, ['_gone']);
      expect(profiles.profiles.map((p) => p.id), ['other', 'idle']);
    },
  );

  test('an image another profile also holds, from one backup, stays', () async {
    final shared = await storeOf(gone).add(DateTime(2026, 10, 1), [1]);
    await storeOf(idle).merge([shared], const {});

    await delete(gone);

    final image = await storeOf(idle).file(shared);
    expect(await image.exists(), isTrue);
    expect((await storeOf(idle).all()).single.id, shared.id);
  });

  test('another profile, read for its index, is closed again', () async {
    await storeOf(gone).add(DateTime(2026, 10, 1), [1]);
    final name = HiveDBProvider.boxNameFor(AdaptiveStore.boxName, '_idle');

    await delete(gone);

    expect(Hive.isBoxOpen(name), isFalse);
    expect(
      Hive.isBoxOpen(
        HiveDBProvider.boxNameFor(AdaptiveStore.boxName, '_other'),
      ),
      isTrue,
    );
  });

  test('an index that cannot be read does not stop the delete', () async {
    final box = await db.openScopedBox<dynamic>(
      AdaptiveStore.boxName,
      gone.boxSuffix,
    );
    await box.put('progressPhotos', [
      {'id': '../../escape', 'date': '2026-10-01'},
    ]);

    await delete(gone);

    expect(db.deleted, ['_gone']);
    expect(profiles.profiles.map((p) => p.id), ['other', 'idle']);
  });

  test('deleting a photo another profile also holds keeps its image', () async {
    locator
      ..registerSingleton<HiveDBProvider>(db)
      ..registerSingleton<ProfileRepository>(profiles);
    addTearDown(locator.reset);
    final shared = await storeOf(other).add(DateTime(2026, 10, 1), [1]);
    final own = await storeOf(other).add(DateTime(2026, 10, 2), [2]);
    await storeOf(idle).merge([shared], const {});

    await storeOf(other).remove(shared.id);
    await storeOf(other).remove(own.id);

    expect(await (await storeOf(idle).file(shared)).exists(), isTrue);
    expect(await (await storeOf(other).file(own)).exists(), isFalse);
    expect(await storeOf(other).all(), isEmpty);
  });
}
