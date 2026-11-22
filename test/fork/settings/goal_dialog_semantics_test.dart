// What a screen reader hears from the goal dialogs' sliders and fields
// (the 2026-11-21 G6 critique, A5).
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/user_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_user_usecase.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/diary/presentation/bloc/calendar_day_bloc.dart';
import 'package:opennutritracker/features/home/presentation/bloc/home_bloc.dart';
import 'package:opennutritracker/features/profile/presentation/bloc/profile_bloc.dart';
import 'package:opennutritracker/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:opennutritracker/features/settings/presentation/widgets/kcal_adjustment_dialog.dart';
import 'package:opennutritracker/features/settings/presentation/widgets/macro_split_dialog.dart';
import 'package:opennutritracker/features/settings/presentation/widgets/per_meal_kcal_share_dialog.dart';
import 'package:opennutritracker/features/settings/presentation/widgets/water_goal_dialog.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:provider/provider.dart';

import '../../fixture/user_entity_fixtures.dart';

class _SettingsBloc extends Fake implements SettingsBloc {
  @override
  Future<double> getKcalAdjustment() async => 0;
  @override
  Future<int?> getDailyWaterGoalMl() async => 1500;
  @override
  Future<double?> getUserCarbGoalPct() async => 0.6;
  @override
  Future<double?> getUserProteinGoalPct() async => 0.15;
  @override
  Future<double?> getUserFatGoalPct() async => 0.25;
  @override
  Future<Map<String, int>> getMealKcalSharesPct() async => {};
  @override
  void add(SettingsEvent event) {}
}

class _ProfileBloc extends Fake implements ProfileBloc {
  @override
  Future<UserEntity> getUser() async =>
      UserEntityFixtures.youngSedentaryMaleWantingToMaintainWeight;
  @override
  void add(ProfileEvent event) {}
}

class _GetUser extends Fake implements GetUserUsecase {
  @override
  Future<UserEntity> getUserData() async =>
      UserEntityFixtures.youngSedentaryMaleWantingToMaintainWeight;
}

class _HomeBloc extends Fake implements HomeBloc {}

class _CalendarDayBloc extends Fake implements CalendarDayBloc {}

Future<void> _open(WidgetTester tester, Widget dialog) async {
  await tester.pumpWidget(
    ChangeNotifierProvider<EnergyUnitProvider>(
      create: (_) => EnergyUnitProvider(),
      child: MaterialApp(
        localizationsDelegates: const [S.delegate],
        supportedLocales: S.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () =>
                  showDialog<void>(context: context, builder: (_) => dialog),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

/// The label of the one slider node a screen reader hears as [value].
String _sliderLabel(String value) {
  final node = find.semantics.byValue(value).evaluate().single;
  final data = node.getSemanticsData();
  expect(data.flagsCollection.isSlider, isTrue, reason: value);
  return data.label;
}

void main() {
  late SemanticsHandle semantics;

  setUp(() {
    semantics = SemanticsBinding.instance.ensureSemantics();
    locator.registerSingleton<GetUserUsecase>(_GetUser());
    locator.registerSingleton<ProfileBloc>(_ProfileBloc());
  });
  tearDown(() async {
    semantics.dispose();
    await locator.reset();
  });

  testWidgets('the kcal slider says its name and amount', (tester) async {
    await _open(
      tester,
      KcalAdjustmentDialog(
        settingsBloc: _SettingsBloc(),
        profileBloc: _ProfileBloc(),
        homeBloc: _HomeBloc(),
      ),
    );
    expect(_sliderLabel('0 kcal'), 'Daily kcal adjustment');
  });

  testWidgets('the water slider says its name and amount', (tester) async {
    await _open(
      tester,
      WaterGoalDialog(settingsBloc: _SettingsBloc(), homeBloc: _HomeBloc()),
    );
    expect(_sliderLabel('1500 ml'), 'Daily water goal');
  });

  testWidgets('each meal-share slider says which meal it sets', (
    tester,
  ) async {
    await _open(
      tester,
      PerMealKcalShareDialog(
        settingsBloc: _SettingsBloc(),
        homeBloc: _HomeBloc(),
        calendarDayBloc: _CalendarDayBloc(),
      ),
    );
    expect(_sliderLabel('30%'), 'Breakfast');
    expect(_sliderLabel('40%'), 'Lunch');
    expect(_sliderLabel('20%'), 'Dinner');
    expect(_sliderLabel('10%'), 'Snack');
    // The row's own word, and the rebalance said before it surprises
    // (G6-7, G6-12)
    expect(
      find.textContaining('dinner and snack. Moving one share moves the '
          'other three'),
      findsOneWidget,
    );
  });

  testWidgets('macro split names each macro in sentence case, on its '
      'slider and its field', (tester) async {
    await _open(
      tester,
      MacroSplitDialog(settingsBloc: _SettingsBloc(), homeBloc: _HomeBloc()),
    );
    for (final name in ['Carbs', 'Fat', 'Protein']) {
      expect(find.text(name), findsOneWidget, reason: name);
    }
    expect(_sliderLabel('60%'), 'Carbs');
    expect(_sliderLabel('15%'), 'Protein');
    expect(_sliderLabel('25%'), 'Fat');
    for (final name in ['Carbs', 'Fat', 'Protein']) {
      expect(
        find.semantics.byPredicate((n) {
          final d = n.getSemanticsData();
          return d.label == name && d.flagsCollection.isTextField;
        }),
        findsOneWidget,
        reason: name,
      );
    }
    // One node per field: the label joins the field rather than sitting
    // beside it.
    expect(
      find.semantics.byPredicate(
        (n) => n.getSemanticsData().flagsCollection.isTextField,
      ),
      findsNWidgets(3),
    );
  });
}
