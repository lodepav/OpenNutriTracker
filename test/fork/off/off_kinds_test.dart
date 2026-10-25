import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:hive_ce/hive.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/presentation/widgets/intake_card.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/fork/off/off_kinds.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:provider/provider.dart';

const _yogurt = [
  'en:dairies',
  'en:fermented-foods',
  'en:fermented-milk-products',
  'en:desserts',
  'en:fermented-dairy-desserts-with-fruits',
  'en:yogurts',
  'en:fruit-yogurts',
];

MealEntity _product(
  String name, {
  String code = '4006040000000',
  MealSourceEntity source = MealSourceEntity.off,
}) => MealEntity(
  code: code,
  name: name,
  url: null,
  thumbnailImageUrl: 'https://images.openfoodfacts.org/thumb.jpg',
  mainImageUrl: 'https://images.openfoodfacts.org/front.jpg',
  mealQuantity: null,
  mealUnit: 'g',
  servingQuantity: null,
  servingUnit: null,
  servingSize: null,
  nutriments: MealNutrimentsEntity.empty(),
  source: source,
);

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('off_kinds');
    Hive.init(dir.path);
    OffKinds.box = () => Hive.openBox<dynamic>(OffKinds.boxName);
    OffKinds.kinds.value = const {};
  });

  tearDown(() async {
    OffKinds.kinds.value = const {};
    await Hive.close();
    await dir.delete(recursive: true);
  });

  group('the kind from the categories', () {
    test('the narrowest that names one, without its leading words', () {
      expect(OffKinds.fromCategories(_yogurt), '🥛');
    });

    test('a broad category when nothing narrower names a kind', () {
      expect(
        OffKinds.fromCategories(['en:dairies', 'en:fermented-milk-products']),
        '🥛',
      );
    });

    test('"with" names an ingredient, not the kind', () {
      expect(OffKinds.fromCategories(['en:desserts-with-fruits']), isNot('🍎'));
    });

    test('only English tags, none for nothing', () {
      expect(OffKinds.fromCategories(['fr:yaourts']), isNull);
      expect(OffKinds.fromCategories(null), isNull);
      expect(OffKinds.fromCategories(const []), isNull);
    });
  });

  test("a guess from the name's last words; a brand alone says nothing", () {
    expect(OffKinds.fromName('Greek yogurt'), '🥛');
    expect(OffKinds.fromName('Nutella'), isNull);
    expect(OffKinds.fromName(null), isNull);
  });

  test(
    'a learnt kind is kept by barcode and read back at the next start',
    () async {
      await OffKinds.learn([
        (code: '111', categories: _yogurt),
        (code: '222', categories: null),
        (code: null, categories: _yogurt),
      ]);
      expect(OffKinds.kinds.value, {'111': '🥛'});

      OffKinds.kinds.value = const {};
      await OffKinds.start();
      expect(OffKinds.kinds.value, {'111': '🥛'});
    },
  );

  test('a product shows its learnt kind over a guess from its name, and no '
      'photo; other foods keep theirs', () async {
    final nutella = _product('Nutella');
    expect(OffKinds.emojiFor(nutella), isNull);
    await OffKinds.learn([
      (code: nutella.code, categories: ['en:spreads', 'en:sweet-spreads']),
    ]);
    // "spreads" names no kind: still the guess, which is none.
    expect(OffKinds.emojiFor(nutella), isNull);

    final yogurt = _product('Greek yogurt', code: '333');
    expect(OffKinds.emojiFor(yogurt), '🥛');
    await OffKinds.learn([
      (code: '333', categories: ['en:beverages']),
    ]);
    expect(OffKinds.emojiFor(yogurt), '🥤');

    expect(OffKinds.showsPhoto(yogurt), isFalse);
    expect(
      OffKinds.showsPhoto(_product('Own', source: MealSourceEntity.custom)),
      isTrue,
    );
  });

  testWidgets("a logged product's row shows its kind, not its photo", (
    tester,
  ) async {
    await tester.runAsync(
      () => OffKinds.learn([(code: '444', categories: _yogurt)]),
    );
    await tester.pumpWidget(
      ChangeNotifierProvider<EnergyUnitProvider>(
        create: (_) => EnergyUnitProvider(usesKilojoules: false),
        child: MaterialApp(
          localizationsDelegates: const [
            S.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          supportedLocales: S.supportedLocales,
          home: Scaffold(
            body: IntakeCard(
              key: const ValueKey('row'),
              intake: IntakeEntity(
                id: 'i',
                unit: 'g',
                amount: 150,
                type: IntakeTypeEntity.snack,
                meal: _product('Fruit yogurt', code: '444'),
                dateTime: DateTime(2026, 10, 25, 16),
              ),
              firstListElement: false,
              usesImperialUnits: false,
            ),
          ),
        ),
      ),
    );
    expect(find.text('🥛'), findsOneWidget);
    expect(find.byType(CachedNetworkImage), findsNothing);
  });

  tearDownAll(() => GetIt.instance.reset());
}
