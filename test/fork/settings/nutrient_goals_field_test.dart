// The Nutrient goals editor's fields after the round-4 settings critique
// (2026-11-22, G6): each says which goal it sets, and a typed value outside
// the row's range says the range before it is pulled into it.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/tracked_day_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_entity.dart';
import 'package:opennutritracker/features/diary/presentation/bloc/calendar_day_bloc.dart';
import 'package:opennutritracker/features/diary/presentation/bloc/diary_bloc.dart';
import 'package:opennutritracker/features/home/presentation/bloc/home_bloc.dart';
import 'package:opennutritracker/features/profile/presentation/bloc/profile_bloc.dart';
import 'package:opennutritracker/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:opennutritracker/features/settings/presentation/widgets/nutrient_goals_screen.dart';
import 'package:opennutritracker/generated/l10n.dart';

import '../../fixture/user_entity_fixtures.dart';

class _FakeSettingsBloc extends Fake implements SettingsBloc {
  double? savedSodium;
  double? savedIron;
  double? savedVitaminB12;

  @override
  Future<TrackedDayEntity?> getTodayTrackedDay(DateTime day) async => null;

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
  }) async {
    savedSodium = sodiumGoal;
    savedIron = ironGoal;
    savedVitaminB12 = vitaminB12Goal;
  }

  @override
  void add(SettingsEvent event) {}
}

class _FakeProfileBloc extends Fake implements ProfileBloc {
  @override
  Future<UserEntity> getUser() async =>
      UserEntityFixtures.youngSedentaryMaleWantingToMaintainWeight;
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

// Rows run fibre, saturated fat, sugars, sodium, calcium, iron, potassium,
// magnesium, vitamin D, vitamin B12.
const _vitaminB12 = 9;

void main() {
  Future<void> openScreen(WidgetTester tester) async {
    // Tall enough for the ListView to build every row.
    await tester.binding.setSurfaceSize(const Size(400, 3000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [S.delegate],
        supportedLocales: S.supportedLocales,
        home: NutrientGoalsScreen(
          settingsBloc: _FakeSettingsBloc(),
          profileBloc: _FakeProfileBloc(),
          diaryBloc: _FakeDiaryBloc(),
          calendarDayBloc: _FakeCalendarDayBloc(),
          homeBloc: _FakeHomeBloc(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder field(int row) => find.byType(TextField).at(row);

  testWidgets('each field is named for its goal', (tester) async {
    final semantics = tester.ensureSemantics();
    await openScreen(tester);
    final fibre = tester.getSemantics(field(0));
    // Its own node: the row's other words are read apart from it.
    expect(fibre.label, 'Fibre goal');
    expect(fibre.flagsCollection.isTextField, isTrue);
    expect(tester.getSemantics(field(_vitaminB12)).label, 'Vitamin B12 goal');
    semantics.dispose();
  });

  testWidgets('the help text spaces its units, as the fields do (S586)', (
    tester,
  ) async {
    await openScreen(tester);
    expect(find.textContaining('Default reference is 1000 mg.'), findsOneWidget);
    expect(find.textContaining('1000mg'), findsNothing);
  });

  testWidgets('the editor is titled apart from the overview it opens from '
      '(G5-13)', (tester) async {
    await openScreen(tester);
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.text('Edit nutrient goals'),
      ),
      findsOneWidget,
    );
    expect(find.text('Nutrient goals'), findsNothing);
  });

  testWidgets('a value past the range says the range, then is held to it', (
    tester,
  ) async {
    await openScreen(tester);
    await tester.enterText(field(0), '500');
    await tester.pump();
    expect(find.text('From 0 to 80 g'), findsOneWidget);

    await tester.enterText(field(_vitaminB12), '12.5');
    await tester.pump();
    expect(find.text('From 0 to 10 µg'), findsOneWidget);

    await tester.enterText(field(0), '40');
    await tester.pump();
    expect(find.text('From 0 to 80 g'), findsNothing);
  });
}
