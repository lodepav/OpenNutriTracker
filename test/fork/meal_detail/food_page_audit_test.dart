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
import 'package:provider/provider.dart';

import 'package:opennutritracker/features/meal_detail/presentation/widgets/off_disclaimer.dart';
import 'package:opennutritracker/fork/display/contrast.dart';
import 'package:opennutritracker/fork/layout/width_cap.dart';

import '../../helpers/fake_favourites.dart';
import '../../helpers/ux_checks.dart' show pumpOnPhone;

// The Add flow audit's findings on the food page.

MealEntity _food({
  MealSourceEntity source = MealSourceEntity.off,
  String? photo,
}) => MealEntity(
  code: 'audit-roll',
  name: 'Bread roll',
  brands: 'Baker',
  url: null,
  mealQuantity: null,
  mealUnit: 'g',
  servingQuantity: 60,
  servingUnit: 'g',
  servingSize: '1 roll (60 g)',
  mainImageUrl: photo,
  nutriments: const MealNutrimentsEntity(
    energyKcal100: 250,
    carbohydrates100: 48,
    fat100: 3,
    proteins100: 9,
    sugars100: 3,
    saturatedFat100: 1,
    fiber100: 3,
  ),
  source: source,
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

  Future<void> pumpPage(
    WidgetTester tester, {
    Size size = const Size(1080, 2340),
    MealEntity? meal,
  }) async {
    await pumpOnPhone(
      tester,
      ChangeNotifierProvider(
        create: (_) => EnergyUnitProvider(usesKilojoules: false),
        child: Navigator(
          onGenerateRoute: (_) => MaterialPageRoute<void>(
            settings: RouteSettings(
              arguments: MealDetailScreenArguments(
                meal ?? _food(),
                IntakeTypeEntity.breakfast,
                DateTime(2026, 10, 25),
                false,
              ),
            ),
            builder: (_) => const MealDetailScreen(),
          ),
        ),
      ),
      textScale: 1,
    );
    tester.view.physicalSize = size;
    await tester.pumpAndSettle();
  }

  ScrollPosition page(WidgetTester tester) => tester
      .state<ScrollableState>(
        find
            .descendant(
              of: find.byType(CustomScrollView),
              matching: find.byType(Scrollable),
            )
            .first,
      )
      .position;

  testWidgets('the amount field says what it is and in what unit', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pumpPage(tester);
    final field = find.descendant(
      of: find.byKey(const ValueKey('amount-field')),
      matching: find.byType(TextField),
    );
    final unit = tester.widget<TextField>(field).decoration!.suffixText;
    expect(unit, isNotNull);
    expect(
      tester.getSemantics(field),
      isSemantics(label: 'Amount in $unit', isTextField: true),
    );
    semantics.dispose();
  });

  testWidgets('with Remove animations on, an amount change jumps to the top', (
    tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await pumpPage(tester);
    final position = page(tester);
    position.jumpTo(position.maxScrollExtent);
    await tester.pump();
    expect(position.pixels, greaterThan(0));

    await tester.tap(find.bySemanticsIdentifier('amount-plus'));
    await tester.pump();
    expect(position.pixels, 0);
  });

  testWidgets('the chosen unit has a fill of its own', (tester) async {
    await pumpPage(tester);
    final chips = tester.widgetList<ChoiceChip>(
      find.descendant(
        of: find.byType(AmountPicker),
        matching: find.byType(ChoiceChip),
      ),
    );
    Color fill(ChoiceChip chip) {
      final ink = tester.widget<Ink>(
        find.descendant(of: find.byWidget(chip), matching: find.byType(Ink)),
      );
      return (ink.decoration! as ShapeDecoration).color!;
    }

    final chosen = chips.singleWhere((c) => c.selected);
    final other = chips.firstWhere((c) => !c.selected);
    expect(contrastRatio(fill(chosen), fill(other)), greaterThanOrEqualTo(3));
  });

  testWidgets('the header photo is decoded at its shown size', (tester) async {
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FoodPageHeader(meal: _food(photo: 'https://x.test/a.jpg')),
        ),
      ),
    );
    final image = tester.widget<Image>(find.byType(Image)).image;
    expect(image, isA<ResizeImage>());
    expect((image as ResizeImage).width, 56 * 3);
  });

  testWidgets('on a wide window the page keeps a phone column', (tester) async {
    await pumpPage(tester, size: const Size(1280 * 2.625, 800 * 2.625));
    expect(
      tester.getSize(find.byType(FoodMacroRing)).width,
      lessThanOrEqualTo(WidthCap.maxWidth),
    );
  });

  testWidgets('scrolled to the end, the page clears the pinned sheet', (
    tester,
  ) async {
    await pumpPage(tester);
    final position = page(tester);
    position.jumpTo(position.maxScrollExtent);
    await tester.pumpAndSettle();
    final sheet = tester.getRect(find.byKey(const ValueKey(FoodSheetPart.all)));
    final end = tester.getRect(find.byType(OffDisclaimer));
    expect(end.bottom, lessThanOrEqualTo(sheet.top));
  });

  testWidgets('in landscape the page keeps room under the app bar', (
    tester,
  ) async {
    await pumpPage(tester, size: const Size(2340, 1080));
    final screen = tester.getRect(find.byType(MealDetailScreen));
    final bar = tester.getRect(find.byType(AppBar));
    final pinned = find.byKey(const ValueKey(FoodSheetPart.all));
    final sheetTop = pinned.evaluate().isEmpty
        ? tester.getRect(find.byKey(const ValueKey(FoodSheetPart.addBar))).top
        : tester.getRect(pinned).top;
    expect(sheetTop - bar.bottom, greaterThanOrEqualTo(screen.height / 2));
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
