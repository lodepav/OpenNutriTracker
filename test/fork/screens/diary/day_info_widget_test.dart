// Fork-owned copy of test/features/diary/presentation/widgets/day_info_widget_test.dart (D23); upstream's later changes to it
// are ported by hand: fork/tools/upstream-copies.sh.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/domain/entity/profile_entity.dart';
import 'package:opennutritracker/core/domain/entity/tracked_day_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_activity_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_profiles_usecase.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_store.dart';
import 'package:opennutritracker/fork/adaptive/skip_day.dart';
import 'package:opennutritracker/fork/copy/diary_selection.dart';
import 'package:opennutritracker/fork/display/day_totals_card.dart';
import 'package:opennutritracker/fork/display/diary_timeline.dart';
import 'package:opennutritracker/fork/screens/diary/day_info_widget.dart';
import 'package:opennutritracker/features/diary/presentation/bloc/calendar_day_bloc.dart';
import 'package:opennutritracker/features/home/presentation/bloc/home_bloc.dart';
import 'package:opennutritracker/features/meal_detail/presentation/bloc/meal_detail_bloc.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:provider/provider.dart';
import '../../../fixture/physical_activity_entity_fixtures.dart';
import '../../../helpers/test_l10n.dart';
import '../../../helpers/ux_checks.dart';

class _FakeMealDetailBloc extends Fake implements MealDetailBloc {}

class _FakeHomeBloc extends Fake implements HomeBloc {}

class _FakeCalendarDayBloc extends Fake implements CalendarDayBloc {
  @override
  Future<void> setDiarySortPreference(String mealKey, int sortIndex) async {}
}

class _SingleProfileGetProfilesUsecase implements GetProfilesUsecase {
  static final _profile = ProfileEntity(
    id: 'p1',
    name: 'Me',
    createdAt: DateTime(2026, 1, 1),
    boxSuffix: '',
  );

  @override
  List<ProfileEntity> getProfiles() => [_profile];

  @override
  String get activeProfileId => 'p1';

  @override
  ProfileEntity? getActiveProfile() => _profile;
}

IntakeEntity _intake(IntakeTypeEntity type, String name, {DateTime? at}) {
  return IntakeEntity(
    id: 'intake-$name',
    unit: 'g',
    amount: 100,
    type: type,
    dateTime: at ?? DateTime(2026, 6, 15, 8),
    meal: MealEntity(
      code: 'meal-$name',
      name: name,
      url: null,
      mealQuantity: '100',
      mealUnit: 'g',
      servingQuantity: null,
      servingUnit: 'g',
      servingSize: '100 g',
      nutriments: MealNutrimentsEntity(
        energyKcal100: 200,
        carbohydrates100: 20,
        fat100: 10,
        proteins100: 5,
        sugars100: null,
        saturatedFat100: null,
        fiber100: null,
      ),
      source: MealSourceEntity.custom,
    ),
  );
}

final _dinner = _intake(IntakeTypeEntity.dinner, 'Dinner Stew');

