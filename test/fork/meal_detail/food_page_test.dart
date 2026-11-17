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
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/features/add_meal/data/repository/products_repository.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/features/diary/presentation/bloc/calendar_day_bloc.dart';
import 'package:opennutritracker/features/diary/presentation/bloc/diary_bloc.dart';
import 'package:opennutritracker/features/home/presentation/bloc/home_bloc.dart';
import 'package:opennutritracker/features/meal_detail/presentation/bloc/meal_detail_bloc.dart';
import 'package:opennutritracker/features/meal_detail/presentation/widgets/meal_detail_bottom_sheet.dart';
import 'package:opennutritracker/fork/basket/basket.dart';
import 'package:opennutritracker/fork/meal_detail/food_page.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:provider/provider.dart';

final _toast = MealEntity(
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

Widget _app(Widget child) => MaterialApp(
  localizationsDelegates: const [S.delegate],
  supportedLocales: S.supportedLocales,
  home: Scaffold(body: child),
);

class _NothingLogged extends Fake implements GetIntakeUsecase {
  Future<List<IntakeEntity>> _none() async => [];
  @override
  Future<List<IntakeEntity>> getBreakfastIntakeByDay(
    DateTime day, {
    int dayStartOffsetHours = 0,
    int dayStartOffsetMinutes = 0,
  }) => _none();
  @override
  Future<List<IntakeEntity>> getDinnerIntakeByDay(
    DateTime day, {
    int dayStartOffsetHours = 0,
    int dayStartOffsetMinutes = 0,
  }) => _none();
}

class _HomeBloc extends Fake implements HomeBloc {
  @override
  void add(HomeEvent event) {}
}

class _DiaryBloc extends Fake implements DiaryBloc {
  @override
  void add(DiaryEvent event) {}
}

class _CalendarDayBloc extends Fake implements CalendarDayBloc {
  @override
  void add(CalendarDayEvent event) {}
}

class _Written extends Fake implements IntakeEntity {}

/// Records the meal and amount each Add logs.
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

  final logged = <(IntakeTypeEntity, String)>[];

  @override
  Future<IntakeEntity> addIntake(
    BuildContext context,
    String unit,
    String amountText,
    IntakeTypeEntity type,
    MealEntity meal,
    DateTime day,
  ) async {
    logged.add((type, unit));
    return _Written();
  }
}

class _FakeAdd extends Fake implements AddIntakeUsecase {}

class _FakeTracked extends Fake implements AddTrackedDayUsecase {}

class _FakeKcal extends Fake implements GetKcalGoalUsecase {}

class _FakeMacro extends Fake implements GetMacroGoalUsecase {}

class _FakeGetTracked extends Fake implements GetTrackedDayUsecase {}

class _FakeProducts extends Fake implements ProductsRepository {}

class _FakeCache extends Fake implements RemoteSearchCacheDataSource {}

