// The Add flow audit's findings on the Add food search screen.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:opennutritracker/core/domain/entity/app_theme_entity.dart';
import 'package:opennutritracker/core/domain/entity/config_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/domain/usecase/add_intake_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/add_tracked_day_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_intake_usecase.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/app_theme.dart';
import 'package:opennutritracker/core/utils/navigation_options.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/usecase/search_products_usecase.dart';
import 'package:opennutritracker/features/add_meal/presentation/add_meal_type.dart';
import 'package:opennutritracker/features/add_meal/presentation/bloc/add_meal_bloc.dart';
import 'package:opennutritracker/features/add_meal/presentation/bloc/favourite_meal_bloc.dart';
import 'package:opennutritracker/features/add_meal/presentation/bloc/favourite_toggle_bloc.dart';
import 'package:opennutritracker/features/add_meal/presentation/bloc/food_bloc.dart';
import 'package:opennutritracker/features/add_meal/presentation/bloc/products_bloc.dart';
import 'package:opennutritracker/features/add_meal/presentation/bloc/recent_meal_bloc.dart';
import 'package:opennutritracker/features/add_meal/presentation/widgets/quick_add_bottom_sheet.dart';
import 'package:opennutritracker/features/diary/presentation/bloc/calendar_day_bloc.dart';
import 'package:opennutritracker/features/diary/presentation/bloc/diary_bloc.dart';
import 'package:opennutritracker/features/home/presentation/bloc/home_bloc.dart';
import 'package:opennutritracker/fork/display/contrast.dart';
import 'package:opennutritracker/fork/layout/width_cap.dart';
import 'package:opennutritracker/fork/screens/add_meal/add_meal_screen.dart';
import 'package:opennutritracker/fork/screens/add_meal/meal_item_card.dart';
import 'package:opennutritracker/generated/l10n.dart';

import '../../../helpers/fake_favourites.dart';
import '../../../helpers/test_l10n.dart';

class _Intakes implements GetIntakeUsecase {
  final List<IntakeEntity> recent;
  final Completer<void>? hold;

  _Intakes(this.recent, {this.hold});

  @override
  Future<List<IntakeEntity>> getRecentIntake() async {
    await hold?.future;
    return recent;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Unexpected call: ${invocation.memberName}');
}

class _Config implements GetConfigUsecase {
  @override
  Future<ConfigEntity> getConfig() async =>
      const ConfigEntity(true, true, false, AppThemeEntity.system);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Unexpected call: ${invocation.memberName}');
}

class _Search implements SearchProductsUseCase {
  List<MealEntity> food = const [];

  @override
  Future<SearchProductsResult> searchOFFProductsByString(
    String searchString, {
    bool skipRemote = false,
  }) async {
    return const SearchProductsResult(meals: [], remoteSourceEmpty: false);
  }

  @override
  Future<SearchProductsResult> searchFDCFoodByString(
    String searchString, {
    bool skipRemote = false,
    bool forResolution = false,
  }) async {
    return SearchProductsResult(meals: food, remoteSourceEmpty: false);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Unexpected call: ${invocation.memberName}');
}

/// Counts the loads asked of it and stays in its first state, as a bloc
/// still waiting would.
class _CountingRecent extends RecentMealBloc {
  int loads = 0;

  _CountingRecent() : super(_Intakes(const []), _Config());

  @override
  void add(RecentMealEvent event) {
    if (event is LoadRecentMealEvent) loads++;
  }
}

class _CountingFavourites extends FavouriteMealBloc {
  int loads = 0;

  _CountingFavourites(FakeFavourites favourites)
    : super(favourites.get, _Config());

