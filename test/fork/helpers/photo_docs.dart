import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/presentation/widgets/user_image_picker_tile.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// A 1x1 PNG: the photo already stored, and (a byte longer) the one the
/// picker gives.
final storedBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=',
);
final pickedBytes = [...storedBytes, 0];

class _Docs extends PathProviderPlatform with MockPlatformInterfaceMixin {
  final String path;
  _Docs(this.path);

  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

/// A documents directory of its own for a photo editor's test, with the
/// file the fake picker returns.
class PhotoDocs {
  final Directory root;
  final PathProviderPlatform _before;

  PhotoDocs._(this.root, this._before);

  static Future<PhotoDocs> create() async {
    final root = await Directory.systemTemp.createTemp('fork_photo_docs_');
    final docs = PhotoDocs._(root, PathProviderPlatform.instance);
    PathProviderPlatform.instance = _Docs(root.path);
    await File('${root.path}/picked.jpg').writeAsBytes(pickedBytes);
    return docs;
  }

  String get picked => '${root.path}/picked.jpg';

  /// A staged pick is still on disk (sync, so a wait condition can ask).
  bool get hasStaged => root
      .listSync(recursive: true)
      .any((e) => e.uri.pathSegments.last.contains('.staged'));

  Future<void> write(String relative, List<int> bytes) async {
    final file = File('${root.path}/$relative');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes);
  }

  Future<List<int>?> read(String relative) async {
    final file = File('${root.path}/$relative');
    return await file.exists() ? await file.readAsBytes() : null;
  }

  Future<List<String>> list(String dir) async {
    final d = Directory('${root.path}/$dir');
    if (!await d.exists()) return [];
    return [for (final e in await d.list().toList()) e.uri.pathSegments.last]
      ..sort();
  }

  Future<void> dispose() async {
    PathProviderPlatform.instance = _before;
    await root.delete(recursive: true);
  }
}

/// The image picker returns [path] (the encoder has no plugin in a test, so
/// the store copies it as it is).
void fakePicker(WidgetTester tester, String path) {
  const channel = MethodChannel('plugins.flutter.io/image_picker');
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    channel,
    (call) async => call.method == 'pickImage' ? path : null,
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      null,
    ),
  );
}

/// Pumps until [done] holds, with real time between pumps for file work
/// started in the test's fake zone; fails after [limit] of real time.
Future<void> settleWithIo(
  WidgetTester tester,
  bool Function() done, {
  Duration limit = const Duration(seconds: 20),
}) async {
  final watch = Stopwatch()..start();
  while (!done()) {
    if (watch.elapsed > limit) fail('settleWithIo: not done after $limit');
    // A pump with no duration leaves the fake clock, and a route's
    // transition, where they are.
    await tester.pump(const Duration(milliseconds: 50));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
  }
  await tester.pumpAndSettle();
}

/// The photo the picker tile shows.
String? tilePhoto(WidgetTester tester, Finder tile) => tester
    .widget<UserImagePickerTile>(
      find.ancestor(of: tile, matching: find.byType(UserImagePickerTile)),
    )
    .imagePath;

/// Opens the picker tile's sheet, taps [action] in it, and waits until the
/// tile shows another photo or the screen says the pick failed.
Future<void> choose(WidgetTester tester, Finder tile, String action) async {
  await tester.ensureVisible(tile);
  await tester.pumpAndSettle();
  final before = tilePhoto(tester, tile);
  await tester.tap(tile);
  await tester.pumpAndSettle();
  await tester.tap(find.text(action));
  await settleWithIo(
    tester,
    () =>
        tilePhoto(tester, tile) != before ||
        find.text('Could not add the photo').evaluate().isNotEmpty,
  );
}

/// System Back, and Discard when the screen asks; waits until the editor is
/// gone and its staged file with it.
Future<void> backAndDiscard(WidgetTester tester, PhotoDocs docs) async {
  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
  final discard = find.widgetWithText(FilledButton, 'Discard');
  if (discard.evaluate().isNotEmpty) {
    await tester.tap(discard);
  }
  await settleWithIo(tester, () => editorClosed(tester) && !docs.hasStaged);
}

/// The editor is up with its picker tile.
bool editorOpen(WidgetTester tester) =>
    find.byType(UserImagePickerTile).evaluate().isNotEmpty;

/// Only the test's home route is left.
bool editorClosed(WidgetTester tester) =>
    !tester.state<NavigatorState>(find.byType(Navigator).first).canPop();
