import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:opennutritracker/core/data/data_source/remote_search_cache_data_source.dart';
import 'package:opennutritracker/core/domain/entity/app_theme_entity.dart';
import 'package:opennutritracker/core/domain/entity/config_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/domain/entity/tracked_day_entity.dart';
import 'package:opennutritracker/core/domain/usecase/add_intake_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/add_tracked_day_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_intake_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_kcal_goal_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_macro_goal_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_tracked_day_usecase.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/features/add_meal/data/repository/products_repository.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/features/add_meal/presentation/bloc/favourite_toggle_bloc.dart';
import 'package:opennutritracker/features/diary/presentation/bloc/calendar_day_bloc.dart';
import 'package:opennutritracker/features/diary/presentation/bloc/diary_bloc.dart';
import 'package:opennutritracker/features/home/presentation/bloc/home_bloc.dart';
import 'package:opennutritracker/features/meal_detail/meal_detail_screen.dart';
import 'package:opennutritracker/features/meal_detail/presentation/bloc/meal_detail_bloc.dart';
import 'package:opennutritracker/fork/amounts/amount_picker.dart';
import 'package:opennutritracker/fork/meal_detail/food_page.dart';
import 'package:opennutritracker/fork/meal_detail/nutrients_table.dart';
import 'package:provider/provider.dart';

import '../../helpers/fake_favourites.dart';
import '../../helpers/ux_checks.dart';

// Critique P1: at 2x the fixed amount panel filled the page. Above 1.5x the
// amount goes onto the page and only Add stays pinned.

final _roll = MealEntity(
  code: 'large-text-roll',
  name: 'Chicken breast, roasted, skin not eaten',
  brands: 'A brand with a long name',
  url: null,
  mealQuantity: null,
  mealUnit: 'g',
  servingQuantity: 60,
  servingUnit: 'g',
  servingSize: '1 serving (60 g)',
  nutriments: const MealNutrimentsEntity(
    energyKcal100: 165,
    carbohydrates100: 0,
    fat100: 3.6,
    proteins100: 31,
    sugars100: 0,
    saturatedFat100: 1,
    fiber100: 0,
  ),
  source: MealSourceEntity.custom,
);

