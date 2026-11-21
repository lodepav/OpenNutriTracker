// The goals editor's potassium default is the DRI value the goals overview
// judges against for this profile, not the panel's flat 3500 mg (the
// 2026-11-21 G6 critique, nge1.png).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/tracked_day_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_gender_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_pal_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_weight_goal_entity.dart';
import 'package:opennutritracker/features/diary/presentation/bloc/calendar_day_bloc.dart';
import 'package:opennutritracker/features/diary/presentation/bloc/diary_bloc.dart';
import 'package:opennutritracker/features/diary/presentation/widgets/daily_nutrient_panel.dart';
import 'package:opennutritracker/features/home/presentation/bloc/home_bloc.dart';
import 'package:opennutritracker/features/profile/presentation/bloc/profile_bloc.dart';
import 'package:opennutritracker/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:opennutritracker/features/settings/presentation/widgets/nutrient_goals_screen.dart';
import 'package:opennutritracker/generated/l10n.dart';

class _FakeSettingsBloc extends Fake implements SettingsBloc {
  TrackedDayEntity? today;


  @override
  Future<TrackedDayEntity?> getTodayTrackedDay(DateTime day) async => today;

  @override
  Future<DateTime> getCurrentLogicalDay() async => DateTime(2026, 10, 10);

  @override
  Future<void> updateTrackedDay(DateTime day) async {}

  @override
  Future<void> setTodayNutrientGoals(
    DateTime day, {
    double? fibreGoal,
    double? satFatGoal,
    double? sugarsGoal,
    double? sodiumGoal,
    double? calciumGoal,
    double? ironGoal,
    double? potassiumGoal,
    double? vitaminDGoal,
    double? vitaminB12Goal,
    double? magnesiumGoal,
    bool clearAll = false,
  }) async {}

  @override
  void add(SettingsEvent event) {}
}

class _FakeProfileBloc extends Fake implements ProfileBloc {
  final UserEntity user;

  _FakeProfileBloc(this.user);

  @override
  Future<UserEntity> getUser() async => user;
}

class _FakeHomeBloc extends Fake implements HomeBloc {
  @override
  void add(HomeEvent event) {}
}

class _FakeDiaryBloc extends Fake implements DiaryBloc {
  @override
  void add(DiaryEvent event) {}
}

class _FakeCalendarDayBloc extends Fake implements CalendarDayBloc {
  @override
  void add(CalendarDayEvent event) {}
}

UserEntity _user(int age, UserGenderEntity gender) {
  final now = DateTime.now();
  return UserEntity(
    birthday: DateTime(now.year - age, now.month, now.day),
    heightCM: 165,
    weightKG: 60,
    gender: gender,
    goal: UserWeightGoalEntity.maintainWeight,
    pal: UserPALEntity.sedentary,
  );
}

/// Pushes the screen over a placeholder route, so Save has one to pop
/// back to.
Future<void> _open(
  WidgetTester tester, {
  required UserEntity user,
  TrackedDayEntity? today,
  _FakeSettingsBloc? settingsBloc,
}) async {
  // Tall enough that the list builds every row.
  tester.view.physicalSize = const Size(800, 6000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: const [S.delegate],
      supportedLocales: S.supportedLocales,
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => NutrientGoalsScreen(
                settingsBloc: (settingsBloc ?? _FakeSettingsBloc())
                  ..today = today,
                profileBloc: _FakeProfileBloc(user),
                diaryBloc: _FakeDiaryBloc(),
                calendarDayBloc: _FakeCalendarDayBloc(),
                homeBloc: _FakeHomeBloc(),
              ),
            ),
          ),
          child: const Text('Open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

// Rows run fibre, saturated fat, sugars, sodium, calcium, iron, potassium.
const _potassiumRow = 6;

String _potassiumText(WidgetTester tester) => tester
    .widget<TextField>(find.byType(TextField).at(_potassiumRow))
    .controller!
    .text;

double _potassiumSlider(WidgetTester tester) =>
    tester.widget<Slider>(find.byType(Slider).at(_potassiumRow)).value;

void main() {
  test('the flat default this replaces differs from the DRI', () {
    expect(DailyNutrientPanel.defaultPotassiumRefMg, 3500);
  });

  testWidgets('a man with no goal opens at 3400 mg, and the hint says so', (
    tester,
  ) async {
    await _open(tester, user: _user(40, UserGenderEntity.male));

    expect(_potassiumText(tester), '3400');
    expect(_potassiumSlider(tester), 3400);
    expect(
      find.text(
        'Daily potassium target in milligrams. Default for you: 3400 mg.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('3500'), findsNothing);
  });

  testWidgets('a woman with no goal opens at 2600 mg', (tester) async {
    await _open(tester, user: _user(30, UserGenderEntity.female));

    expect(_potassiumText(tester), '2600');
    expect(_potassiumSlider(tester), 2600);
    expect(find.textContaining('Default for you: 2600 mg.'), findsOneWidget);
  });

  testWidgets('Reset returns a saved goal to the DRI value', (tester) async {
    await _open(
      tester,
      user: _user(40, UserGenderEntity.male),
      today: TrackedDayEntity(
        day: DateTime.now(),
        calorieGoal: 2000,
        caloriesTracked: 0,
        potassiumGoal: 4000,
      ),
    );
    expect(_potassiumText(tester), '4000');

    await tester.tap(find.bySemanticsIdentifier('nutrient-goals-reset'));
    await tester.pumpAndSettle();

    expect(_potassiumText(tester), '3400');
    expect(_potassiumSlider(tester), 3400);
  });
}
