import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:opennutritracker/core/data/data_source/remote_search_cache_data_source.dart';
import 'package:opennutritracker/core/data/dbo/meal_dbo.dart';
import 'package:opennutritracker/core/domain/entity/app_theme_entity.dart';
import 'package:opennutritracker/core/domain/entity/config_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/core/utils/navigation_options.dart';
import 'package:opennutritracker/features/add_meal/data/repository/products_repository.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/features/add_meal/presentation/add_meal_type.dart';
import 'package:opennutritracker/features/add_meal/presentation/bloc/favourite_toggle_bloc.dart';
import 'package:opennutritracker/features/meal_detail/meal_detail_screen.dart';
import 'package:opennutritracker/features/meal_detail/presentation/bloc/meal_detail_bloc.dart';
import 'package:opennutritracker/fork/add/one_tap_log.dart';
import 'package:opennutritracker/fork/amounts/remembered_amounts.dart';
import 'package:opennutritracker/fork/screens/add_meal/meal_item_card.dart';
import 'package:opennutritracker/generated/l10n.dart';

import '../../fixture/intake_entity_fixtures.dart';
import '../../helpers/fake_favourites.dart';

MealEntity _food({
  String? name = 'Oats',
  double? serving,
  String unit = 'g',
  MealSourceEntity source = MealSourceEntity.custom,
  bool detailed = false,
  double? carbs = 60,
}) => MealEntity(
  code: 'oats',
  name: name,
  url: null,
  mealQuantity: null,
  mealUnit: unit,
  servingQuantity: serving,
  servingUnit: unit,
  servingSize: null,
  nutriments: MealNutrimentsEntity(
    energyKcal100: 380,
    carbohydrates100: carbs,
    fat100: 7,
    proteins100: 13,
    sugars100: 1,
    saturatedFat100: 1,
    fiber100: 10,
  ),
  source: source,
  detailed: detailed,
);

MealEntity _thin() => _food(source: MealSourceEntity.off);

MealEntity _full({double? carbs = 60}) => _food(
  serving: 40,
  source: MealSourceEntity.off,
  detailed: true,
  carbs: carbs,
);

class _Config extends Fake implements GetConfigUsecase {
  @override
  Future<ConfigEntity> getConfig() async =>
      const ConfigEntity(true, true, false, AppThemeEntity.system);
}

class _Cache extends Fake implements RemoteSearchCacheDataSource {
  MealDBO? held;
  final written = <String?>[];

  @override
  MealDBO? getDetailedByBarcode(String barcode) => held;

  @override
  Future<void> cache(MealDBO meal) async => written.add(meal.code);
}

class _Products extends Fake implements ProductsRepository {
  Future<MealEntity> Function() lookup = () async => _full();
  var lookups = 0;

  @override
  Future<MealEntity> getOFFProductByBarcode(String barcode) {
    lookups++;
    return lookup();
  }
}

class _Bloc extends Fake implements MealDetailBloc {
  final logged = <IntakeEntity>[];

  @override
  Future<IntakeEntity?> addIntake(
    BuildContext context,
    String unit,
    String amountText,
    IntakeTypeEntity type,
    MealEntity meal,
    DateTime day,
  ) async {
    final intake = IntakeEntity(
      id: 'written',
      unit: unit,
      amount: double.parse(amountText),
      type: type,
      meal: meal,
      dateTime: day,
    );
    logged.add(intake);
    return intake;
  }
}