  @override
  void add(FavouriteMealEvent event) {
    if (event is LoadFavouriteMealEvent) loads++;
  }
}

class _FakeAdd extends Fake implements AddIntakeUsecase {
  @override
  Future<void> addIntake(IntakeEntity intake) async {}
}

class _SavedTracked implements AddTrackedDayUsecase {
  @override
  Future<bool> hasTrackedDay(DateTime day) async => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}

class _Home extends Fake implements HomeBloc {
  @override
  void add(HomeEvent event) {}
}

class _Diary extends Fake implements DiaryBloc {
  @override
  void add(DiaryEvent event) {}
}

class _Calendar extends Fake implements CalendarDayBloc {
  @override
  void add(CalendarDayEvent event) {}
}

IntakeEntity _intake(String name) => IntakeEntity(
  id: name,
  unit: 'g',
  amount: 100,
  type: IntakeTypeEntity.lunch,
  meal: _meal(name),
  dateTime: DateTime(2026, 10, 1),
);

MealEntity _meal(String name) => MealEntity(
  code: name,
  name: name,
  url: null,
  mealQuantity: null,
  mealUnit: 'g',
  servingQuantity: null,
  servingUnit: 'g',
  servingSize: null,
  nutriments: MealNutrimentsEntity.empty(),
  source: MealSourceEntity.fdc,
);

final getIt = GetIt.instance;

Future<void> _register({
  List<IntakeEntity> recent = const [],
  Completer<void>? holdRecent,
  _Search? search,
  RecentMealBloc? recentBloc,
  FavouriteMealBloc Function(FakeFavourites)? favouritesBloc,
}) async {
  await getIt.reset();
  final config = _Config();
  final s = search ?? _Search();
  final favourites = FakeFavourites();
  addTearDown(favourites.dispose);
  getIt
    ..registerFactory<AddMealBloc>(() => AddMealBloc(config))
    ..registerFactory<ProductsBloc>(() => ProductsBloc(s, config))
    ..registerFactory<FoodBloc>(() => FoodBloc(s, config))
    ..registerFactory<RecentMealBloc>(
      () =>
          recentBloc ??
          RecentMealBloc(_Intakes(recent, hold: holdRecent), config),
    )
    ..registerFactory<FavouriteMealBloc>(
      () =>
          favouritesBloc?.call(favourites) ??
          FavouriteMealBloc(favourites.get, config),
    )
    ..registerFactory<FavouriteToggleBloc>(
      () => FavouriteToggleBloc(favourites.get, favourites.toggle),
    );
}

Future<void> _pump(
  WidgetTester tester, {
  Size size = const Size(411, 891),
  double keyboard = 0,
  Brightness brightness = Brightness.light,
  bool settle = true,
}) async {
  tester.view
    ..devicePixelRatio = 1
    ..physicalSize = size
    ..viewInsets = FakeViewPadding(bottom: keyboard);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(
        brightness == Brightness.dark ? AppPalette.dark : AppPalette.light,
      ),
      localizationsDelegates: const [
        S.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: S.supportedLocales,
      onGenerateRoute: (settings) =>
          settings.name == NavigationOptions.mainRoute
          ? MaterialPageRoute<void>(builder: (_) => const Text('fresh home'))
          : MaterialPageRoute<void>(
              settings: RouteSettings(
                name: settings.name,
                arguments: AddMealScreenArguments(
                  AddMealType.lunchType,
                  DateTime(2026, 10, 1),
                ),
              ),
              builder: (_) => const AddMealScreen(),
            ),
    ),
  );
  settle ? await tester.pumpAndSettle() : await tester.pump();
}

final _recents = [for (var i = 0; i < 10; i++) _intake('Food $i')];

void main() {
  tearDown(() => getIt.reset());

  testWidgets('the last result scrolls clear of a 300 dp keyboard', (
    tester,
  ) async {
    await _register(recent: _recents);
    await _pump(tester, keyboard: 300);

    final list = find.descendant(
      of: find.bySemanticsIdentifier('add-meal-recent-list'),
      matching: find.byType(Scrollable),
    );
    final position = tester.state<ScrollableState>(list.first).position;
    position.jumpTo(position.maxScrollExtent);
    await tester.pumpAndSettle();

    final last = find.textContaining('Food 9');
    expect(last, findsOneWidget);
    expect(tester.getRect(last).bottom, lessThanOrEqualTo(891 - 300));
  });

  testWidgets('dragging the results puts the keyboard away', (tester) async {
    await _register(recent: _recents);
    await _pump(tester);
    expect(tester.testTextInput.isVisible, isTrue);

    await tester.drag(find.textContaining('Food 3'), const Offset(0, -200));
    await tester.pumpAndSettle();
    expect(tester.testTextInput.isVisible, isFalse);
  });

  testWidgets('"Search results" is a heading', (tester) async {
    await _register(search: _Search()..food = [_meal('Apple')]);
    final handle = tester.ensureSemantics();
    await _pump(tester);
    await tester.enterText(find.byType(TextField).first, 'apple');
    await tester.pumpAndSettle();

    final heading = find.text(l10nEn.searchResultsLabel);
    expect(heading, findsOneWidget);
    expect(
      tester.getSemantics(heading),
      matchesSemantics(label: l10nEn.searchResultsLabel, isHeader: true),
    );
    handle.dispose();
  });

  testWidgets('spinners say Loading', (tester) async {
    final hold = Completer<void>();
    await _register(recent: _recents, holdRecent: hold);
    final handle = tester.ensureSemantics();
    await _pump(tester, settle: false);
    await tester.pump();
    expect(find.bySemanticsLabel('Loading'), findsOneWidget);

    // a search still under way
    await tester.enterText(find.byType(TextField).first, 'apple');
    await tester.pump();
    expect(find.bySemanticsLabel('Loading'), findsOneWidget);
    hold.complete();
    await tester.pumpAndSettle();
    handle.dispose();
  });

  testWidgets('a rebuild asks for no load: they are not sent from builders', (
    tester,
  ) async {
    final recent = _CountingRecent();
    late _CountingFavourites favourites;
    await _register(
      recentBloc: recent,
      favouritesBloc: (f) => favourites = _CountingFavourites(f),
    );
    await _pump(tester);
    final recentLoads = recent.loads;
    expect(recentLoads, greaterThan(0));
    // rebuilt by a new window size, as by a turn of the phone
    tester.view.physicalSize = const Size(420, 891);
    await tester.pump();
    tester.view.physicalSize = const Size(411, 880);
    await tester.pump();
    expect(recent.loads, recentLoads);

    await tester.tap(find.text(l10nEn.favouritesLabel));
    await tester.pump();
    final favouriteLoads = favourites.loads;
    tester.view.physicalSize = const Size(420, 891);
    await tester.pump();
    tester.view.physicalSize = const Size(411, 880);
    await tester.pump();
    expect(favourites.loads, favouriteLoads);
  });

  testWidgets('Quick add here stays on search, with the logged bar', (
    tester,
  ) async {
    await _register(recent: _recents);
    getIt
      ..registerSingleton<AddIntakeUsecase>(_FakeAdd())
      ..registerSingleton<AddTrackedDayUsecase>(_SavedTracked())
      ..registerSingleton<HomeBloc>(_Home())
      ..registerSingleton<DiaryBloc>(_Diary())
      ..registerSingleton<CalendarDayBloc>(_Calendar());
    await _pump(tester);
    await tester.enterText(find.byType(TextField).first, 'ri');
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('add-meal-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10nEn.quickAddCardLabel).last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.bySemanticsIdentifier('quick-add-energy'),
        matching: find.byType(TextField),
      ),
      '450',
    );
    await tester.pump();
    await tester.tap(find.bySemanticsIdentifier('quick-add-submit'));
    await tester.pumpAndSettle();

    expect(find.text('fresh home'), findsNothing);
    expect(find.byType(QuickAddBottomSheet), findsNothing);
    expect(find.byType(AddMealScreen), findsOneWidget);
    // the query is still there
    expect(find.text('ri'), findsOneWidget);
    expect(find.text('Undo'), findsOneWidget);
  });

