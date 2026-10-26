import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:opennutritracker/core/data/data_source/remote_search_cache_data_source.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/domain/entity/recipe_entity.dart';
import 'package:opennutritracker/core/domain/usecase/add_intake_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/add_tracked_day_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_kcal_goal_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_macro_goal_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_tracked_day_usecase.dart';
import 'package:opennutritracker/features/add_meal/data/repository/products_repository.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/features/add_meal/util/food_emoji_resolver.dart';
import 'package:opennutritracker/core/domain/entity/recipe_ingredient_entity.dart';
import 'package:opennutritracker/features/meal_detail/presentation/bloc/meal_detail_bloc.dart';
import 'package:opennutritracker/fork/screens/recipes/recipe_list_item.dart';
import 'package:opennutritracker/fork/recipe/recipe_list.dart';
import 'package:opennutritracker/generated/l10n.dart';

const _per100 = MealNutrimentsEntity(
  energyKcal100: 150,
  carbohydrates100: 20,
  fat100: 5,
  proteins100: 10,
  sugars100: null,
  saturatedFat100: null,
  fiber100: null,
);

RecipeEntity _bowl({int? servings = 2}) => RecipeEntity(
  id: 'bowl',
  name: 'Bowl',
  description: null,
  ingredients: const [],
  totalWeightG: 400,
  aggregatedNutrimentsPer100: _per100,
  createdAt: DateTime(2026, 10, 25),
  updatedAt: DateTime(2026, 10, 25),
  servingsCount: servings,
);

Widget _app(Widget child) => MaterialApp(
  localizationsDelegates: const [S.delegate],
  supportedLocales: S.supportedLocales,
  home: Scaffold(body: child),
);

class _Written extends Fake implements IntakeEntity {}

class _FakeAdd extends Fake implements AddIntakeUsecase {}

class _FakeTracked extends Fake implements AddTrackedDayUsecase {}

class _FakeKcal extends Fake implements GetKcalGoalUsecase {}

class _FakeMacro extends Fake implements GetMacroGoalUsecase {}

class _FakeGetTracked extends Fake implements GetTrackedDayUsecase {}

class _FakeProducts extends Fake implements ProductsRepository {}

class _FakeCache extends Fake implements RemoteSearchCacheDataSource {}

class _CacheManager extends Fake implements CacheManager {}

class _RecordingBloc extends MealDetailBloc {
  _RecordingBloc()
    : super(
        _FakeAdd(),
        _FakeTracked(),
        _FakeKcal(),
        _FakeMacro(),
        _FakeGetTracked(),
        _FakeProducts(),
        _FakeCache(),
      );

  final logged = <(IntakeTypeEntity, String, String)>[];

  @override
  Future<IntakeEntity> addIntake(
    BuildContext context,
    String unit,
    String amountText,
    IntakeTypeEntity type,
    MealEntity meal,
    DateTime day,
  ) async {
    logged.add((type, unit, amountText));
    return _Written();
  }
}

void main() {
  test('a serving is the recipe over its servings, else all of it', () {
    final half = servingValues(_bowl());
    expect(half.kcal, 300);
    expect((half.carbs, half.fat, half.protein), (40, 10, 20));
    expect(servingValues(_bowl(servings: null)).kcal, 600);
  });

  test('the kind is the name\'s, else the most energetic ingredient\'s', () {
    RecipeIngredientEntity ingredient(String name, double grams, double kcal) =>
        RecipeIngredientEntity(
          snapshotMeal: MealEntity(
            code: name,
            name: name,
            url: null,
            mealQuantity: null,
            mealUnit: 'g',
            servingQuantity: null,
            servingUnit: null,
            servingSize: null,
            nutriments: MealNutrimentsEntity(
              energyKcal100: kcal,
              carbohydrates100: 0,
              fat100: 0,
              proteins100: 0,
              sugars100: null,
              saturatedFat100: null,
              fiber100: null,
            ),
            source: MealSourceEntity.custom,
          ),
          amount: grams,
          unit: 'g',
          convertedAmountG: grams,
        );
    RecipeEntity named(String name) => RecipeEntity(
      id: name,
      name: name,
      description: null,
      ingredients: [ingredient('Water', 500, 0), ingredient('Banana', 100, 89)],
      totalWeightG: 600,
      aggregatedNutrimentsPer100: _per100,
      createdAt: DateTime(2026, 10, 25),
      updatedAt: DateTime(2026, 10, 25),
      servingsCount: null,
    );
    final yogurt = resolveFoodEmoji('yogurt');
    expect(yogurt, isNotNull);
    expect(recipeEmoji(named('Greek yogurt parfait')), yogurt);
    // The water weighs more and comes first; the banana is the dish.
    expect(recipeEmoji(named('Sunday mix')), resolveFoodEmoji('Banana'));
  });

  group('the row', () {
    setUp(
      () => GetIt.instance.registerSingleton<CacheManager>(_CacheManager()),
    );
    tearDown(GetIt.instance.reset);

    testWidgets('shows one serving\'s energy and macros, and logs it', (
      tester,
    ) async {
      var logs = 0;
      await tester.pumpWidget(
        _app(
          RecipeListItem(recipe: _bowl(), onTap: () {}, onLog: () => logs++),
        ),
      );
      expect(find.text('300'), findsOneWidget);
      expect(find.text('kcal / serving'), findsOneWidget);
      // Shown as letters, spoken as grams (A5)
      final macros = find.byWidgetPredicate(
        (w) =>
            w is RichText &&
            w.text
                .toPlainText(includeSemanticsLabels: false)
                .contains('C\u00A040 · F\u00A010 · P\u00A020'),
      );
      expect(macros, findsOneWidget);
      expect(
        tester.widget<RichText>(macros).text.toPlainText(),
        contains('40 grams carbs, 10 grams fat, 20 grams protein'),
      );
      await tester.tap(find.byKey(const ValueKey('recipe-log-bowl')));
      expect(logs, 1);
    });

    testWidgets('a recipe without servings shows all of it', (tester) async {
      await tester.pumpWidget(
        _app(RecipeListItem(recipe: _bowl(servings: null), onTap: () {})),
      );
      expect(find.text('600'), findsOneWidget);
      expect(find.text('kcal'), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
    });
  });

  group('logging a serving', () {
    late _RecordingBloc bloc;
    setUp(() {
      bloc = _RecordingBloc();
      GetIt.instance.registerSingleton<MealDetailBloc>(bloc);
    });
    tearDown(() async {
      await bloc.close();
      await GetIt.instance.reset();
    });

    testWidgets('logs one serving in grams to the meal picked', (tester) async {
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => logRecipeServing(context, _bowl()),
              child: const Text('log'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('log'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lunch'));
      await tester.pumpAndSettle();
      expect(bloc.logged, [(IntakeTypeEntity.lunch, 'g', '200.0')]);
      expect(find.text('1 serving of Bowl added to Lunch'), findsOneWidget);
    });

    testWidgets('with a meal given, logs to it without asking', (tester) async {
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => logRecipeServing(
                context,
                _bowl(),
                meal: IntakeTypeEntity.dinner,
              ),
              child: const Text('log'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('log'));
      await tester.pumpAndSettle();
      expect(find.text('Lunch'), findsNothing);
      expect(bloc.logged, [(IntakeTypeEntity.dinner, 'g', '200.0')]);
    });

    testWidgets('closing the meals logs nothing', (tester) async {
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => logRecipeServing(context, _bowl()),
              child: const Text('log'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('log'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();
      expect(bloc.logged, isEmpty);
    });
  });
}
