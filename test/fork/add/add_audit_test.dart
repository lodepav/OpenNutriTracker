// The Add flow audit's findings on the + sheet, Quick add and the Undo bar.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/domain/usecase/add_intake_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/add_tracked_day_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_intake_usecase.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/app_theme.dart';
import 'package:opennutritracker/core/utils/navigation_options.dart';
import 'package:opennutritracker/core/utils/tracked_day_lock.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/features/add_meal/presentation/bloc/favourite_toggle_bloc.dart';
import 'package:opennutritracker/features/add_meal/presentation/widgets/quick_add_bottom_sheet.dart';
import 'package:opennutritracker/features/diary/presentation/bloc/calendar_day_bloc.dart';
import 'package:opennutritracker/features/diary/presentation/bloc/diary_bloc.dart';
import 'package:opennutritracker/features/home/presentation/bloc/home_bloc.dart';
import 'package:opennutritracker/fork/add/add_sheet.dart';
import 'package:opennutritracker/fork/add/logged_bar.dart';
import 'package:opennutritracker/fork/add/quick_add.dart';
import 'package:opennutritracker/fork/display/contrast.dart';
import 'package:opennutritracker/generated/l10n.dart';

import '../../helpers/fake_favourites.dart';

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

class _Recent implements GetIntakeUsecase {
  @override
  Future<List<IntakeEntity>> getRecentIntake() async => [
    IntakeEntity(
      id: 'r',
      unit: 'g',
      amount: 100,
      type: IntakeTypeEntity.lunch,
      meal: MealEntity(
        code: 'r',
        name: 'Rice',
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

Widget _app(Widget home, {Brightness brightness = Brightness.light}) =>
    MaterialApp(
      theme: buildAppTheme(
        brightness == Brightness.dark ? AppPalette.dark : AppPalette.light,
      ),
      localizationsDelegates: const [S.delegate],
      supportedLocales: S.supportedLocales,
      routes: {NavigationOptions.mainRoute: (_) => const Text('fresh home')},
      home: home,
    );

Finder _field(String id) => find.descendant(
  of: find.bySemanticsIdentifier(id),
  matching: find.byType(TextField),
);

void main() {
  tearDown(() => GetIt.I.reset());

  group('the Undo bar', () {
    Future<void> show(WidgetTester tester) async {
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showLoggedBar(
                  ScaffoldMessenger.of(context),
                  'Added',
                  day: DateTime(2026, 1, 1),
                  written: const [],
                  stamp: ProfileStamp.now(),
                ),
                child: const Text('log'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('log'));
      await tester.pumpAndSettle();
      expect(find.text('Undo'), findsOneWidget);
      await tester.pump(const Duration(seconds: 10));
      await tester.pumpAndSettle();
    }

    testWidgets('times out under a screen reader too', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(accessibleNavigation: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await show(tester);
      expect(find.text('Undo'), findsNothing);
    });

    testWidgets('times out without a screen reader', (tester) async {
      await show(tester);
      expect(find.text('Undo'), findsNothing);
    });
  });

  testWidgets('Quick add from the + sheet closes both sheets, not the app', (
    tester,
  ) async {
    GetIt.I
      ..registerSingleton<AddIntakeUsecase>(_FakeAdd())
      ..registerSingleton<AddTrackedDayUsecase>(_SavedTracked())
      ..registerSingleton<HomeBloc>(_Home())
      ..registerSingleton<DiaryBloc>(_Diary())
      ..registerSingleton<CalendarDayBloc>(_Calendar());
    await tester.pumpWidget(
      _app(
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                builder: (_) => AddSheet(day: DateTime(2026, 10, 26)),
              ),
              child: const Text('diary'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('diary'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsIdentifier('add-item-quick-add'));
    await tester.pumpAndSettle();
    await tester.enterText(_field('quick-add-energy'), '450');
    await tester.pump();
    await tester.tap(find.bySemanticsIdentifier('quick-add-submit'));
    await tester.pumpAndSettle();

    expect(find.text('fresh home'), findsNothing);
    expect(find.byType(QuickAddBottomSheet), findsNothing);
    expect(find.byType(AddSheet), findsNothing);
    expect(find.text('diary'), findsOneWidget);
    expect(find.text('Undo'), findsOneWidget);
  });

  testWidgets('"Recent for …" is a heading', (tester) async {
    GetIt.I
      ..registerSingleton<GetIntakeUsecase>(_Recent())
      ..registerFactory<FavouriteToggleBloc>(() {
        final favourites = FakeFavourites();
        return FavouriteToggleBloc(favourites.get, favourites.toggle);
      });
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _app(
        Scaffold(
          body: AddSheet(
            day: DateTime(2026, 1, 1),
            suggestedType: IntakeTypeEntity.lunch,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getSemantics(find.text('Recent for Lunch')),
      matchesSemantics(label: 'Recent for Lunch', isHeader: true),
    );
    handle.dispose();
  });

  testWidgets('the + sheet uses rounded icons only', (tester) async {
    await tester.pumpWidget(
      _app(Scaffold(body: AddSheet(day: DateTime(2026, 1, 1)))),
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.menu_book_outlined), findsNothing);
    expect(find.byIcon(Icons.menu_book_rounded), findsOneWidget);
  });

  for (final brightness in Brightness.values) {
    testWidgets('the chosen meal chip has a fill of its own ($brightness)', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: AddSheet(
              day: DateTime(2026, 1, 1),
              suggestedType: IntakeTypeEntity.lunch,
            ),
          ),
          brightness: brightness,
        ),
      );
      await tester.pumpAndSettle();
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
        contrastRatio(fill('Lunch'), fill('Dinner')),
        greaterThanOrEqualTo(3),
      );
    });

    testWidgets('Quick add\'s macro fields have a 3:1 edge ($brightness)', (
      tester,
    ) async {
      final controllers = List.generate(3, (_) => TextEditingController());
      addTearDown(() {
        for (final c in controllers) {
          c.dispose();
        }
      });
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: QuickAddMacroFields(
              carbs: controllers[0],
              fat: controllers[1],
              protein: controllers[2],
            ),
          ),
          brightness: brightness,
        ),
      );
      final palette = brightness == Brightness.dark
          ? AppPalette.dark
          : AppPalette.light;
      for (final name in ['carbs', 'fat', 'protein']) {
        final decoration = tester
            .widget<TextField>(_field('quick-add-$name'))
            .decoration!;
        final side = decoration.enabledBorder?.borderSide;
        expect(side, isNotNull, reason: name);
        expect(side!.style, BorderStyle.solid);
        // on the sheet and on the field's own fill
        expect(
          contrastRatio(side.color, palette.surface),
          greaterThanOrEqualTo(3),
        );
        expect(
          contrastRatio(side.color, palette.surfaceMuted),
          greaterThanOrEqualTo(3),
        );
      }
    });
  }
}