void main() {
  testWidgets('the ring gives each macro its share of the energy', (
    tester,
  ) async {
    // 25 g carbs and 25 g protein are 100 kcal each; 0 g fat is none.
    await tester.pumpWidget(
      _app(const FoodMacroRing(kcal: 200, carbs: 25, fat: 0, protein: 25)),
    );
    expect(find.text('200'), findsOneWidget);
    expect(find.text('25 g carbs · 50%'), findsOneWidget);
    expect(find.text('0 g fat · 0%'), findsOneWidget);
    expect(find.text('25 g protein · 50%'), findsOneWidget);
  });

  // #1474: what the food lacks is missing, not 0.
  testWidgets('a value the food lacks shows as missing, with no share', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(const FoodMacroRing(kcal: null, carbs: 25, fat: null, protein: 25)),
    );
    expect(find.text('—'), findsOneWidget);
    expect(find.text('— fat'), findsOneWidget);
    expect(find.text('25 g carbs · 50%'), findsOneWidget);
    expect(find.text('25 g protein · 50%'), findsOneWidget);
  });

  testWidgets('the header names where the food comes from and its energy', (
    tester,
  ) async {
    await tester.pumpWidget(_app(FoodPageHeader(meal: _toast)));
    expect(find.text('Toast'), findsOneWidget);
    expect(find.text('Your food · 200 kcal per 100 g'), findsOneWidget);
  });

  testWidgets('the header reads as sentences, one heading', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(_app(FoodPageHeader(meal: _toast)));
    expect(
      tester.getSemantics(find.text('Toast')),
      isSemantics(
        label: 'Toast. Your food. 200 kcal per 100 g',
        isHeader: true,
      ),
    );
    semantics.dispose();
  });

  // A target passed is not an error, as in the Diary (critique P2).
  testWidgets('today after adding sums the amount in, none red when over', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      _app(
        TodayAfterAdding(
          day: DateTime(2026, 10, 25),
          kcal: 200,
          carbs: 10,
          fat: 2,
          protein: 5,
          load: (_) async => (
            eaten: (kcal: 1900.0, carbs: 100.0, fat: 50.0, protein: 60.0),
            goal: (kcal: 2000.0, carbs: 250.0, fat: 70.0, protein: 120.0),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final kcal = find.textContaining('2100');
    expect(kcal, findsOneWidget);
    // the unit with its number, a no-break space between
    expect(find.text('2100 / 2000\u00a0kcal'), findsOneWidget);
    expect(find.text('110 / 250\u00a0g'), findsOneWidget);
    for (final name in ['Energy', 'Carbs', 'Fat', 'Protein']) {
      expect(find.text(name), findsOneWidget, reason: name);
    }
    expect(find.textContaining('carbs g'), findsNothing);
    final span =
        (tester.widget<Text>(kcal).textSpan! as TextSpan).children!.first
            as TextSpan;
    expect(span.style!.color, isNot(AppPalette.light.fat));
    expect(
      find.bySemanticsLabel('Energy 2100 of 2000 kcal, 100 kcal over'),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Carbs 110 of 250 g'), findsOneWidget);
    semantics.dispose();
  });

  // The bar compares like with like: a kJ goal against kcal eaten filled
  // a 1900 of 2000 kcal day a quarter.
  testWidgets('the energy bar fills the same in kJ', (tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => EnergyUnitProvider(usesKilojoules: true),
        child: _app(
          TodayAfterAdding(
            day: DateTime(2026, 10, 25),
            kcal: 0,
            carbs: 0,
            fat: 0,
            protein: 0,
            load: (_) async => (
              eaten: (kcal: 1900.0, carbs: 100.0, fat: 50.0, protein: 60.0),
              goal: (kcal: 2000.0, carbs: 250.0, fat: 70.0, protein: 120.0),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('kJ', findRichText: true), findsWidgets);
    // the energy column's eaten part, of 1000
    final eaten = tester.widget<Flexible>(find.byType(Flexible).first);
    expect(eaten.flex, 950);
  });

  group('the bottom bar', () {
    setUp(() {
      GetIt.instance
        ..registerFactory<GetIntakeUsecase>(_NothingLogged.new)
        ..registerFactory<HomeBloc>(_HomeBloc.new)
        ..registerFactory<DiaryBloc>(_DiaryBloc.new)
        ..registerFactory<CalendarDayBloc>(_CalendarDayBloc.new);
    });
    tearDown(() => GetIt.instance.reset());

    testWidgets('Add names the amount and logs to the meal picked beside it', (
      tester,
    ) async {
      final bloc = _RecordingBloc();
      addTearDown(bloc.close);
      final amount = TextEditingController(text: '100');
      await tester.pumpWidget(
        _app(
          MealDetailBottomSheet(
            product: _toast,
            day: DateTime(2026, 10, 25),
            intakeTypeEntity: IntakeTypeEntity.breakfast,
            quantityTextController: amount,
            mealDetailBloc: bloc,
            selectedUnit: 'g',
            onQuantityOrUnitChanged: (_, _) {},
          ),
        ),
      );
      expect(find.text('Add 100 g'), findsOneWidget);
      amount.text = '';
      await tester.pump();
      expect(find.text('Add'), findsOneWidget);
      amount.text = '150';
      await tester.pump();
      expect(find.text('Add 150 g'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('meal-detail-meal')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dinner').last);
      await tester.pumpAndSettle();
      expect(find.text('Dinner'), findsOneWidget);

      await tester.tap(find.text('Add 150 g'));
      await tester.pumpAndSettle();
      expect(bloc.logged.map((l) => l.$1), [IntakeTypeEntity.dinner]);
      expect(find.text('Added to Dinner'), findsOneWidget);
    });

    // Above 1.5x text the meal is picked on the page and Add is pinned: two
    // parts of one sheet, one meal between them.
    // The page's amount and the pinned bar, sharing the meal.
    Future<(_RecordingBloc, TextEditingController, List<String?>)> pumpParts(
      WidgetTester tester,
    ) async {
      final bloc = _RecordingBloc();
      addTearDown(bloc.close);
      final amount = TextEditingController(text: '100');
      final type = ValueNotifier(IntakeTypeEntity.breakfast);
      addTearDown(type.dispose);
      final changes = <String?>[];
      MealDetailBottomSheet part(FoodSheetPart part) => MealDetailBottomSheet(
        key: ValueKey(part),
        product: _toast,
        day: DateTime(2026, 10, 25),
        intakeTypeEntity: IntakeTypeEntity.breakfast,
        quantityTextController: amount,
        mealDetailBloc: bloc,
        selectedUnit: 'g',
        onQuantityOrUnitChanged: (text, _) => changes.add(text),
        forkPart: part,
        forkType: type,
      );
      await tester.pumpWidget(
        _app(
          Column(
            children: [
              part(FoodSheetPart.amount),
              const Spacer(),
              part(FoodSheetPart.addBar),
            ],
          ),
        ),
      );
      return (bloc, amount, changes);
    }

    testWidgets('the pinned Add logs to the meal picked on the page', (
      tester,
    ) async {
      final (bloc, amount, changes) = await pumpParts(tester);
      Finder inPart(FoodSheetPart p, Finder f) =>
          find.descendant(of: find.byKey(ValueKey(p)), matching: f);
      final meal = find.byKey(const ValueKey('meal-detail-meal'));
      expect(inPart(FoodSheetPart.amount, meal), findsOneWidget);
      expect(inPart(FoodSheetPart.addBar, meal), findsNothing);
      final add = find.bySemanticsIdentifier('meal-detail-add');
      expect(inPart(FoodSheetPart.amount, add), findsNothing);
      expect(inPart(FoodSheetPart.addBar, add), findsOneWidget);

      // one listener on the amount, not one a part
      amount.text = '150';
      await tester.pump();
      expect(changes, ['150']);
      expect(find.text('Add 150 g'), findsOneWidget);

      await tester.tap(meal);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dinner').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add 150 g'));
      await tester.pumpAndSettle();
      expect(bloc.logged.map((l) => l.$1), [IntakeTypeEntity.dinner]);
    });

    testWidgets('the pinned basket takes the meal picked on the page', (
      tester,
    ) async {
      await pumpParts(tester);
      await tester.tap(find.byKey(const ValueKey('meal-detail-meal')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dinner').last);
      await tester.pumpAndSettle();
      addTearDown(FoodBasket.instance.clear);
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey(FoodSheetPart.addBar)),
          matching: find.byTooltip('Add to basket'),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        FoodBasket.instance.itemsFor(
          IntakeTypeEntity.dinner,
          DateTime(2026, 10, 25),
        ),
        hasLength(1),
      );
    });
  });
}
