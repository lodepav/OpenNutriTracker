import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/presentation/widgets/image_full_screen.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/app_theme.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

// S521: the full-screen food photo shows all of it on black, its Back arrow
// white over it, and has a spoken name.

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
    root = Directory.systemTemp.createTempSync('fork_full_photo_');
    before = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(root.path);
  });
  tearDown(() {
    PathProviderPlatform.instance = before;
    root.deleteSync(recursive: true);
  });

  testWidgets('the photo is contained on black, named, with a white bar', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(AppPalette.light),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                settings: RouteSettings(
                  arguments: ImageFullScreenArguments(
                    '',
                    localImagePath: 'meal_images/banana.webp',
                  ),
                ),
                builder: (_) => const ImageFullScreen(),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(tester.widget<Image>(find.byType(Image)).fit, BoxFit.contain);
    expect(
      tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
      Colors.black,
    );
    // the Back arrow as drawn, under the app's theme
    final arrow = find.descendant(
      of: find.byType(BackButton),
      matching: find.byType(Icon),
    );
    expect(IconTheme.of(tester.element(arrow)).color, Colors.white);
    expect(find.bySemanticsLabel('The food photo'), findsOneWidget);
    // black system bars with light icons, not the light theme's grey scrims
    // (S556, G2-25)
    final bars = tester.widget<AppBar>(find.byType(AppBar)).systemOverlayStyle!;
    expect(bars.statusBarIconBrightness, Brightness.light);
    expect(bars.systemNavigationBarColor, Colors.black);
    expect(bars.systemNavigationBarContrastEnforced, isFalse);
    expect(bars.systemStatusBarContrastEnforced, isFalse);
    semantics.dispose();
  });
}
