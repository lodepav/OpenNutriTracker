import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:intl/intl.dart';
import 'package:opennutritracker/core/data/dbo/config_dbo.dart';
import 'package:opennutritracker/core/domain/entity/config_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/domain/entity/profile_entity.dart';
import 'package:opennutritracker/core/domain/entity/tracked_day_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_intake_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_profiles_usecase.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/features/diary/presentation/bloc/calendar_day_bloc.dart';
import 'package:opennutritracker/features/diary/presentation/widgets/daily_nutrient_panel.dart';
import 'package:opennutritracker/features/diary/presentation/widgets/diary_table_calendar.dart';
import 'package:opennutritracker/features/home/presentation/bloc/home_bloc.dart';
import 'package:opennutritracker/features/meal_detail/presentation/bloc/meal_detail_bloc.dart';
import 'package:opennutritracker/fork/copy/copy_ui.dart';
import 'package:opennutritracker/fork/copy/diary_selection.dart';
import 'package:opennutritracker/fork/display/contrast.dart';
import 'package:opennutritracker/fork/display/day_ring.dart';
import 'package:opennutritracker/fork/screens/diary/day_info_widget.dart';
import 'package:provider/provider.dart';

import '../../../helpers/ux_checks.dart';

// The Diary audit's findings, each pinned.

class _MealDetailBloc extends Fake implements MealDetailBloc {}

class _HomeBloc extends Fake implements HomeBloc {}

class _CalendarDayBloc extends Fake implements CalendarDayBloc {
  @override
  Future<void> setDiarySortPreference(String mealKey, int sortIndex) async {}
}

class _Profiles extends Fake implements GetProfilesUsecase {
  static final _me = ProfileEntity(
    id: 'p1',
    name: 'Me',
    createdAt: DateTime(2026),
    boxSuffix: '',
  );

  @override
  List<ProfileEntity> getProfiles() => [_me];

  @override
  String get activeProfileId => 'p1';

  @override
  ProfileEntity? getActiveProfile() => _me;
}

class _Config extends Fake implements GetConfigUsecase {
  @override
  Future<ConfigEntity> getConfig() async =>
      ConfigEntity.fromConfigDBO(ConfigDBO.empty());
}

/// Counts the panel's week reads: one per meal per day.
class _CountingIntakes extends Fake implements GetIntakeUsecase {
  var reads = 0;

  Future<List<IntakeEntity>> _read() async {
    reads++;
    return const [];
  }

  @override
  Future<List<IntakeEntity>> getBreakfastIntakeByDay(
    DateTime day, {
    int dayStartOffsetHours = 0,
    int dayStartOffsetMinutes = 0,
  }) => _read();

  @override
  Future<List<IntakeEntity>> getLunchIntakeByDay(
    DateTime day, {
    int dayStartOffsetHours = 0,
    int dayStartOffsetMinutes = 0,
  }) => _read();

  @override
  Future<List<IntakeEntity>> getDinnerIntakeByDay(
    DateTime day, {
    int dayStartOffsetHours = 0,
    int dayStartOffsetMinutes = 0,
  }) => _read();

  @override
  Future<List<IntakeEntity>> getSnackIntakeByDay(
    DateTime day, {
    int dayStartOffsetHours = 0,
    int dayStartOffsetMinutes = 0,
  }) => _read();
}

final _day = DateTime(2026, 6, 15);

IntakeEntity _intake(String name, {double? fiber100}) => IntakeEntity(
  id: 'intake-$name',
  unit: 'g',
  amount: 100,
  type: IntakeTypeEntity.breakfast,
  dateTime: DateTime(2026, 6, 15, 8),
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
      fiber100: fiber100,
    ),
    source: MealSourceEntity.custom,
  ),
);

Widget _dayWidget(List<IntakeEntity> breakfast) => DayInfoWidget(
  selectedDay: _day,
  currentDay: DateTime(2026, 6, 16),
  trackedDayEntity: TrackedDayEntity(
    day: _day,
    calorieGoal: 2000,
    caloriesTracked: 200,
  ),
  userActivities: const [],
  breakfastIntake: breakfast,
  lunchIntake: const [],
  dinnerIntake: const [],
  snackIntake: const [],
  usesImperialUnits: false,
  showActivityTracking: false,
  onDeleteIntake: (_, _) {},
  onDeleteActivity: (_, _) {},
  onCopyActivity: (_, _) {},
  breakfastKcalTarget: 500,
  diarySortPreferences: const {},
);