void main() {
  group('the amount the plus logs', () {
    test('a recent at its latest entry, as logged', () {
      final last = intakeOf('oats', 45);
      expect(oneTapAmount(_food(serving: 40), last: last), (
        unit: 'g',
        amount: 45,
      ));
    });

    test('else the amount last logged of the food', () {
      expect(
        oneTapAmount(
          _food(serving: 40),
          remembered: (unit: 'serving', quantity: '1,5'),
        ),
        (unit: 'serving', amount: 60),
      );
    });

    test('a remembered serving the food cannot scale is passed over', () {
      expect(
        oneTapAmount(_food(), remembered: (unit: 'serving', quantity: '2')),
        (unit: 'g', amount: 100),
      );
    });

    test('else a serving, or 100 g when raw units are the default', () {
      expect(oneTapAmount(_food(serving: 40)), (unit: 'serving', amount: 40));
      expect(oneTapAmount(_food(serving: 40), rawUnits: true), (
        unit: 'g',
        amount: 100,
      ));
      expect(oneTapAmount(_food(unit: 'ml')), (unit: 'ml', amount: 100));
    });

    test('an ounce in imperial units', () {
      final amount = oneTapAmount(_food(), imperial: true);
      expect(amount.unit, 'oz');
      expect(amount.amount, closeTo(28.35, 0.01));
    });
  });

  group('the record the plus logs', () {
    late _Cache cache;
    late _Products products;

    setUp(() {
      cache = _Cache();
      products = _Products();
    });

    test('a food with its full record stays as it is', () async {
      final meal = _full();
      expect(await hydratedForLog(meal, cache, products), same(meal));
      expect(products.lookups, 0);
    });

    test('a search hit from the cache, without the network', () async {
      cache.held = MealDBO.fromMealEntity(_full());
      final meal = await hydratedForLog(_thin(), cache, products);
      expect(meal.detailed, isTrue);
      expect(products.lookups, 0);
    });

    test('else from the network, and caches it', () async {
      final meal = await hydratedForLog(_thin(), cache, products);
      expect(meal.detailed, isTrue);
      expect(cache.written, ['oats']);
    });

    test('a failed lookup keeps the search hit', () async {
      products.lookup = () async => throw Exception('offline');
      final thin = _thin();
      expect(await hydratedForLog(thin, cache, products), same(thin));
    });

    test('a slow lookup keeps the search hit', () async {
      products.lookup = () => Completer<MealEntity>().future;
      final thin = _thin();
      expect(
        await hydratedForLog(
          thin,
          cache,
          products,
          wait: const Duration(milliseconds: 1),
        ),
        same(thin),
      );
    });
  });

  group('the plus on a search hit', () {
    late List<Object?> opened;
    late _Products products;
    late _Bloc bloc;

    setUp(() async {
      opened = [];
      products = _Products();
      bloc = _Bloc();
      await GetIt.instance.reset();
      final favourites = FakeFavourites();
      GetIt.instance
        ..registerFactory<FavouriteToggleBloc>(
          () => FavouriteToggleBloc(favourites.get, favourites.toggle),
        )
        ..registerSingleton<GetConfigUsecase>(_Config())
        ..registerSingleton<RemoteSearchCacheDataSource>(_Cache())
        ..registerSingleton<ProductsRepository>(products)
        ..registerSingleton<MealDetailBloc>(bloc);
      RememberedAmounts.current = RememberedAmounts(
        () async => throw StateError('no box'),
      );
    });

    tearDown(() async {
      RememberedAmounts.current = RememberedAmounts();
      await GetIt.instance.reset();
    });

    Future<void> pump(WidgetTester tester, MealEntity meal) =>
        tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: const [S.delegate],
            onGenerateRoute: (settings) {
              opened.add(settings.arguments);
              return MaterialPageRoute(builder: (_) => const Scaffold());
            },
            home: Scaffold(
              body: MealItemCard(
                day: DateTime(2026, 10, 30),
                mealEntity: meal,
                addMealType: AddMealType.lunchType,
                usesImperialUnits: false,
              ),
            ),
          ),
        );

    Future<void> tapPlus(WidgetTester tester) async {
      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pumpAndSettle();
    }

    testWidgets('logs the full record at its serving', (tester) async {
      await pump(tester, _thin());
      await tapPlus(tester);
      final logged = bloc.logged.single;
      expect(logged.meal.detailed, isTrue);
      expect((logged.unit, logged.amount), ('serving', 40));
      expect(find.text('Added Oats, 40 g, to Lunch'), findsOneWidget);
    });

    testWidgets('the bar leaves out a name the food lacks', (tester) async {
      products.lookup = () async => _food(
        name: null,
        serving: 40,
        source: MealSourceEntity.off,
        detailed: true,
      );
      await pump(tester, _thin());
      await tapPlus(tester);
      expect(find.text('Added 40 g to Lunch'), findsOneWidget);
    });

    testWidgets('logs the search hit when the lookup fails', (tester) async {
      products.lookup = () async => throw Exception('offline');
      await pump(tester, _thin());
      await tapPlus(tester);
      final logged = bloc.logged.single;
      expect(logged.meal.detailed, isFalse);
      expect((logged.unit, logged.amount), ('g', 100));
    });

    testWidgets('opens the page when the food lacks what it needs', (
      tester,
    ) async {
      products.lookup = () async => _full(carbs: null);
      await pump(tester, _thin());
      await tapPlus(tester);
      expect(bloc.logged, isEmpty);
      final page = opened.single as MealDetailScreenArguments;
      expect(page.mealEntity.detailed, isTrue);
      expect(page.intakeTypeEntity, IntakeTypeEntity.lunch);
    });

    testWidgets('a second tap during the lookup logs once', (tester) async {
      final lookup = Completer<MealEntity>();
      products.lookup = () => lookup.future;
      await pump(tester, _thin());
      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pump();
      lookup.complete(_full());
      await tester.pumpAndSettle();
      expect(products.lookups, 1);
      expect(bloc.logged, hasLength(1));
    });
  });

  group('the row', () {
    late List<String> calls;

    setUp(() async {
      calls = [];
      await GetIt.instance.reset();
      final favourites = FakeFavourites();
      GetIt.instance.registerFactory<FavouriteToggleBloc>(
        () => FavouriteToggleBloc(favourites.get, favourites.toggle),
      );
      logFromRow =
          (
            context, {
            required MealEntity meal,
            required IntakeTypeEntity type,
            required DateTime day,
            required bool imperial,
            IntakeEntity? last,
          }) async =>
              calls.add('log ${meal.name} ${type.name} ${last?.amount}');
    });

    tearDown(() async {
      logFromRow = defaultLogFromRow;
      await GetIt.instance.reset();
    });

    Future<void> pump(WidgetTester tester) => tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [S.delegate],
        onGenerateRoute: (settings) {
          calls.add('open ${settings.name}');
          return MaterialPageRoute(builder: (_) => const Scaffold());
        },
        home: Scaffold(
          body: MealItemCard(
            day: DateTime(2026, 10, 30),
            mealEntity: _food(),
            addMealType: AddMealType.lunchType,
            usesImperialUnits: false,
            forkLastLogged: intakeOf('oats', 45),
          ),
        ),
      ),
    );

    testWidgets('the plus logs at once and stays', (tester) async {
      await pump(tester);
      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pumpAndSettle();
      expect(calls, ['log Oats lunch 45.0']);
    });

    testWidgets('the row opens the food\'s page', (tester) async {
      await pump(tester);
      await tester.tap(find.textContaining('Oats', findRichText: true).first);
      await tester.pumpAndSettle();
      expect(calls, ['open ${NavigationOptions.mealDetailRoute}']);
    });
  });
}
