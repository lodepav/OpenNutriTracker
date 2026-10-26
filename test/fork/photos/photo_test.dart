import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:opennutritracker/fork/photos/photo_card.dart';
import 'package:opennutritracker/fork/photos/photo_store.dart';

/// In memory, as real Hive hangs under `testWidgets`.
class _MemoryPhotos extends PhotoStore {
  final photos = <ProgressPhoto>[];
  var _next = 0;

  @override
  Future<List<ProgressPhoto>> all() async => [...photos];

  @override
  Future<File> file(ProgressPhoto photo) async => File(photo.relativePath);

  @override
  Future<ProgressPhoto> add(DateTime date, List<int> bytes) async {
    final photo = ProgressPhoto(id: 'p${_next++}', date: date);
    photos.add(photo);
    PhotoStore.changes.value++;
    return photo;
  }

  @override
  Future<void> remove(String id) async {
    photos.removeWhere((p) => p.id == id);
    PhotoStore.changes.value++;
  }
}

void main() {
  group('store', () {
    late Directory dir;
    late PhotoStore store;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('photos');
      Hive.init(dir.path);
      store = PhotoStore(
        () => Hive.openBox<dynamic>('photos'),
        () async => dir,
      );
    });

    tearDown(() async {
      await Hive.close();
      await dir.delete(recursive: true);
    });

    test('a photo is kept by day with its image, oldest first', () async {
      final later = await store.add(DateTime(2026, 10, 22, 18), [4]);
      final earlier = await store.add(DateTime(2026, 9, 1), [1, 2]);

      expect((await store.all()).map((p) => (p.id, p.date)), [
        (earlier.id, DateTime(2026, 9, 1)),
        (later.id, DateTime(2026, 10, 22)),
      ]);
      expect(await (await store.file(earlier)).readAsBytes(), [1, 2]);
    });

    test('removing a photo deletes its image', () async {
      final photo = await store.add(DateTime(2026, 10, 22), [1]);
      final image = await store.file(photo);

      await store.remove(photo.id);

      expect(await store.all(), isEmpty);
      expect(await image.exists(), isFalse);
    });
  });

  group('card', () {
    Future<_MemoryPhotos> pump(
      WidgetTester tester, {
      int photos = 0,
      List<int>? picked,
    }) async {
      final store = _MemoryPhotos();
      for (var i = 0; i < photos; i++) {
        store.photos.add(
          ProgressPhoto(id: 'old$i', date: DateTime(2026, 8 + i, 1)),
        );
      }
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProgressPhotosCard(store: store, pick: (_) async => picked),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return store;
    }

    testWidgets('a picked photo is added', (tester) async {
      final store = await pump(tester, picked: [1, 2, 3]);
      expect(find.byKey(const ValueKey('photo-compare')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('photo-add')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('photo-gallery')));
      await tester.pumpAndSettle();

      expect(store.photos, hasLength(1));
      expect(find.byKey(const ValueKey('photo-p0')), findsOneWidget);
    });

    testWidgets('a cancelled pick adds nothing', (tester) async {
      final store = await pump(tester);

      await tester.tap(find.byKey(const ValueKey('photo-add')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('photo-camera')));
      await tester.pumpAndSettle();

      expect(store.photos, isEmpty);
    });

    testWidgets('a photo opens and is deleted', (tester) async {
      final store = await pump(tester, photos: 1);

      await tester.tap(find.byKey(const ValueKey('photo-old0')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('photo-delete')));
      await tester.pumpAndSettle();
      // asked first: kept on Cancel
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(store.photos, hasLength(1));

      await tester.tap(find.byKey(const ValueKey('photo-old0')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('photo-delete')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('photo-delete-confirm')));
      await tester.pumpAndSettle();

      expect(store.photos, isEmpty);
      expect(find.byKey(const ValueKey('photo-old0')), findsNothing);
    });

    testWidgets('compare starts with the oldest and the newest', (
      tester,
    ) async {
      await pump(tester, photos: 3);

      await tester.tap(find.byKey(const ValueKey('photo-compare')));
      await tester.pumpAndSettle();

      expect(find.text('Compare photos'), findsOneWidget);
      expect(find.text('2026-08-01'), findsOneWidget);
      expect(find.text('2026-10-01'), findsOneWidget);
      expect(find.text('61 days apart'), findsOneWidget);
    });
  });
}
