import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/fork/screens/home/intake_card.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';

class _Paths extends PathProviderPlatform with MockPlatformInterfaceMixin {
  final String root;
  var lookups = 0;

  _Paths(this.root);

  @override
  Future<String?> getApplicationDocumentsPath() async {
    lookups++;
    return root;
  }
}

class _Cache extends Fake implements CacheManager {}

IntakeEntity _intake({
  String name = 'Chicken breast, skinless, roasted, from the deli counter',
  String? photo,
  String? url,
}) => IntakeEntity(
  id: 'i',
  unit: 'g',
  amount: 150,
  type: IntakeTypeEntity.lunch,
  dateTime: DateTime(2026, 1, 1, 12),
  meal: MealEntity(
    code: 'meal',
    name: name,
    url: null,
    mainImageUrl: url,
    localImagePath: photo,
    mealQuantity: '100',
    mealUnit: 'g',
    servingQuantity: null,
    servingUnit: 'g',
    servingSize: '100 g',
    nutriments: MealNutrimentsEntity(
      energyKcal100: 200,
      carbohydrates100: 20,
      fat100: 10,
      proteins100: 5,
      sugars100: null,
      saturatedFat100: null,
      fiber100: null,
    ),
    source: MealSourceEntity.custom,
  ),
);

Widget _app(IntakeEntity intake, {double scale = 1, double width = 320}) =>
    ChangeNotifierProvider<EnergyUnitProvider>(
      create: (_) => EnergyUnitProvider(usesKilojoules: false),
      child: MaterialApp(
        localizationsDelegates: const [
          S.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        supportedLocales: S.supportedLocales,
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: width,
                  child: IntakeCard(
                    key: const ValueKey('row'),
                    intake: intake,
                    firstListElement: false,
                    usesImperialUnits: false,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

void main() {
  group('a meal photo thumbnail', () {
    late Directory root;
    late PathProviderPlatform before;
    late _Paths paths;

    setUp(() {
      root = Directory.systemTemp.createTempSync('fork_thumb_');
      before = PathProviderPlatform.instance;
      paths = _Paths(root.path);
      PathProviderPlatform.instance = paths;
    });
    tearDown(() {
      PathProviderPlatform.instance = before;
      root.deleteSync(recursive: true);
    });

    testWidgets('is decoded at the thumbnail size, its path looked up once', (
      tester,
    ) async {
      Directory('${root.path}/meal_images').createSync();
      File('${root.path}/meal_images/m.jpg').writeAsBytesSync([0, 1, 2]);
      final intake = _intake(photo: 'meal_images/m.jpg');
      await tester.pumpWidget(_app(intake));
      await tester.pump();
      // a rebuild, as each selection tap makes
      await tester.pumpWidget(_app(intake, width: 319));
      await tester.pump();
      expect(paths.lookups, 1);

      final image = tester.widget<Image>(find.byType(Image)).image;
      final dpr = tester.view.devicePixelRatio;
      expect(image, isA<ResizeImage>());
      expect(
        (image as ResizeImage).width,
        (IntakeCard.thumbSize * dpr).round(),
      );
      // a broken or unreadable photo shows nothing worse than the fallback
      tester.takeException();
    });

    testWidgets('a photo no longer on disk shows the food\'s fallback', (
      tester,
    ) async {
      await tester.pumpWidget(_app(_intake(photo: 'meal_images/gone.jpg')));
      await tester.pump();
      // the file read fails off the fake clock
      for (var i = 0; i < 3; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump();
      }
      final thumb = find.descendant(
        of: find.byType(ClipRRect),
        matching: find.byWidgetPredicate((w) => w is Text || w is Icon),
      );
      expect(thumb, findsOneWidget);
    });
  });

  testWidgets('a remote thumbnail is kept in memory at the thumbnail size', (
    tester,
  ) async {
    GetIt.instance.registerSingleton<CacheManager>(_Cache());
    addTearDown(GetIt.instance.reset);
    await tester.pumpWidget(_app(_intake(url: 'https://example.com/a.jpg')));
    final image = tester.widget<CachedNetworkImage>(
      find.byType(CachedNetworkImage),
    );
    expect(
      image.memCacheWidth,
      (IntakeCard.thumbSize * tester.view.devicePixelRatio).round(),
    );
    tester.takeException();
  });

  testWidgets('above 1.5x text the name shows whole, the energy under it', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_intake(), scale: 2));
    await tester.pump();
    final name = find.textContaining('Chicken breast');
    final paragraph = tester.renderObject<RenderParagraph>(
      find.descendant(of: name, matching: find.byType(RichText)).first,
    );
    expect(paragraph.didExceedMaxLines, isFalse);
    expect(
      tester.getTopLeft(find.text('300 kcal')).dy,
      greaterThan(tester.getBottomLeft(name).dy - 1),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('at 1x the energy stays on the trailing edge', (tester) async {
    await tester.pumpWidget(_app(_intake()));
    await tester.pump();
    expect(
      tester.getTopLeft(find.text('300 kcal')).dx,
      greaterThan(tester.getTopRight(find.textContaining('Chicken')).dx),
    );
  });
}
