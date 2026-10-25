import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:opennutritracker/core/domain/entity/recipe_entity.dart';
import 'package:opennutritracker/core/domain/entity/recipe_ingredient_entity.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/features/recipes/presentation/widgets/recipe_list_item.dart';
import 'package:opennutritracker/fork/off/off_kinds.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:provider/provider.dart';

class _CacheManager extends Fake implements CacheManager {}

const _nutriments = MealNutrimentsEntity(
  energyKcal100: 100,
  carbohydrates100: 20,
  fat100: 10,
  proteins100: 5,
  sugars100: null,
  saturatedFat100: null,
  fiber100: null,
);

RecipeIngredientEntity _ingredient(MealSourceEntity source, String photo) =>
    RecipeIngredientEntity(
      snapshotMeal: MealEntity(
        code: photo,
        name: 'Oats',
        thumbnailImageUrl: 'https://images.example/$photo.jpg',
        url: null,
        mealQuantity: null,
        mealUnit: 'g',
        servingQuantity: null,
        servingUnit: null,
        servingSize: null,
        nutriments: _nutriments,
        source: source,
      ),
      amount: 100,
      unit: 'g',
      convertedAmountG: 100,
    );

RecipeEntity _recipe(List<RecipeIngredientEntity> ingredients) => RecipeEntity(
  id: 'r',
  name: 'Porridge',
  description: null,
  ingredients: ingredients,
  totalWeightG: 100,
  aggregatedNutrimentsPer100: _nutriments,
  createdAt: DateTime(2026, 10, 25),
  updatedAt: DateTime(2026, 10, 25),
  servingsCount: 1,
);

Widget _app(Widget child) => ChangeNotifierProvider<EnergyUnitProvider>(
  create: (_) => EnergyUnitProvider(usesKilojoules: false),
  child: MaterialApp(
    localizationsDelegates: const [
      S.delegate,
      ...GlobalMaterialLocalizations.delegates,
    ],
    supportedLocales: S.supportedLocales,
    home: Scaffold(body: child),
  ),
);

void main() {
  setUp(() => GetIt.instance.registerSingleton<CacheManager>(_CacheManager()));
  tearDown(GetIt.instance.reset);

  testWidgets('a recipe takes no Open Food Facts photo from its ingredients', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        RecipeListItem(
          recipe: _recipe([_ingredient(MealSourceEntity.off, 'off')]),
          onTap: () {},
        ),
      ),
    );
    expect(find.byType(CachedNetworkImage), findsNothing);
    // S130: its kind instead
    final kind = OffKinds.emojiFor(
      _ingredient(MealSourceEntity.off, 'off').snapshotMeal,
    );
    expect(kind, isNotNull);
    expect(find.text(kind!), findsOne);
  });

  testWidgets('a recipe with no kind or photo shows the book', (tester) async {
    await tester.pumpWidget(
      _app(RecipeListItem(recipe: _recipe([]), onTap: () {})),
    );
    expect(find.byIcon(Icons.menu_book_rounded), findsOne);
  });

  testWidgets('another source\'s photo still shows', (tester) async {
    await tester.pumpWidget(
      _app(
        RecipeListItem(
          recipe: _recipe([
            _ingredient(MealSourceEntity.off, 'off'),
            _ingredient(MealSourceEntity.fdc, 'fdc'),
          ]),
          onTap: () {},
        ),
      ),
    );
    expect(
      tester
          .widget<CachedNetworkImage>(find.byType(CachedNetworkImage))
          .imageUrl,
      'https://images.example/fdc.jpg',
    );
  });
}
