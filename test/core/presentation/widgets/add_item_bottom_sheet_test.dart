import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_intake_usecase.dart';
import 'package:opennutritracker/core/presentation/widgets/add_item_bottom_sheet.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/features/add_meal/presentation/bloc/favourite_toggle_bloc.dart';
import 'package:opennutritracker/generated/l10n.dart';
// [fork] S131 add-sheet
import 'package:opennutritracker/core/utils/navigation_options.dart';
import 'package:opennutritracker/features/add_meal/presentation/add_meal_screen.dart';
import 'package:opennutritracker/features/add_meal/presentation/add_meal_type.dart';
import 'package:opennutritracker/features/add_meal/presentation/widgets/meal_item_card.dart';
// [/fork]
import '../../../helpers/fake_favourites.dart';
import '../../../helpers/test_l10n.dart';

// #277: the Show Activity Tracking toggle in Settings has been wired to
// hide every activity-related surface in the app. AddItemBottomSheet is
// the FAB's add-something menu — when the toggle is off, the Activity
// row at the top should disappear so the meal options are all that's on
// offer. Locking the behaviour in here so a future refactor that drops
// the conditional or its default trips the test instead of slipping past
// review.

Widget _wrapWithMaterial(Widget child) {
  return MaterialApp(
    localizationsDelegates: const [S.delegate],
    supportedLocales: S.supportedLocales,
    home: Scaffold(body: child),
  );
}

