import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:opennutritracker/core/data/data_source/remote_search_cache_data_source.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/domain/usecase/add_intake_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/add_tracked_day_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_kcal_goal_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_macro_goal_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_tracked_day_usecase.dart';
import 'package:opennutritracker/features/add_meal/data/repository/products_repository.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/features/add_meal/presentation/add_meal_type.dart';
import 'package:opennutritracker/features/add_meal/presentation/bloc/favourite_toggle_bloc.dart';
import 'package:opennutritracker/features/meal_detail/presentation/bloc/meal_detail_bloc.dart';
import 'package:opennutritracker/features/meal_detail/presentation/widgets/meal_detail_bottom_sheet.dart';
import 'package:opennutritracker/fork/basket/basket.dart';
import 'package:opennutritracker/fork/screens/add_meal/meal_item_card.dart';
import 'package:opennutritracker/generated/l10n.dart';

import '../../helpers/fake_favourites.dart';

class _Add extends Fake implements AddIntakeUsecase {}

class _Tracked extends Fake implements AddTrackedDayUsecase {}

class _Kcal extends Fake implements GetKcalGoalUsecase {}

class _Macro extends Fake implements GetMacroGoalUsecase {}

class _Day extends Fake implements GetTrackedDayUsecase {}

class _Products extends Fake implements ProductsRepository {}

class _Cache extends Fake implements RemoteSearchCacheDataSource {}

class _Bloc extends MealDetailBloc {
  _Bloc()
    : super(
        _Add(),
        _Tracked(),
        _Kcal(),
        _Macro(),
        _Day(),
        _Products(),
        _Cache(),
      );

  var saves = 0;

  @override
  Future<IntakeEntity?> addIntake(
    BuildContext context,
    String unit,
    String amountText,
    IntakeTypeEntity type,
    MealEntity meal,
    DateTime day,
  ) async {
    saves++;
    return null;
  }
}

/// While planning for a day ahead, nothing reachable from search may log.
void main() {
  final day = DateTime(2026, 11, 3);
  final meal = MealEntity(
    code: 'toast',
    name: 'Toast',
    url: null,
    mealQuantity: null,
    mealUnit: 'g',
    servingQuantity: null,
    servingUnit: 'g',
    servingSize: null,
    nutriments: const MealNutrimentsEntity(
      energyKcal100: 200,
      carbohydrates100: 40,
      fat100: 2,
      proteins100: 6,
      sugars100: null,
      saturatedFat100: null,
      fiber100: null,
    ),
    source: MealSourceEntity.custom,
  );
  final basket = FoodBasket.instance;
  late FakeFavourites favourites;

  setUp(() {
    favourites = FakeFavourites();
    GetIt.instance.registerFactory<FavouriteToggleBloc>(
      () => FavouriteToggleBloc(favourites.get, favourites.toggle),
    );
  });

  tearDown(() async {
    basket
      ..planning = null
      ..clear();
    await GetIt.instance.reset();
    await favourites.dispose();
  });

  Widget app(Widget body) => MaterialApp(
    localizationsDelegates: const [
      S.delegate,
      ...GlobalMaterialLocalizations.delegates,
    ],
    supportedLocales: S.supportedLocales,
    home: Builder(
      builder: (context) => TextButton(
        onPressed: () => Navigator.of(
          context,
        ).push(MaterialPageRoute<void>(builder: (_) => Scaffold(body: body))),
        child: const Text('search'),
      ),
    ),
  );

  Future<void> open(WidgetTester tester, Widget body) async {
    await tester.pumpWidget(app(body));
    await tester.tap(find.text('search'));
    await tester.pumpAndSettle();
  }

  group('search row', () {
    Widget row() => MealItemCard(
      day: day,
      mealEntity: meal,
      addMealType: AddMealType.lunchType,
      usesImperialUnits: false,
    );

    testWidgets('has its one-tap plus normally', (tester) async {
      await open(tester, row());
      expect(find.bySemanticsIdentifier('meal-item-add'), findsOneWidget);
    });

    testWidgets('has none while planning', (tester) async {
      basket.planning = PlanMode.once;
      await open(tester, row());
      expect(find.bySemanticsIdentifier('meal-item-add'), findsNothing);
    });
  });

  group("food's page", () {
    Future<_Bloc> page(WidgetTester tester) async {
      final bloc = _Bloc();
      addTearDown(bloc.close);
      bloc.add(
        UpdateKcalEvent(meal: meal, totalQuantity: '150', selectedUnit: 'g'),
      );
      await open(
        tester,
        MealDetailBottomSheet(
          product: meal,
          day: day,
          intakeTypeEntity: IntakeTypeEntity.lunch,
          quantityTextController: TextEditingController(text: '150'),
          mealDetailBloc: bloc,
          selectedUnit: 'g',
          onQuantityOrUnitChanged: (_, _) {},
        ),
      );
      return bloc;
    }

    testWidgets('has Add normally', (tester) async {
      await page(tester);
      expect(find.bySemanticsIdentifier('meal-detail-add'), findsOneWidget);
      expect(find.text('Add to plan'), findsNothing);
    });

    testWidgets('only adds to the plan while planning', (tester) async {
      basket.planning = PlanMode.recurring;
      final bloc = await page(tester);
      expect(find.bySemanticsIdentifier('meal-detail-add'), findsNothing);
      expect(find.byKey(const ValueKey('meal-detail-meal')), findsNothing);

      await tester.tap(find.text('Add to plan'));
      await tester.pumpAndSettle();
      expect(bloc.saves, 0);
      expect(basket.itemsFor(IntakeTypeEntity.lunch, day), hasLength(1));
      expect(find.text('search'), findsOneWidget);
    });
  });
}
