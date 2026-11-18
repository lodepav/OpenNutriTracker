import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/fork/display/sized_file_image.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _Paths extends PathProviderPlatform with MockPlatformInterfaceMixin {
  final String root;

  _Paths(this.root);

  @override
  Future<String?> getApplicationDocumentsPath() async => root;
}

void main() {
  late Directory root;
  late PathProviderPlatform before;

  setUp(() {
    root = Directory.systemTemp.createTempSync('fork_evict_');
    before = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(root.path);
  });
  tearDown(() {
    PathProviderPlatform.instance = before;
    root.deleteSync(recursive: true);
  });

  testWidgets('a photo re-picked at the same path is read afresh, at the '
      'thumbnail size too', (tester) async {
    Directory('${root.path}/meal_images').createSync();
    File('${root.path}/meal_images/m.jpg').writeAsBytesSync([0, 1, 2]);
    await tester.pumpWidget(
      MaterialApp(
        home: SizedFileImage(
          relativePath: 'meal_images/m.jpg',
          size: 40,
          fallback: (_) => const SizedBox(),
        ),
      ),
    );
    await tester.pump();
    final resized = tester.widget<Image>(find.byType(Image)).image;
    expect(resized, isA<ResizeImage>());
    final plain = (resized as ResizeImage).imageProvider;
    final cache = PaintingBinding.instance.imageCache;
    // Both as the old photo left them cached.
    final keys = [
      await resized.obtainKey(ImageConfiguration.empty),
      await plain.obtainKey(ImageConfiguration.empty),
    ];
    for (final key in keys) {
      cache.putIfAbsent(
        key,
        () => OneFrameImageStreamCompleter(Completer<ImageInfo>().future),
      );
      expect(cache.containsKey(key), isTrue);
    }

    await evictPhoto('meal_images/m.jpg');

    expect(cache.containsKey(keys[0]), isFalse, reason: 'the thumbnail');
    expect(cache.containsKey(keys[1]), isFalse, reason: 'the full size');
    tester.takeException();
  });
}