class _FakeGetIntakeUsecase implements GetIntakeUsecase {
  @override
  Future<List<IntakeEntity>> getRecentIntake() async => [
    for (var i = 0; i < 2; i++)
      IntakeEntity(
        id: 'recent-$i',
        unit: 'g',
        amount: 100,
        type: IntakeTypeEntity.lunch,
        meal: MealEntity(
          code: 'recent-$i',
          name: 'Recent $i',
          url: null,
          mealQuantity: '100',
          mealUnit: 'g',
          servingQuantity: null,
          servingUnit: null,
          servingSize: null,
          nutriments: MealNutrimentsEntity.empty(),
          source: MealSourceEntity.custom,
        ),
        dateTime: DateTime(2026, 1, 1),
      ),
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Unexpected call: ${invocation.memberName}');
}

Finder _withIdentifier(String identifier) => find.byWidgetPredicate(
  (widget) => widget is Semantics && widget.properties.identifier == identifier,
);

void main() {
  testWidgets(
    'shows the Activity tile when showActivityTracking is true',
    (tester) async {
      await tester.pumpWidget(_wrapWithMaterial(
        AddItemBottomSheet(
          day: DateTime(2026, 1, 1),
          showActivityTracking: true,
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text(l10nEn.activityLabel), findsOneWidget);
      expect(find.text(l10nEn.breakfastLabel), findsOneWidget);
    },
  );

  testWidgets(
    'hides the Activity tile when showActivityTracking is false',
    (tester) async {
      await tester.pumpWidget(_wrapWithMaterial(
        AddItemBottomSheet(
          day: DateTime(2026, 1, 1),
          showActivityTracking: false,
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text(l10nEn.activityLabel), findsNothing);
      // Meal tiles still render so the sheet stays useful for food logging.
      expect(find.text(l10nEn.breakfastLabel), findsOneWidget);
      expect(find.text(l10nEn.lunchLabel), findsOneWidget);
      expect(find.text(l10nEn.dinnerLabel), findsOneWidget);
      expect(find.text(l10nEn.snackLabel), findsOneWidget);
    },
  );

  testWidgets('recent card stars have unique identifiers', (tester) async {
    final getIt = GetIt.instance;
    await getIt.reset();
    final favourites = FakeFavourites();
    getIt.registerSingleton<GetIntakeUsecase>(_FakeGetIntakeUsecase());
    getIt.registerFactory<FavouriteToggleBloc>(
      () => FavouriteToggleBloc(favourites.get, favourites.toggle),
    );
    final handle = tester.ensureSemantics();

    await tester.pumpWidget(_wrapWithMaterial(
      AddItemBottomSheet(day: DateTime(2026, 1, 1)),
    ));
    await tester.pumpAndSettle();

    expect(_withIdentifier('add-item-recent-favourite-1'), findsOneWidget);
    expect(_withIdentifier('add-item-recent-favourite-2'), findsOneWidget);
    handle.dispose();
    await getIt.reset();
    await favourites.dispose();
  });

  testWidgets(
    'defaults to showing the Activity tile when the flag is omitted',
    (tester) async {
      await tester.pumpWidget(_wrapWithMaterial(
        AddItemBottomSheet(day: DateTime(2026, 1, 1)),
      ));
      await tester.pumpAndSettle();

      expect(find.text(l10nEn.activityLabel), findsOneWidget);
    },
  );

  // [fork] S131 add-sheet: the suggestion is the meal chip picked, and
  // the recent foods follow the chip
  bool selected(WidgetTester tester, String label) => tester
      .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, label))
      .selected;

  testWidgets('picks the suggested meal, and only it', (tester) async {
    await tester.pumpWidget(_wrapWithMaterial(
      AddItemBottomSheet(
        day: DateTime(2026, 1, 1),
        suggestedType: IntakeTypeEntity.lunch,
      ),
    ));
    await tester.pumpAndSettle();

    expect(selected(tester, l10nEn.lunchLabel), isTrue);
    for (final other in [
      l10nEn.breakfastLabel,
      l10nEn.dinnerLabel,
      l10nEn.snackLabel,
    ]) {
      expect(selected(tester, other), isFalse);
    }
    await tester.tap(find.text(l10nEn.dinnerLabel));
    await tester.pump();
    expect(selected(tester, l10nEn.dinnerLabel), isTrue);
    expect(selected(tester, l10nEn.lunchLabel), isFalse);
  });

  testWidgets('without a suggestion, one meal is still picked', (
    tester,
  ) async {
    await tester.pumpWidget(_wrapWithMaterial(
      AddItemBottomSheet(day: DateTime(2026, 1, 1)),
    ));
    await tester.pumpAndSettle();

    expect(
      tester
          .widgetList<ChoiceChip>(find.byType(ChoiceChip))
          .where((chip) => chip.selected),
      hasLength(1),
    );
  });

  testWidgets('the recent foods are the picked meal\'s, else any meal\'s', (
    tester,
  ) async {
    final getIt = GetIt.instance;
    await getIt.reset();
    final favourites = FakeFavourites();
    getIt.registerSingleton<GetIntakeUsecase>(_FakeGetIntakeUsecase());
    getIt.registerFactory<FavouriteToggleBloc>(
      () => FavouriteToggleBloc(favourites.get, favourites.toggle),
    );

    await tester.pumpWidget(_wrapWithMaterial(
      AddItemBottomSheet(
        day: DateTime(2026, 1, 1),
        suggestedType: IntakeTypeEntity.lunch,
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Recent for ${l10nEn.lunchLabel}'), findsOneWidget);
    MealItemCard first() =>
        tester.widget<MealItemCard>(find.byType(MealItemCard).first);
    expect(first().mealEntity.name, 'Recent 0');
    expect(first().addMealType, AddMealType.lunchType);

    await tester.tap(find.text(l10nEn.snackLabel));
    await tester.pumpAndSettle();
    expect(find.text(l10nEn.recentlyAddedLabel), findsOneWidget);
    // Logged with lunch, the foods now go to the snack.
    expect(first().mealEntity.name, 'Recent 0');
    expect(first().addMealType, AddMealType.snackType);

    await getIt.reset();
    await favourites.dispose();
  });

  testWidgets('search opens the food search for the picked meal', (
    tester,
  ) async {
    final pushed = <RouteSettings>[];
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: const [S.delegate],
      supportedLocales: S.supportedLocales,
      onGenerateRoute: (settings) {
        if (settings.name != '/') pushed.add(settings);
        return MaterialPageRoute(
          settings: settings,
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                builder: (_) => AddItemBottomSheet(
                  day: DateTime(2026, 1, 1),
                  suggestedType: IntakeTypeEntity.lunch,
                ),
              ),
              child: const Text('open'),
            ),
          ),
        );
      },
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10nEn.dinnerLabel));
    await tester.pump();
    await tester.tap(find.text(l10nEn.searchLabel));
    await tester.pumpAndSettle();

    expect(pushed.single.name, NavigationOptions.addMealRoute);
    final args = pushed.single.arguments as AddMealScreenArguments;
    expect(args.mealType, AddMealType.dinnerType);
    expect(args.day, DateTime(2026, 1, 1));
    expect(find.text(l10nEn.dinnerLabel), findsNothing, reason: 'closed');
  });

  testWidgets('offers search, Quick add, Scan and Recipes', (tester) async {
    await tester.pumpWidget(_wrapWithMaterial(
      AddItemBottomSheet(day: DateTime(2026, 1, 1)),
    ));
    await tester.pumpAndSettle();

    for (final id in [
      'add-item-search',
      'add-item-quick-add',
      'add-item-scan',
      'add-item-recipes',
      'add-item-activity',
    ]) {
      expect(_withIdentifier(id), findsOneWidget, reason: id);
    }
  });
  // [/fork]
}