/// The day of [breakfast], under a parent that rebuilds on [tick].
Widget _rebuilding(ValueNotifier<int> tick, List<IntakeEntity> breakfast) =>
    ChangeNotifierProvider(
      create: (_) => EnergyUnitProvider(usesKilojoules: false),
      child: SingleChildScrollView(
        child: ValueListenableBuilder(
          valueListenable: tick,
          builder: (_, _, _) => _dayWidget(breakfast),
        ),
      ),
    );

Widget _calendar({Map<String, TrackedDayEntity> days = const {}}) =>
    DiaryTableCalendar(
      onDateSelected: (_, _) {},
      calendarDurationDays: const Duration(days: 365),
      focusedDate: DateTime(2026, 8, 24),
      currentDate: DateTime(2026, 8, 24),
      selectedDate: DateTime(2026, 8, 24),
      trackedDaysMap: days,
      daysWithEntries: days.keys.toSet(),
    );

/// A 360 dp phone, the narrowest the app is laid out for.
Future<void> _narrow(WidgetTester tester) async {
  tester.view.physicalSize = const Size(360 * 2.625, 2340);
  await tester.pump();
}

void main() {
  late _CountingIntakes intakes;

  setUp(() {
    intakes = _CountingIntakes();
    GetIt.instance
      ..registerFactory<MealDetailBloc>(_MealDetailBloc.new)
      ..registerFactory<HomeBloc>(_HomeBloc.new)
      ..registerFactory<CalendarDayBloc>(_CalendarDayBloc.new)
      ..registerFactory<GetProfilesUsecase>(_Profiles.new)
      ..registerSingleton<GetConfigUsecase>(_Config())
      ..registerSingleton<GetIntakeUsecase>(intakes);
  });
  tearDown(() async {
    DiarySelection.instance.end();
    await GetIt.instance.reset();
  });

  testWidgets('a rebuild of the day does not re-read the week', (tester) async {
    final tick = ValueNotifier(0);
    final breakfast = [_intake('Porridge')];
    await pumpOnPhone(tester, _rebuilding(tick, breakfast), textScale: 1);
    await tester.pumpAndSettle();
    final first = intakes.reads;
    expect(first, 28, reason: 'seven days of four meals');

    tick.value++;
    await tester.pumpAndSettle();
    expect(intakes.reads, first, reason: 'the same lists');
  });

  testWidgets('a new list from the bloc does re-read the week', (tester) async {
    final tick = ValueNotifier(0);
    await pumpOnPhone(
      tester,
      _rebuilding(tick, [_intake('Porridge')]),
      textScale: 1,
    );
    await tester.pumpAndSettle();
    await pumpOnPhone(
      tester,
      _rebuilding(tick, [_intake('Porridge')]),
      textScale: 1,
    );
    await tester.pumpAndSettle();
    expect(intakes.reads, 56);
  });

  testWidgets("the day's date is a heading", (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpOnPhone(
      tester,
      _rebuilding(ValueNotifier(0), [_intake('Porridge')]),
      textScale: 1,
    );
    await tester.pumpAndSettle();
    expect(
      tester.getSemantics(find.text(DateFormat.MMMMEEEEd().format(_day))),
      matchesSemantics(label: 'Monday, June 15', isHeader: true),
    );
    semantics.dispose();
  });

  group('the selection bar keeps its count whole at 360 dp', () {
    for (final scale in [1.0, 2.0]) {
      for (final picked in [1, 3]) {
        testWidgets('at ${scale}x with $picked picked', (tester) async {
          final selection = DiarySelection()
            ..toggleAll([for (var i = 0; i < picked; i++) _intake('Food $i')]);
          await pumpOnPhone(
            tester,
            Align(
              alignment: Alignment.bottomCenter,
              child: DiarySelectionBar(
                selection: selection,
                day: _day,
                onDelete: (_, _) {},
                onEdit: (_, _) {},
              ),
            ),
            textScale: scale,
          );
          await _narrow(tester);
          expect(find.text('$picked selected'), findsOneWidget);
          expect(cutText(tester), isEmpty);
          expect(tester.takeException(), isNull);
          for (final key in ['end', 'copy', 'move', 'delete']) {
            expect(find.byKey(Key('fork-selection-$key')), findsOneWidget);
          }
          // the less used ones, a tap further
          await tester.tap(find.byKey(const Key('fork-selection-more')));
          await tester.pumpAndSettle();
          expect(
            find.byKey(const Key('fork-selection-edit')),
            picked == 1 ? findsOneWidget : findsNothing,
          );
          expect(find.byKey(const Key('fork-selection-share')), findsOneWidget);
        });
      }
    }
  });

  testWidgets('the month toggle and the week strip days take 48 dp', (
    tester,
  ) async {
    await pumpOnPhone(tester, _calendar(), textScale: 1);
    await _narrow(tester);
    await tester.pumpAndSettle();
    final toggle = find.ancestor(
      of: find.byIcon(Icons.expand_more_rounded),
      matching: find.byType(InkWell),
    );
    expect(tester.getSize(toggle.first).height, greaterThanOrEqualTo(48));
    final cell = find
        .ancestor(
          of: find.text('25'),
          matching: find.byType(RawGestureDetector),
        )
        .first;
    expect(tester.getSize(cell).width, greaterThanOrEqualTo(48));
  });

  test('a ring says how much of the energy goal is eaten', () {
    TrackedDayEntity row(double kcal, double goal) =>
        TrackedDayEntity(day: _day, calorieGoal: goal, caloriesTracked: kcal);
    expect(DayRing.fillLabel(null), isNull);
    expect(DayRing.fillLabel(row(1500, 2000)), '75% of energy goal');
    // over the goal: the ring is full, the words say by how much
    expect(DayRing.fillLabel(row(2400, 2000)), '120% of energy goal');
    expect(DayRing.fillLabel(row(500, 0)), isNull);
  });

  testWidgets('a day with entries speaks its ring', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpOnPhone(
      tester,
      _calendar(
        days: {
          '2026-08-25': TrackedDayEntity(
            day: DateTime(2026, 8, 25),
            calorieGoal: 2000,
            caloriesTracked: 1500,
          ),
        },
      ),
      textScale: 1,
    );
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel(RegExp('75% of energy goal')), findsOneWidget);
    semantics.dispose();
  });

  group('the nutrient panel', () {
    Future<void> openPanel(WidgetTester tester, {bool dark = false}) async {
      await pumpOnPhone(
        tester,
        SingleChildScrollView(
          child: DailyNutrientPanel(intakes: [_intake('Bran', fiber100: 20)]),
        ),
        textScale: 1,
        dark: dark,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nutrients'));
      await tester.pumpAndSettle();
    }

    testWidgets('its info button and Day/Week toggle take 48 dp', (
      tester,
    ) async {
      await openPanel(tester);
      final info = tester.getSize(
        find.ancestor(
          of: find.byTooltip('Reference intake'),
          matching: find.byType(IconButton),
        ),
      );
      expect(info.width, greaterThanOrEqualTo(48));
      expect(info.height, greaterThanOrEqualTo(48));
      expect(
        tester
            .getSize(find.byWidgetPredicate((w) => w is SegmentedButton))
            .height,
        greaterThanOrEqualTo(48),
      );
    });

    for (final dark in [false, true]) {
      testWidgets('a part-met bar stands out at 3:1 on its track'
          '${dark ? ' (dark)' : ''}', (tester) async {
        await openPanel(tester, dark: dark);
        final palette = dark ? AppPalette.dark : AppPalette.light;
        // fibre at 20 g is part met, whatever the reference
        final bar = tester.widget<LinearProgressIndicator>(
          find
              .descendant(
                of: find.ancestor(
                  of: find.text('fiber'),
                  matching: find.byType(Column),
                ),
                matching: find.byType(LinearProgressIndicator),
              )
              .first,
        );
        final colour = bar.valueColor!.value!;
        expect(colour, isNot(palette.accent), reason: 'the part-met colour');
        expect(
          contrastRatio(colour, bar.backgroundColor!),
          greaterThanOrEqualTo(3),
        );
      });
    }
  });

  for (final (name, open) in <(String, void Function(BuildContext))>[
    ('Copy day', (context) => copyDay(context, _day)),
    (
      'copy or move',
      (context) => copyOrMoveIntakes(context, [
        _intake('Porridge'),
        _intake('Toast'),
      ], from: _day),
    ),
  ]) {
    // a phone held either way
    for (final (w, h) in [(360.0, 640.0), (640.0, 360.0)]) {
      testWidgets('the $name sheet stops below the status bar at 2x, '
          '${w.round()} wide', (tester) async {
        await pumpOnPhone(
          tester,
          Builder(
            builder: (context) => TextButton(
              onPressed: () => open(context),
              child: const Text('open'),
            ),
          ),
        );
        tester.view
          ..physicalSize = Size(w * 2.625, h * 2.625)
          ..padding = const FakeViewPadding(top: 24 * 2.625);
        await tester.pump();
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        final top = tester.getTopLeft(find.byType(BottomSheet)).dy;
        expect(top, greaterThanOrEqualTo(24));
      });
    }
  }
}
