// Fork cases moved out of test/features/settings/presentation/widgets/nutrient_goals_decimal_input_test.dart (they test the fork's changes).
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

import '../../../../../../fixture/user_entity_fixtures.dart';
import '../../../../../../helpers/test_l10n.dart';

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
const _sodium = 3;

void main() {
  Future<void> openScreen(
    WidgetTester tester,
    _FakeSettingsBloc settingsBloc,
  ) async {
    // Tall enough for the ListView to build every row.
    await tester.binding.setSurfaceSize(const Size(400, 3000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [S.delegate],
        supportedLocales: S.supportedLocales,
        home: NutrientGoalsScreen(
          settingsBloc: settingsBloc,
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

  String textOf(WidgetTester tester, int row) =>
      tester.widget<TextField>(field(row)).controller!.text;

  /// Clears the field, then types [keys] one at a time the way a keyboard
  /// does, so each keystroke goes through the input formatters on its own.
  Future<void> type(WidgetTester tester, int row, String keys) async {
    await tester.enterText(field(row), '');
    for (final key in keys.split('')) {
      await tester.enterText(field(row), textOf(tester, row) + key);
    }
  }

  testWidgets('the three limits say at most, the targets at least', (
    tester,
  ) async {
    await openScreen(tester, _FakeSettingsBloc());
    expect(find.text('At most'), findsNWidgets(3));
    expect(find.text('At least'), findsNWidgets(7));
  });

  Future<void> openOver(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 3000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [S.delegate],
        supportedLocales: S.supportedLocales,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => NutrientGoalsScreen(
                  settingsBloc: _FakeSettingsBloc(),
                  profileBloc: _FakeProfileBloc(),
                  diaryBloc: _FakeDiaryBloc(),
                  calendarDayBloc: _FakeCalendarDayBloc(),
                  homeBloc: _FakeHomeBloc(),
                ),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Future<void> back(WidgetTester tester) async {
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
  }

  testWidgets('Back with nothing changed leaves at once', (tester) async {
    await openOver(tester);
    await back(tester);
    expect(find.byType(NutrientGoalsScreen), findsNothing);
  });

  testWidgets('Back after typing a goal asks first', (tester) async {
    await openOver(tester);
    await type(tester, _sodium, '1500');
    await back(tester);
    expect(find.text(l10nEn.discardChangesTitle), findsOneWidget);
    await tester.tap(find.text(l10nEn.dialogCancelLabel));
    await tester.pumpAndSettle();
    expect(find.byType(NutrientGoalsScreen), findsOneWidget);

    await back(tester);
    await tester.tap(find.text(l10nEn.discardChangesConfirmLabel));
    await tester.pumpAndSettle();
    expect(find.byType(NutrientGoalsScreen), findsNothing);
  });

  testWidgets('a slider says its nutrient and its value', (tester) async {
    final semantics = tester.ensureSemantics();
    await openScreen(tester, _FakeSettingsBloc());
    expect(
      find.semantics.byPredicate(
        (node) =>
            node.value == '${l10nEn.settingsSodiumGoalLabel}, 2300 milligrams',
      ),
      findsOne,
    );
    semantics.dispose();
  });
}