/// OMAD shares: only dinner has a share, breakfast is at 0 %.
Future<void> _pumpOmadDay(
  WidgetTester tester, {
  required List<IntakeEntity> breakfastIntake,
  void Function(IntakeEntity intake)? onEditIntake,
}) async {
  await tester.pumpWidget(
    ChangeNotifierProvider<EnergyUnitProvider>(
      create: (_) => EnergyUnitProvider(),
      child: MaterialApp(
        localizationsDelegates: const [
          S.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        supportedLocales: S.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: DayInfoWidget(
              selectedDay: DateTime(2026, 6, 15),
              currentDay: DateTime(2026, 6, 16),
              trackedDayEntity: null,
              userActivities: const [],
              breakfastIntake: breakfastIntake,
              lunchIntake: const [],
              dinnerIntake: [_dinner],
              snackIntake: const [],
              usesImperialUnits: false,
              showActivityTracking: false,
              onDeleteIntake: (_, _) {},
              onDeleteActivity: (_, _) {},
              onEditIntake: (_, intake, _) => onEditIntake?.call(intake),
              onCopyActivity: (_, _) {},
              breakfastSharePct: 0,
              lunchSharePct: 0,
              dinnerSharePct: 100,
              snackSharePct: 0,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

final _walk = UserActivityEntity(
  'walk',
  43,
  249,
  DateTime(2026, 6, 15, 18),
  PhysicalActivityFixtures.moderateBicycling,
);

final _porridge = _intake(
  IntakeTypeEntity.breakfast,
  'Porridge',
  at: DateTime(2026, 6, 15, 8, 41),
);

/// A day with a logged breakfast and an activity, its fat goal passed.
Future<void> _pumpLoggedDay(
  WidgetTester tester, {
  List<IntakeEntity>? breakfast,
}) async {
  await tester.pumpWidget(
    ChangeNotifierProvider<EnergyUnitProvider>(
      create: (_) => EnergyUnitProvider(),
      child: MaterialApp(
        localizationsDelegates: const [
          S.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        supportedLocales: S.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: DayInfoWidget(
              selectedDay: DateTime(2026, 6, 15),
              currentDay: DateTime(2026, 6, 16),
              trackedDayEntity: TrackedDayEntity(
                day: DateTime(2026, 6, 15),
                calorieGoal: 2000,
                caloriesTracked: 200,
                carbsGoal: 250,
                fatGoal: 6,
                proteinGoal: 120,
              ),
              userActivities: [_walk],
              breakfastIntake: breakfast ?? [_porridge],
              lunchIntake: const [],
              dinnerIntake: const [],
              snackIntake: const [],
              usesImperialUnits: false,
              onDeleteIntake: (_, _) {},
              onDeleteActivity: (_, _) {},
              onCopyActivity: (_, _) {},
              breakfastKcalTarget: 929,
              diarySortPreferences: const {},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

class _Skips extends AdaptiveStore {
  @override
  Future<void> setSkipped(DateTime day, bool skipped) async {
    final days = {...AdaptiveStore.skipped.value};
    skipped ? days.add(day) : days.remove(day);
    AdaptiveStore.skipped.value = days;
  }
}

void main() {
  setUpAll(() {
    final locator = GetIt.instance;
    locator.registerFactory<MealDetailBloc>(_FakeMealDetailBloc.new);
    locator.registerFactory<HomeBloc>(_FakeHomeBloc.new);
    locator.registerFactory<CalendarDayBloc>(_FakeCalendarDayBloc.new);
    locator.registerFactory<GetProfilesUsecase>(
      _SingleProfileGetProfilesUsecase.new,
    );
  });

  tearDownAll(() {
    GetIt.instance.reset();
  });

  tearDown(DiarySelection.instance.end);

  // #1305: OMAD puts breakfast, lunch and snack at 0 %. Food that still lands
  // in breakfast must get a section, or it counts toward the day with no way
  // to see, edit or delete it. Empty 0 % sections stay hidden.
  testWidgets('a 0 % meal section with intakes is shown, an empty one is not', (
    WidgetTester tester,
  ) async {
    await _pumpOmadDay(
      tester,
      breakfastIntake: [_intake(IntakeTypeEntity.breakfast, 'Hidden Porridge')],
    );

    expect(find.text(l10nEn.breakfastLabel), findsOneWidget);
    expect(find.text('Hidden Porridge'), findsOneWidget);
    expect(find.text(l10nEn.dinnerLabel), findsOneWidget);
    expect(find.text(l10nEn.lunchLabel), findsNothing);
    expect(find.text(l10nEn.snackLabel), findsNothing);
  });

  // #1305: showing the entry is half the fix; it must also be editable, and
  // so deletable, through the same long-press as any other entry. Once it is
  // gone the empty 0 % section hides again.
  testWidgets('an entry in a 0 % meal section opens its edit on a long-press', (
    WidgetTester tester,
  ) async {
    final porridge = _intake(IntakeTypeEntity.breakfast, 'Hidden Porridge');
    final edited = <IntakeEntity>[];
    await _pumpOmadDay(
      tester,
      breakfastIntake: [porridge],
      onEditIntake: edited.add,
    );

    await tester.longPress(find.text('Hidden Porridge'));
    await tester.pumpAndSettle();
    expect(edited, [porridge]);

    // The page reloads without the deleted entry.
    await _pumpOmadDay(tester, breakfastIntake: const []);

    expect(find.text('Hidden Porridge'), findsNothing);
    expect(find.text(l10nEn.breakfastLabel), findsNothing);
    expect(find.text(l10nEn.dinnerLabel), findsOneWidget);
    expect(find.text('Dinner Stew'), findsOneWidget);
  });

  testWidgets('a tap selects; no actions sheet opens', (tester) async {
    await _pumpOmadDay(tester, breakfastIntake: const []);

    await tester.tap(find.text('Dinner Stew'));
    await tester.pumpAndSettle();
    expect(DiarySelection.instance.isPicked(_dinner), isTrue);
    expect(find.text('Copy to…'), findsNothing);
  });

  testWidgets('a tap on the header selects the whole meal', (tester) async {
    await _pumpOmadDay(tester, breakfastIntake: const []);

    await tester.tap(find.text(l10nEn.dinnerLabel));
    await tester.pumpAndSettle();
    expect(DiarySelection.instance.isPicked(_dinner), isTrue);
  });

  testWidgets('the section menu no longer offers to copy or move', (
    tester,
  ) async {
    await _pumpOmadDay(tester, breakfastIntake: const []);

    await tester.tap(find.bySemanticsIdentifier('intake-section-menu'));
    await tester.pumpAndSettle();
    expect(find.text(l10nEn.deleteAllLabel), findsOneWidget);
    expect(find.text('Copy or move…'), findsNothing);
  });

  testWidgets('at 2x text on a 412-wide phone nothing overflows and the '
      'totals stack', (tester) async {
    tester.view.physicalSize = const Size(412, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await _pumpLoggedDay(tester);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final card = find.byType(DayTotalsCard);
    double y(String label) => tester
        .getTopLeft(find.descendant(of: card, matching: find.text(label)))
        .dy;
    expect(y('Energy'), lessThan(y('Carbs')));
    expect(y('Carbs'), lessThan(y('Fat')));
    expect(y('Fat'), lessThan(y('Protein')));

    // The menus open without overflowing too.
    await tester.tap(find.byTooltip('Day options'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tapAt(Offset.zero);
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsIdentifier('intake-section-menu').first);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('the meal header, the totals and an activity are spoken as '
      'shown, in words', (tester) async {
    final handle = tester.ensureSemantics();
    await _pumpLoggedDay(tester);

    // 929 is the meal's target, not on screen.
    expect(
      find.bySemanticsLabel(
        'Breakfast, 8:41 AM, 200 kcal, carbs 20 g, fat 10 g, protein 5 g',
      ),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Carbs 20 of 250 g'), findsOneWidget);
    expect(find.bySemanticsLabel('Fat 10 of 6 g, 4 g over'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Bicycling, 43 minutes, 249 kcal burned'),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel(RegExp('🔥|/')), findsNothing);
    // On screen too (S224): a capital, and the figure without its emoji.
    expect(find.text('Bicycling'), findsOneWidget);
    expect(find.textContaining('🔥'), findsNothing);

    // While selecting, a checkbox stands where the time was.
    DiarySelection.instance.start();
    await tester.pumpAndSettle();
    expect(
      find.bySemanticsLabel(
        'Breakfast, 200 kcal, carbs 20 g, fat 10 g, protein 5 g',
      ),
      findsOneWidget,
    );
    DiarySelection.instance.end();
    await tester.pumpAndSettle();

    // The activity's one node keeps the card's long-press.
    tester.semantics.longPress(
      find.semantics.byLabel(RegExp('43 minutes, 249 kcal burned')),
    );
    await tester.pumpAndSettle();
    expect(find.text('${l10nEn.copyActionLabel}…'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('fat past its target is not in the error colour', (tester) async {
    await _pumpLoggedDay(tester);
    final error = Theme.of(
      tester.element(find.byType(DayTotalsCard)),
    ).colorScheme.error;
    final card = find.byType(DayTotalsCard);
    for (final text in tester.widgetList<RichText>(
      find.descendant(of: card, matching: find.byType(RichText)),
    )) {
      text.text.visitChildren((span) {
        expect(span.style?.color, isNot(error));
        return true;
      });
    }
    for (final bar in tester.widgetList<LinearProgressIndicator>(
      find.descendant(of: card, matching: find.byType(LinearProgressIndicator)),
    )) {
      expect(bar.color, isNot(error));
    }
  });

  testWidgets("sort is in the meal's menu, not its header", (tester) async {
    await _pumpLoggedDay(tester);
    expect(find.byIcon(Icons.sort_rounded), findsNothing);

    await tester.tap(find.bySemanticsIdentifier('intake-section-menu').first);
    await tester.pumpAndSettle();
    expect(find.text(l10nEn.diarySortByLabel), findsOneWidget);
    expect(find.text(l10nEn.diarySortByKcal), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('diary-sort-kcal')));
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsIdentifier('intake-section-menu').first);
    await tester.pumpAndSettle();
    final kcal = tester.widget<CheckedPopupMenuItem>(
      find.byKey(const ValueKey('diary-sort-kcal')),
    );
    expect(kcal.checked, isTrue);
  });

  testWidgets('the Day menu names its four actions', (tester) async {
    await _pumpLoggedDay(tester);
    expect(find.byKey(const Key('fork-select-entries')), findsNothing);

    await tester.tap(find.byTooltip('Day options'));
    await tester.pumpAndSettle();
    for (final item in [
      'Timeline',
      'Select foods',
      'Copy day',
      'Leave out of expenditure',
    ]) {
      expect(find.text(item), findsOneWidget, reason: item);
    }
    await tester.tap(find.byKey(const Key('fork-select-entries')));
    await tester.pumpAndSettle();
    expect(DiarySelection.instance.active, isTrue);
  });

  testWidgets('leaving the day out is a Day menu item; the day then says so '
      'and a tap counts it again', (tester) async {
    addTearDown(() => AdaptiveStore.skipped.value = const {});
    final store = _Skips();
    final day = DateTime(2026, 6, 15);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              DayMenu(day: day, hasEntries: true, store: store),
              SkipDayNote(day: day, store: store),
            ],
          ),
        ),
      ),
    );
    expect(find.byType(Switch), findsNothing);
    expect(find.textContaining('Left out'), findsNothing);

    await tester.tap(find.byTooltip('Day options'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Logged only in part?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('skip-day')));
    await tester.pumpAndSettle();
    expect(AdaptiveStore.skipped.value, {day});
    expect(
      find.text('Left out of expenditure · Undo', findRichText: true),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('Day options'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<CheckedPopupMenuItem>(find.byKey(const ValueKey('skip-day')))
          .checked,
      isTrue,
    );
    await tester.tapAt(Offset.zero);
    await tester.pumpAndSettle();

    await tester.tap(find.byType(SkipDayNote));
    await tester.pumpAndSettle();
    expect(AdaptiveStore.skipped.value, isEmpty);
    expect(isSkippedDay(day), isFalse);
  });

  testWidgets('the day body has no expenditure switch', (tester) async {
    await _pumpLoggedDay(tester);
    expect(find.byType(Switch), findsNothing);
    expect(find.text('Leave out of expenditure'), findsNothing);
  });

  testWidgets('a day with nothing logged shows no empty hours', (tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<EnergyUnitProvider>(
        create: (_) => EnergyUnitProvider(),
        child: MaterialApp(
          localizationsDelegates: const [
            S.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          supportedLocales: S.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: DayInfoWidget(
                selectedDay: DateTime(2026, 6, 15),
                currentDay: DateTime(2026, 6, 16),
                trackedDayEntity: null,
                userActivities: const [],
                breakfastIntake: const [],
                lunchIntake: const [],
                dinnerIntake: const [],
                snackIntake: const [],
                usesImperialUnits: false,
                onDeleteIntake: (_, _) {},
                onDeleteActivity: (_, _) {},
                onCopyActivity: (_, _) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text(l10nEn.breakfastLabel), findsOneWidget);
    expect(find.byType(TimelineGap), findsNothing);
  });

  testWidgets('the day heading leaves the year to the strip: its longest '
      'date one line at 1x on a 411 phone', (tester) async {
    await pumpOnPhone(
      tester,
      ChangeNotifierProvider<EnergyUnitProvider>(
        create: (_) => EnergyUnitProvider(),
        child: SingleChildScrollView(
          child: DayInfoWidget(
            selectedDay: DateTime(2026, 11, 18),
            currentDay: DateTime(2026, 11, 18),
            trackedDayEntity: null,
            userActivities: const [],
            breakfastIntake: const [],
            lunchIntake: const [],
            dinnerIntake: const [],
            snackIntake: const [],
            usesImperialUnits: false,
            onDeleteIntake: (_, _) {},
            onDeleteActivity: (_, _) {},
            onCopyActivity: (_, _) {},
          ),
        ),
      ),
      textScale: 1,
    );
    final heading = find.text('Wednesday, November 18');
    expect(heading, findsOneWidget);
    expect(find.textContaining('2026'), findsNothing);
    final style = tester.widget<Text>(heading).style!;
    expect(
      tester.getSize(heading).height,
      lessThan(style.fontSize! * style.height! * 1.5),
    );
  });
}