  testWidgets('the menu uses rounded icons only', (tester) async {
    await _register();
    await _pump(tester);
    await tester.tap(find.byKey(const ValueKey('add-meal-menu')));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.playlist_add), findsNothing);
    expect(find.byIcon(Icons.add_circle_outline), findsNothing);
    expect(find.byIcon(Icons.playlist_add_rounded), findsOneWidget);
    expect(find.byIcon(Icons.add_circle_outline_rounded), findsOneWidget);
  });

  testWidgets('the chosen source chip has a fill of its own', (tester) async {
    await _register();
    await _pump(tester);
    Color fill(String label) {
      final ink = tester.widget<Ink>(
        find.descendant(
          of: find.widgetWithText(ChoiceChip, label),
          matching: find.byType(Ink),
        ),
      );
      return (ink.decoration! as ShapeDecoration).color!;
    }

    expect(
      contrastRatio(
        fill(l10nEn.recentlyAddedLabel),
        fill(l10nEn.allItemsLabel),
      ),
      greaterThanOrEqualTo(3),
    );
  });

  testWidgets('on a wide window the results keep a phone column', (
    tester,
  ) async {
    await _register(recent: _recents);
    await _pump(tester, size: const Size(1280, 800));
    expect(
      tester.getSize(find.byType(MealItemCard).first).width,
      lessThanOrEqualTo(WidthCap.maxWidth),
    );
  });
}
