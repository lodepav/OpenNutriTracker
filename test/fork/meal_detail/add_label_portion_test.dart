import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:opennutritracker/core/data/data_source/remote_search_cache_data_source.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/domain/usecase/add_intake_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/add_tracked_day_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_intake_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_kcal_goal_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_macro_goal_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_tracked_day_usecase.dart';
import 'package:opennutritracker/features/add_meal/data/repository/products_repository.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_portion_entity.dart';
import 'package:opennutritracker/features/add_meal/util/portion_unit.dart';
import 'package:opennutritracker/features/diary/presentation/bloc/calendar_day_bloc.dart';
import 'package:opennutritracker/features/diary/presentation/bloc/diary_bloc.dart';
import 'package:opennutritracker/features/home/presentation/bloc/home_bloc.dart';
import 'package:opennutritracker/features/meal_detail/presentation/bloc/meal_detail_bloc.dart';
import 'package:opennutritracker/features/meal_detail/presentation/widgets/meal_detail_bottom_sheet.dart';
import 'package:opennutritracker/generated/l10n.dart';

// An Open Food Facts egg: its serving is "1 large (50 g)".
MealEntity _food({
  String servingSize = '1 large (50 g)',
  List<MealPortionEntity> portions = const [],
}) => MealEntity(
  code: 'egg',
  name: 'Egg',
  url: null,
  mealQuantity: null,
  mealUnit: 'g',
  servingQuantity: 50,
  servingUnit: 'g',
  servingSize: servingSize,
  portions: portions,
  nutriments: const MealNutrimentsEntity(
    energyKcal100: 143,
    carbohydrates100: 1,
    fat100: 10,
    proteins100: 13,
    sugars100: null,
    saturatedFat100: null,
    fiber100: null,
  ),
  source: MealSourceEntity.off,
);

class _NothingLogged extends Fake implements GetIntakeUsecase {
  Future<List<IntakeEntity>> _none() async => [];
  @override
  Future<List<IntakeEntity>> getBreakfastIntakeByDay(
    DateTime day, {
    int dayStartOffsetHours = 0,
    int dayStartOffsetMinutes = 0,
  }) => _none();
}

class _HomeBloc extends Fake implements HomeBloc {}

class _DiaryBloc extends Fake implements DiaryBloc {}

class _CalendarDayBloc extends Fake implements CalendarDayBloc {}

class _FakeAdd extends Fake implements AddIntakeUsecase {}

class _FakeTracked extends Fake implements AddTrackedDayUsecase {}

class _FakeKcal extends Fake implements GetKcalGoalUsecase {}

class _FakeMacro extends Fake implements GetMacroGoalUsecase {}

class _FakeGetTracked extends Fake implements GetTrackedDayUsecase {}

class _FakeProducts extends Fake implements ProductsRepository {}

class _FakeCache extends Fake implements RemoteSearchCacheDataSource {}

void main() {
  setUp(() {
    GetIt.instance
      ..registerFactory<GetIntakeUsecase>(_NothingLogged.new)
      ..registerFactory<HomeBloc>(_HomeBloc.new)
      ..registerFactory<DiaryBloc>(_DiaryBloc.new)
      ..registerFactory<CalendarDayBloc>(_CalendarDayBloc.new);
  });
  tearDown(() => GetIt.instance.reset());

  Future<TextEditingController> pumpSheet(
    WidgetTester tester,
    MealEntity food,
    String unit,
  ) async {
    final bloc = MealDetailBloc(
      _FakeAdd(),
      _FakeTracked(),
      _FakeKcal(),
      _FakeMacro(),
      _FakeGetTracked(),
      _FakeProducts(),
      _FakeCache(),
    );
    addTearDown(bloc.close);
    final amount = TextEditingController(text: '1');
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [S.delegate],
        supportedLocales: S.supportedLocales,
        home: Scaffold(
          body: MealDetailBottomSheet(
            product: food,
            day: DateTime(2026, 10, 25),
            intakeTypeEntity: IntakeTypeEntity.breakfast,
            quantityTextController: amount,
            mealDetailBloc: bloc,
            selectedUnit: unit,
            onQuantityOrUnitChanged: (_, _) {},
          ),
        ),
      ),
    );
    return amount;
  }

  testWidgets('Add names the serving picked, not "serving"', (tester) async {
    final amount = await pumpSheet(tester, _food(), 'serving');

    expect(find.text('Add 1 large'), findsOneWidget);
    expect(find.text('Add 1 serving'), findsNothing);
    amount.text = '2';
    await tester.pump();
    expect(find.text('Add 2 large'), findsOneWidget);
  });

  testWidgets('Add names the portion picked', (tester) async {
    final egg = _food(
      portions: const [
        MealPortionEntity(label: '1 large', gramWeight: 50, localized: true),
        MealPortionEntity(label: '1 jumbo', gramWeight: 63, localized: true),
      ],
    );

    await pumpSheet(tester, egg, portionUnit(0));
    expect(find.text('Add 1 large'), findsOneWidget);

    await pumpSheet(tester, egg, portionUnit(1));
    expect(find.text('Add 1 jumbo'), findsOneWidget);
  });

  testWidgets('a food with no unnamed serving keeps "servings"', (
    tester,
  ) async {
    final amount = await pumpSheet(
      tester,
      _food(servingSize: '50 g'),
      'serving',
    );
    amount.text = '2';
    await tester.pump();
    expect(find.text('Add 2 servings'), findsOneWidget);
  });

  testWidgets('a weight reads as the picker writes it: g, not gml', (
    tester,
  ) async {
    final amount = await pumpSheet(tester, _food(), 'gml');
    amount.text = '100';
    await tester.pump();
    expect(find.text('Add 100 g'), findsOneWidget);
  });
}
