import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:opennutritracker/core/domain/entity/profile_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_profiles_usecase.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/features/diary/presentation/bloc/calendar_day_bloc.dart';
import 'package:opennutritracker/features/home/presentation/bloc/home_bloc.dart';
import 'package:opennutritracker/features/meal_detail/presentation/bloc/meal_detail_bloc.dart';
import 'package:opennutritracker/fork/display/week_bars.dart';
import 'package:opennutritracker/fork/screens/diary/day_info_widget.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:provider/provider.dart';

class _FakeMealDetailBloc extends Fake implements MealDetailBloc {}

class _FakeHomeBloc extends Fake implements HomeBloc {}

class _FakeCalendarDayBloc extends Fake implements CalendarDayBloc {}

class _OneProfile implements GetProfilesUsecase {
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

/// The app in German: fork strings stay English, its dates must not.
Widget _german(Widget child) => _inLocale(const Locale('de'), child);

Widget _inLocale(Locale locale, Widget child) =>
    ChangeNotifierProvider<EnergyUnitProvider>(
      create: (_) => EnergyUnitProvider(usesKilojoules: false),
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: const [
          S.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        supportedLocales: S.supportedLocales,
        home: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    );

void main() {
  setUpAll(() {
    final locator = GetIt.instance;
    locator.registerFactory<MealDetailBloc>(_FakeMealDetailBloc.new);
    locator.registerFactory<HomeBloc>(_FakeHomeBloc.new);
    locator.registerFactory<CalendarDayBloc>(_FakeCalendarDayBloc.new);
    locator.registerFactory<GetProfilesUsecase>(_OneProfile.new);
  });

  tearDownAll(GetIt.instance.reset);

  testWidgets('the Diary day heading is in German', (tester) async {
    await tester.pumpWidget(
      _german(
        DayInfoWidget(
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
    );
    await tester.pump();
    expect(find.text('Montag, 15. Juni'), findsOne);
  });

  testWidgets('the week bars name the days in German', (tester) async {
    await tester.pumpWidget(
      _german(
        WeekBars(
          today: DateTime(2026, 10, 25),
          todayKcal: 1800,
          todayGoalKcal: 2500,
          load: (_, _) async => const [],
        ),
      ),
    );
    await tester.pump();
    expect(
      find.bySemanticsLabel(RegExp(r'^Last 7 days: Montag .*Sonntag 1800')),
      findsOne,
    );
    // The day initials under the bars: Mo, Di, Mi, Do, Fr, Sa, So.
    expect(find.text('D'), findsNWidgets(2));
  });

  testWidgets('the week bars\' initials tell the days apart in Chinese', (
    tester,
  ) async {
    Future<List<String>> initials(Locale locale) async {
      await tester.pumpWidget(
        _inLocale(
          locale,
          WeekBars(
            today: DateTime(2026, 10, 25),
            todayKcal: 1800,
            todayGoalKcal: 2500,
            load: (_, _) async => const [],
          ),
        ),
      );
      await tester.pump();
      return [
        for (final t in tester.widgetList<Text>(
          find.descendant(
            of: find.byType(WeekBars),
            matching: find.byType(Text),
          ),
        ))
          t.data!,
      ];
    }

    // Not the first letter of "周一", "周二": every day was "周".
    expect((await initials(const Locale('zh'))).toSet(), hasLength(7));
    expect(await initials(const Locale('en')), [
      'M',
      'T',
      'W',
      'T',
      'F',
      'S',
      'S',
    ]);
  });
}
