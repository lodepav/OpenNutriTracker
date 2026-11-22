import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/presentation/widgets/image_full_screen.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/core/utils/navigation_options.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/fork/meal_detail/food_page.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';

// S408: a custom food's own photo shows in the food page's header, and its
// tap opens that file full screen.

class _Paths extends PathProviderPlatform with MockPlatformInterfaceMixin {
  final String root;

  _Paths(this.root);

  @override
  Future<String?> getApplicationDocumentsPath() async => root;
}

final _banana = MealEntity(
  code: 'banana',
  name: 'Banana',
  url: null,
  mealQuantity: null,
  mealUnit: 'g',
  servingQuantity: null,
  servingUnit: 'g',
  servingSize: null,
  nutriments: const MealNutrimentsEntity(
    energyKcal100: 89,
    carbohydrates100: 23,
    fat100: 0.3,
    proteins100: 1.1,
    sugars100: null,
    saturatedFat100: null,
    fiber100: null,
  ),
  source: MealSourceEntity.custom,
  localImagePath: 'meal_images/banana.webp',
);

String? _filePath(Image image) {
  var provider = image.image;
  if (provider is ResizeImage) provider = provider.imageProvider;
  return provider is FileImage ? provider.file.path : null;
}

void main() {
  late Directory root;
  late PathProviderPlatform before;

  setUp(() {
    root = Directory.systemTemp.createTempSync('fork_food_photo_');
    before = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(root.path);
  });
  tearDown(() {
    PathProviderPlatform.instance = before;
    root.deleteSync(recursive: true);
  });

  testWidgets('the header shows the food\'s own photo and opens it', (
    tester,
  ) async {
    final expected = '${root.path}/meal_images/banana.webp';
    await tester.pumpWidget(
      ChangeNotifierProvider<EnergyUnitProvider>(
        create: (_) => EnergyUnitProvider(),
        child: MaterialApp(
          routes: {
            NavigationOptions.imageFullScreenRoute: (_) =>
                const ImageFullScreen(),
          },
          home: Scaffold(body: FoodPageHeader(meal: _banana)),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    final thumb = tester.widget<Image>(find.byType(Image));
    expect(_filePath(thumb), expected);

    await tester.tap(find.bySemanticsLabel('Photo of Banana'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();

    final full = tester.widget<Image>(
      find.descendant(
        of: find.byType(ImageFullScreen),
        matching: find.byType(Image),
      ),
    );
    expect(_filePath(full), expected);
  });
}