void main() {
  final getIt = GetIt.instance;

  setUp(() {
    getIt.registerLazySingleton<MealDetailBloc>(
      () => MealDetailBloc(
        _Add(),
        _AddTracked(),
        _Kcal(),
        _Macro(),
        _Tracked(),
        _Products(),
        _Cache(),
      ),
    );
    getIt
      ..registerLazySingleton<GetConfigUsecase>(_Config.new)
      ..registerLazySingleton<GetIntakeUsecase>(_Intakes.new)
      ..registerLazySingleton<GetTrackedDayUsecase>(_Tracked.new)
      // the day after adding reads the goals through it, all set on the day
      ..registerLazySingleton<GetMacroGoalUsecase>(_Macro.new)
      ..registerLazySingleton<CacheManager>(_Images.new)
      ..registerLazySingleton<HomeBloc>(_Home.new)
      ..registerLazySingleton<DiaryBloc>(_Diary.new)
      ..registerLazySingleton<CalendarDayBloc>(_Calendar.new);
    final favourites = FakeFavourites();
    getIt.registerFactory<FavouriteToggleBloc>(
      () => FavouriteToggleBloc(favourites.get, favourites.toggle),
    );
  });

  tearDown(() => getIt.reset());

  Future<void> pumpPage(WidgetTester tester, {double textScale = 2}) async {
    await pumpOnPhone(
      tester,
      ChangeNotifierProvider(
        create: (_) => EnergyUnitProvider(usesKilojoules: false),
        child: Navigator(
          onGenerateRoute: (_) => MaterialPageRoute<void>(
            settings: RouteSettings(
              arguments: MealDetailScreenArguments(
                _roll,
                IntakeTypeEntity.breakfast,
                DateTime(2026, 10, 25),
                false,
              ),
            ),
            builder: (_) => const MealDetailScreen(),
          ),
        ),
      ),
      textScale: textScale,
    );
    await tester.pumpAndSettle();
  }

  Finder onPage(Finder f) =>
      find.descendant(of: find.byType(CustomScrollView), matching: f);
  final pinned = find.byKey(const ValueKey(FoodSheetPart.addBar));

  testWidgets('at 2x on a 412 dp phone the amount scrolls with the page and '
      'Add stays pinned', (tester) async {
    await pumpPage(tester);
    expect(tester.takeException(), isNull);

    expect(onPage(find.byType(AmountPicker)), findsOneWidget);
    expect(
      onPage(find.byKey(const ValueKey('meal-detail-meal'))),
      findsOneWidget,
    );
    expect(pinned, findsOneWidget);
    expect(
      find.descendant(of: pinned, matching: find.byType(AmountPicker)),
      findsNothing,
    );
    final add = find.descendant(
      of: pinned,
      matching: find.bySemanticsIdentifier('meal-detail-add'),
    );
    expect(add, findsOneWidget);
    // the pinned bar is a strip, not three quarters of the screen
    final screen = tester.getSize(find.byType(MealDetailScreen));
    expect(tester.getSize(pinned).height, lessThan(screen.height / 4));
    expect(cutText(tester), isEmpty);

    // A step changes Add's amount and leaves the page where it is.
    final position = tester
        .state<ScrollableState>(onPage(find.byType(Scrollable)).first)
        .position;
    final plus = find.bySemanticsIdentifier('amount-plus');
    await tester.ensureVisible(plus);
    await tester.pumpAndSettle();
    final offset = position.pixels;
    expect(offset, greaterThan(0));
    final before = tester.widget<Text>(
      find.descendant(of: add, matching: find.byType(Text)),
    );
    await tester.tap(plus);
    await tester.pumpAndSettle();
    final after = tester.widget<Text>(
      find.descendant(of: add, matching: find.byType(Text)),
    );
    expect(after.data, isNot(before.data));
    expect(position.pixels, offset);
    expect(tester.takeException(), isNull);
  });

  testWidgets('at 2x the whole page shows in full and is accessible', (
    tester,
  ) async {
    await pumpPage(tester);
    // tall enough to build what a phone scrolls to
    tester.view.physicalSize = const Size(1080, 7020);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(onPage(find.byType(FoodNutrientsTable)), findsOneWidget);
    expect(
      onPage(find.textContaining('after adding', findRichText: true)),
      findsOneWidget,
    );
    expect(find.text('Energy'), findsWidgets);
    expect(cutText(tester), isEmpty);
    await expectAccessible(tester);
  });

  // Critique P2: the header was read as one run of lines.
  testWidgets('on the page the header, a total and a row read as words', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pumpPage(tester);
    tester.view.physicalSize = const Size(1080, 7020);
    await tester.pumpAndSettle();
    final header = tester.getSemantics(
      find.descendant(
        of: find.byType(FoodPageHeader),
        matching: find.text(_roll.name!),
      ),
    );
    expect(
      header,
      isSemantics(
        label:
            'Chicken breast, roasted, skin not eaten. A brand with a long '
            'name. 165 kcal per 100 g',
        isHeader: true,
      ),
    );
    // the meal's button and the headings are nodes of their own, not one
    // button the whole page merged into
    expect(
      tester.getSemantics(find.text('That day after adding')),
      isSemantics(label: 'That day after adding', isHeader: true),
    );
    expect(
      tester.getSemantics(find.text('Per 100 g')),
      isSemantics(label: 'Per 100 g'),
    );
    // 69 g eaten and the amount's fat, of 70 g
    expect(
      find.bySemanticsLabel(RegExp(r'^Fat \d+ of 70 g, \d+ g over$')),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Protein 31 g'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('at 1x the amount stays in the bottom sheet', (tester) async {
    await pumpPage(tester, textScale: 1);
    expect(onPage(find.byType(AmountPicker)), findsNothing);
    expect(find.byType(AmountPicker), findsOneWidget);
    expect(pinned, findsNothing);
    expect(find.byKey(const ValueKey(FoodSheetPart.all)), findsOneWidget);
  });
}

class _Fake {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Unexpected call: ${invocation.memberName}');
}

class _Add extends _Fake implements AddIntakeUsecase {}

class _AddTracked extends _Fake implements AddTrackedDayUsecase {}

class _Kcal extends _Fake implements GetKcalGoalUsecase {}

class _Macro extends _Fake implements GetMacroGoalUsecase {}

class _Products extends _Fake implements ProductsRepository {}

class _Images extends _Fake implements CacheManager {
  @override
  Stream<FileResponse> getFileStream(
    String url, {
    String? key,
    Map<String, String>? headers,
    bool withProgress = false,
  }) => const Stream<FileResponse>.empty();
}

class _Config extends _Fake implements GetConfigUsecase {
  @override
  Future<ConfigEntity> getConfig() async =>
      const ConfigEntity(true, true, false, AppThemeEntity.system);
}

class _Tracked extends _Fake implements GetTrackedDayUsecase {
  @override
  Future<TrackedDayEntity?> getTrackedDay(DateTime day) async =>
      TrackedDayEntity(
        day: day,
        calorieGoal: 2000,
        caloriesTracked: 1900,
        carbsGoal: 250,
        carbsTracked: 100,
        fatGoal: 70,
        fatTracked: 69,
        proteinGoal: 120,
        proteinTracked: 60,
      );
}

class _Cache extends _Fake implements RemoteSearchCacheDataSource {
  @override
  Future<void> touch(String barcode) async {}
}

class _Intakes extends _Fake implements GetIntakeUsecase {
  @override
  Future<List<IntakeEntity>> getBreakfastIntakeByDay(
    DateTime day, {
    int dayStartOffsetHours = 0,
    int dayStartOffsetMinutes = 0,
  }) async => [];
}

class _Home extends _Fake implements HomeBloc {
  @override
  void add(HomeEvent event) {}
}

class _Diary extends _Fake implements DiaryBloc {
  @override
  void add(DiaryEvent event) {}
}

class _Calendar extends _Fake implements CalendarDayBloc {
  @override
  void add(CalendarDayEvent event) {}
}
