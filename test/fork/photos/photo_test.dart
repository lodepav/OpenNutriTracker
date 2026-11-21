import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:opennutritracker/fork/photos/photo_card.dart';
import 'package:opennutritracker/fork/photos/photo_store.dart';

import '../../helpers/ux_checks.dart';

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

class _FailingPhotos extends _MemoryPhotos {
  @override
  Future<ProgressPhoto> add(DateTime date, List<int> bytes) async =>
      throw const FileSystemException('disk full');
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
      // From the gallery it asks the day, as it may not be today's.
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(store.photos, hasLength(1));
      expect(find.byKey(const ValueKey('photo-p0')), findsOneWidget);
    });

    Future<void> addFrom(WidgetTester tester, String source) async {
      await tester.tap(find.byKey(const ValueKey('photo-add')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey(source)));
      await tester.pumpAndSettle();
    }

    testWidgets('a gallery photo is dated today unless another day is asked', (
      tester,
    ) async {
      final store = await pump(tester, picked: [1]);
      final now = DateTime.now();

      await addFrom(tester, 'photo-gallery');
      expect(find.text('Photo taken on'), findsOneWidget);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(DateUtils.isSameDay(store.photos.single.date, now), isTrue);

      await addFrom(tester, 'photo-gallery');
      await tester.tap(find.byTooltip('Switch to input'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '03/05/2025');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(store.photos.last.date, DateTime(2025, 3, 5));
    });

    testWidgets('a gallery photo with the date cancelled adds nothing', (
      tester,
    ) async {
      final store = await pump(tester, picked: [1]);

      await addFrom(tester, 'photo-gallery');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(store.photos, isEmpty);
    });

    testWidgets('a camera photo is of today, without asking', (tester) async {
      final store = await pump(tester, picked: [1]);

      await addFrom(tester, 'photo-camera');

      expect(find.text('Photo taken on'), findsNothing);
      expect(
        DateUtils.isSameDay(store.photos.single.date, DateTime.now()),
        isTrue,
      );
    });

    testWidgets('a pick that fails says so', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProgressPhotosCard(
              store: _MemoryPhotos(),
              pick: (_) async => throw Exception('no permission'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await addFrom(tester, 'photo-camera');

      expect(find.text("Couldn't add the photo. Try again."), findsOneWidget);
    });

    testWidgets('a save that fails says so', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProgressPhotosCard(
              store: _FailingPhotos(),
              pick: (_) async => [1],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await addFrom(tester, 'photo-camera');

      expect(find.text("Couldn't add the photo. Try again."), findsOneWidget);
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

    testWidgets('at 200% text each date stays within its photo', (
      tester,
    ) async {
      final store = _MemoryPhotos()
        ..photos.addAll([
          ProgressPhoto(id: 'a', date: DateTime(2026, 11, 1)),
          ProgressPhoto(id: 'b', date: DateTime(2026, 11, 21)),
        ]);
      await pumpOnPhone(
        tester,
        ProgressPhotosCard(store: store, pick: (_) async => null),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(cutText(tester), isEmpty);
      for (final id in ['a', 'b']) {
        final tile = tester.getRect(find.byKey(ValueKey('photo-$id')));
        final image = tester.getRect(
          find.descendant(
            of: find.byKey(ValueKey('photo-$id')),
            matching: find.byType(Image),
          ),
        );
        final date = tester.getRect(
          find.descendant(
            of: find.byKey(ValueKey('photo-$id')),
            matching: find.byType(Text),
          ),
        );
        expect(date.left, greaterThanOrEqualTo(image.left - 0.5), reason: id);
        expect(date.right, lessThanOrEqualTo(image.right + 0.5), reason: id);
        expect(date.bottom, lessThanOrEqualTo(tile.bottom + 0.5), reason: id);
      }
    });

    testWidgets('compare at 200% text: two pickers inside the page gutter, '
        'each date in full in its own', (tester) async {
      await pumpOnPhone(tester, const SizedBox());
      Navigator.of(tester.element(find.byType(SizedBox).first)).push(
        MaterialPageRoute<void>(
          builder: (_) => ComparePhotosScreen(
            photos: [
              for (final (id, day) in [('a', 1), ('b', 21)])
                (
                  photo: ProgressPhoto(id: id, date: DateTime(2026, 11, day)),
                  file: File('missing-$id.jpg'),
                ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(cutText(tester), isEmpty);
      final width =
          tester.view.physicalSize.width / tester.view.devicePixelRatio;
      final left = tester.getRect(find.byKey(const ValueKey('compare-left')));
      final right = tester.getRect(find.byKey(const ValueKey('compare-right')));
      expect(left.left, greaterThanOrEqualTo(16));
      expect(right.right, lessThanOrEqualTo(width - 16));
      // Stacked, each a full row, so its date fits on one line.
      expect(right.top - left.bottom, greaterThanOrEqualTo(8));
      for (final text in ['Nov 1, 2026', 'Nov 21, 2026']) {
        final paragraph = tester.renderObject<RenderParagraph>(
          find.descendant(
            of: find.text(text).last,
            matching: find.byType(RichText),
          ),
        );
        final tops = {
          for (final box in paragraph.getBoxesForSelection(
            TextSelection(baseOffset: 0, extentOffset: text.length),
          ))
            box.top,
        };
        expect(tops, hasLength(1), reason: text);
      }
      // Outlined, so the two read as separate fields, not one underline.
      for (final key in ['compare-left', 'compare-right']) {
        final decorator = tester.widget<InputDecorator>(
          find.descendant(
            of: find.byKey(ValueKey(key)),
            matching: find.byType(InputDecorator),
          ),
        );
        expect(decorator.decoration.border, isA<OutlineInputBorder>());
      }
      for (final (key, text) in [
        ('compare-left', 'Nov 1, 2026'),
        ('compare-right', 'Nov 21, 2026'),
      ]) {
        final picker = tester.getRect(find.byKey(ValueKey(key)));
        final date = tester.getRect(
          find
              .descendant(
                of: find.byKey(ValueKey(key)),
                matching: find.text(text),
              )
              .last,
        );
        expect(picker.contains(date.topLeft), isTrue, reason: text);
        expect(picker.contains(date.bottomRight), isTrue, reason: text);
      }
      // Each photo sits at the top of the room left under its picker.
      for (final image in tester.widgetList<Image>(find.byType(Image))) {
        expect(image.alignment, Alignment.topCenter);
      }
    });

    for (final scale in [1.0, 1.15, 1.29]) {
      testWidgets(
        'compare at ${(scale * 100).round()}% text: each date on one line, '
        'side by side or stacked',
        (tester) async {
          await pumpOnPhone(tester, const SizedBox(), textScale: scale);
          Navigator.of(tester.element(find.byType(SizedBox).first)).push(
            MaterialPageRoute<void>(
              builder: (_) => ComparePhotosScreen(
                photos: [
                  for (final (id, day) in [('a', 1), ('b', 21)])
                    (
                      photo: ProgressPhoto(
                        id: id,
                        date: DateTime(2026, 11, day),
                      ),
                      file: File('missing-$id.jpg'),
                    ),
                ],
              ),
            ),
          );
          await tester.pumpAndSettle();
          final left = tester.getRect(
            find.byKey(const ValueKey('compare-left')),
          );
          final right = tester.getRect(
            find.byKey(const ValueKey('compare-right')),
          );
          // At the default size they sit side by side.
          if (scale == 1.0) {
            expect(right.left - left.right, greaterThanOrEqualTo(8));
          }
          // Side by side while the dates fit, else stacked.
          expect(
            right.left - left.right >= 8 || right.top - left.bottom >= 8,
            isTrue,
          );
          for (final text in ['Nov 1, 2026', 'Nov 21, 2026']) {
            final paragraph = tester.renderObject<RenderParagraph>(
              find.descendant(
                of: find.text(text).last,
                matching: find.byType(RichText),
              ),
            );
            final tops = {
              for (final box in paragraph.getBoxesForSelection(
                TextSelection(baseOffset: 0, extentOffset: text.length),
              ))
                box.top,
            };
            expect(tops, hasLength(1), reason: text);
          }
        },
      );
    }

    testWidgets("compare: the other side's date is left out, the menu within "
        'its field', (tester) async {
      await pumpOnPhone(tester, const SizedBox(), textScale: 1);
      Navigator.of(tester.element(find.byType(SizedBox).first)).push(
        MaterialPageRoute<void>(
          builder: (_) => ComparePhotosScreen(
            photos: [
              for (final (id, day) in [('a', 1), ('b', 21)])
                (
                  photo: ProgressPhoto(id: id, date: DateTime(2026, 11, day)),
                  file: File('missing-$id.jpg'),
                ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      final field = tester.getRect(find.byKey(const ValueKey('compare-left')));
      await tester.tap(find.byKey(const ValueKey('compare-left')));
      await tester.pumpAndSettle();

      // The right side's date: only on the right picker, not in the menu.
      expect(find.text('Nov 21, 2026'), findsOne);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('compare-right')),
          matching: find.text('Nov 21, 2026'),
        ),
        findsOne,
      );
      final menu = tester.getRect(
        find.ancestor(
          of: find.text('Nov 1, 2026').last,
          matching: find.byType(InkWell),
        ),
      );
      expect(menu.left, greaterThanOrEqualTo(field.left));
      expect(menu.right, lessThanOrEqualTo(field.right));
    });

    testWidgets('compare starts with the oldest and the newest', (
      tester,
    ) async {
      await pump(tester, photos: 3);

      await tester.tap(find.byKey(const ValueKey('photo-compare')));
      await tester.pumpAndSettle();

      expect(find.text('Compare photos'), findsOneWidget);
      expect(find.text('Aug 1, 2026'), findsOneWidget);
      expect(find.text('Oct 1, 2026'), findsOneWidget);
      expect(find.text('61 days apart'), findsOneWidget);
    });
  });
}
