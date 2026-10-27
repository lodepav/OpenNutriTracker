import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/features/add_meal/presentation/add_meal_type.dart';
import 'package:opennutritracker/features/add_meal/presentation/bloc/favourite_toggle_bloc.dart';
import 'package:opennutritracker/fork/screens/add_meal/result_sections.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:provider/provider.dart';

import '../../../helpers/fake_favourites.dart';

MealEntity _meal(
  String name,
  MealSourceEntity source, {
  String? brand,
  double kcal = 130,
  String? backend,
}) => MealEntity(
  code: '$name$brand$kcal',
  name: name,
  brands: brand,
  url: null,
  mealQuantity: null,
  mealUnit: 'g',
  servingQuantity: null,
  servingUnit: 'g',
  servingSize: null,
  nutriments: MealNutrimentsEntity(
    energyKcal100: kcal,
    carbohydrates100: 28,
    fat100: 0.3,
    proteins100: 2.7,
    sugars100: null,
    saturatedFat100: null,
    fiber100: null,
  ),
  source: source,
  backendSource: backend,
);

MealEntity _usda(String name) =>
    _meal(name, MealSourceEntity.fdc, backend: 'fdc_sr_legacy');

void main() {
  final getIt = GetIt.instance;
  late FakeFavourites favourites;

  setUp(() {
    favourites = FakeFavourites();
    getIt.registerFactory<FavouriteToggleBloc>(
      () => FavouriteToggleBloc(favourites.get, favourites.toggle),
    );
  });

  tearDown(() async {
    await getIt.reset();
    await favourites.dispose();
  });

  Widget app(List<MealEntity> merged, {Widget? footer}) =>
      ChangeNotifierProvider<EnergyUnitProvider>(
        create: (_) => EnergyUnitProvider(usesKilojoules: false),
        child: MaterialApp(
          localizationsDelegates: const [
            S.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          supportedLocales: S.supportedLocales,
          home: Scaffold(
            body: ResultSections(
              day: DateTime(2026, 10, 27),
              addMealType: AddMealType.dinnerType,
              usesImperialUnits: false,
              merged: merged,
              footer: footer,
            ),
          ),
        ),
      );

  final brands = [
    for (final (i, kcal) in [
      121.0,
      126.0,
      130.0,
      135.0,
      138.0,
      142.0,
      146.0,
    ].indexed)
      _meal(
        'Cooked Basmati Rice',
        MealSourceEntity.off,
        brand: 'Brand $i',
        kcal: kcal,
      ),
  ];

  testWidgets('basic foods come first, three until asked for more', (
    tester,
  ) async {
    await tester.pumpWidget(
      app([...brands, for (var i = 1; i <= 5; i++) _usda('Rice $i, cooked')]),
    );
    expect(find.text('Basic foods · USDA'), findsOneWidget);
    expect(find.text('Products · Open Food Facts'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Basic foods · USDA')).dy,
      lessThan(tester.getTopLeft(find.text('Products · Open Food Facts')).dy),
    );
    expect(
      find.textContaining('Rice 3, cooked', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.textContaining('Rice 4, cooked', findRichText: true),
      findsNothing,
    );

    await tester.tap(find.text('Show 2 more basic foods'));
    await tester.pump();
    expect(
      find.textContaining('Rice 5, cooked', findRichText: true),
      findsOneWidget,
    );
  });

  testWidgets('one row stands for the products a name shares, and opens in '
      'place to five, then all', (tester) async {
    await tester.pumpWidget(app(brands));
    expect(find.text('Cooked Basmati Rice'), findsOneWidget);
    expect(find.text('Brand 0, Brand 1 and 5 more'), findsOneWidget);
    expect(find.text('121–146 kcal'), findsOneWidget);
    expect(find.text('7'), findsOneWidget);

    await tester.tap(find.text('Cooked Basmati Rice'));
    await tester.pump();
    expect(find.textContaining('Brand 4', findRichText: true), findsWidgets);
    expect(find.textContaining('Brand 5', findRichText: true), findsNothing);

    await tester.tap(find.text('Show 2 more'));
    await tester.pump();
    expect(find.textContaining('Brand 6', findRichText: true), findsWidgets);

    // Closed again, one row.
    await tester.tap(find.text('Cooked Basmati Rice').first);
    await tester.pump();
    expect(find.text('Cooked Basmati Rice'), findsOneWidget);
  });

  testWidgets('a product alone is its own row, not a group', (tester) async {
    await tester.pumpWidget(
      app([_meal('Basmati & wild rice', MealSourceEntity.off, brand: 'L')]),
    );
    expect(find.text('Basmati & wild rice L', findRichText: true), findsOne);
    expect(find.byIcon(Icons.expand_more_rounded), findsNothing);
  });

  testWidgets('the group row reads as one expandable button', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(app(brands));
    expect(
      tester.getSemantics(find.text('Cooked Basmati Rice')),
      matchesSemantics(
        label: 'Cooked Basmati Rice, 7 products, 121–146 kcal per 100 g',
        isButton: true,
        hasExpandedState: true,
        hasTapAction: true,
      ),
    );
    handle.dispose();
  });

  testWidgets('a footer comes last, under the products', (tester) async {
    await tester.pumpWidget(
      app([...brands, _usda('Rice, cooked')], footer: const Text('footer')),
    );
    expect(
      tester.getTopLeft(find.text('footer')).dy,
      greaterThan(tester.getTopLeft(find.text('Cooked Basmati Rice')).dy),
    );
  });

  testWidgets('the Products tab leaves the products heading out', (
    tester,
  ) async {
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
            body: ResultSections(
              day: DateTime(2026, 10, 27),
              addMealType: AddMealType.dinnerType,
              usesImperialUnits: false,
              merged: brands,
              productsHeading: false,
            ),
          ),
        ),
      ),
    );
    expect(find.text('Products · Open Food Facts'), findsNothing);
    expect(find.text('Cooked Basmati Rice'), findsOneWidget);
  });
}
