import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/profile_entity.dart';
import 'package:opennutritracker/features/profile/presentation/widgets/profile_avatar.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

// Seam S250: the profile photo is decoded at the avatar's size, its path
// looked up once rather than on every rebuild.

class _Paths extends PathProviderPlatform with MockPlatformInterfaceMixin {
  var lookups = 0;

  @override
  Future<String?> getApplicationDocumentsPath() async {
    lookups++;
    return '/docs';
  }
}

Widget _app(double width) => MaterialApp(
  home: Center(
    child: SizedBox(
      width: width,
      child: ProfileAvatar(
        profile: ProfileEntity(
          id: 'p1',
          name: 'Alex',
          createdAt: DateTime(2026, 1, 1),
          boxSuffix: '',
          imagePath: 'profile_images/p1.webp',
        ),
        radius: 24,
      ),
    ),
  ),
);

void main() {
  late PathProviderPlatform before;
  late _Paths paths;
  setUp(() {
    before = PathProviderPlatform.instance;
    paths = _Paths();
    PathProviderPlatform.instance = paths;
  });
  tearDown(() => PathProviderPlatform.instance = before);

  testWidgets('the photo is decoded at the avatar size, its path looked up '
      'once', (tester) async {
    await tester.pumpWidget(_app(100));
    await tester.pump();
    // a rebuild, as each profile reload makes
    await tester.pumpWidget(_app(101));
    await tester.pump();
    expect(paths.lookups, 1);

    final image = tester
        .widget<CircleAvatar>(find.byType(CircleAvatar))
        .backgroundImage;
    expect(image, isA<ResizeImage>());
    expect(
      (image as ResizeImage).width,
      (48 * tester.view.devicePixelRatio).round(),
    );
    expect(
      (image.imageProvider as FileImage).file.path,
      File('/docs/profile_images/p1.webp').path,
    );
    // the file isn't there in the test
    tester.takeException();
  });
}
