import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/app_theme_entity.dart';
import 'package:opennutritracker/core/domain/entity/body_weight_unit_entity.dart';
import 'package:opennutritracker/core/domain/entity/config_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/onboarding/domain/entity/user_goal_selection_entity.dart';
import 'package:opennutritracker/features/onboarding/presentation/widgets/onboarding_body_measurements_page_body.dart';
import 'package:opennutritracker/features/onboarding/presentation/widgets/onboarding_goal_page_body.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_store.dart';
import 'package:opennutritracker/fork/adaptive/expenditure_settings_ui.dart';
import 'package:opennutritracker/fork/goal/goal_planner.dart';
import 'package:opennutritracker/fork/goal/onboarding_goal.dart';
import 'package:opennutritracker/fork/goal/planner_screen.dart';
import 'package:opennutritracker/fork/phases/phases.dart';
import 'package:opennutritracker/fork/units/energy_text.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:provider/provider.dart';

import '../../helpers/test_l10n.dart';
import '../../helpers/ux_checks.dart';

class _Store extends AdaptiveStore {
  @override
  Future<void> save(AdaptiveSettings value) async =>
      AdaptiveStore.settings.value = value;

  @override
  Future<CheckInRecord?> lastCheckIn() async => null;
}

class _Config extends Fake implements GetConfigUsecase {
  @override
  Future<ConfigEntity> getConfig() async => ConfigEntity(
    true,
    true,
    false,
    AppThemeEntity.values.first,
    bodyWeightUnit: BodyWeightUnit.lb,
  );
}

Future<void> _pump(WidgetTester tester, Widget home) async {
  // Tall, so a step's whole list is built.
  tester.view.physicalSize = const Size(800, 5000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ChangeNotifierProvider(
      create: (_) => EnergyUnitProvider(usesKilojoules: false),
      child: MaterialApp(
        localizationsDelegates: const [
          S.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: S.supportedLocales,
        home: home,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

final _day0 = DateTime(2026, 11, 21);

/// What a first run has not met yet.
final _notMet = RegExp('adaptive|check-in|trends|diary', caseSensitive: false);

/// The first-run critique of 2026-11-21, round 3.
void main() {
  tearDown(() {
    AdaptiveStore.settings.value = const AdaptiveSettings();
    OnboardingGoal.pending.value = null;
  });

  test('energy a unit of weight: per kg, else the familiar per lb', () {
    expect(kcalPerWeightUnit(7700, BodyWeightUnit.kg), 7700);
    expect(kcalPerWeightUnit(7700, BodyWeightUnit.lb), 3500);
    expect(kcalPerWeightUnit(7700, BodyWeightUnit.st), 3500);
  });

  group('body measurements', () {
    testWidgets('inches over 11 are named, not the height range', (
      tester,
    ) async {
      final showErrors = ValueNotifier<int>(0);
      addTearDown(showErrors.dispose);
      await pumpOnPhone(
        tester,
        OnboardingBodyMeasurementsPageBody(
          setButtonContent: (_, _, _, _, _, _, _) {},
          showErrorsSignal: showErrors,
          initialHeightImperial: true,
          initialBodyWeightUnit: BodyWeightUnit.lb,
        ),
        textScale: 1,
      );
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), '5');
      await tester.enterText(fields.at(1), '13');
      showErrors.value++;
      await tester.pump();
      expect(find.text('Inches 0 to 11'), findsOneWidget);
      expect(find.textContaining('Height between'), findsNothing);
      // Fixed, the line goes; a height out of range gets the range again.
      await tester.enterText(fields.at(1), '11');
      await tester.pump();
      expect(find.text('Inches 0 to 11'), findsNothing);
      await tester.enterText(fields.at(0), '12');
      await tester.pump();
      expect(find.text('Height between 1 and 9 ft'), findsOneWidget);
    });
  });

  group('goal page', () {
    testWidgets('a goal against the plan clears it; the plan\'s own keeps it', (
      tester,
    ) async {
      OnboardingGoal.pending.value = GoalDraft(
        kind: PhaseKind.cut,
        startKg: 79,
        targetKg: 72.6,
        start: _day0,
        paceKg: 0.5,
      ).toPlan();
      final picked = <UserGoalSelectionEntity?>[];
      await pumpOnPhone(
        tester,
        OnboardingGoalPageBody(
          setButtonContent: (_, goal) => picked.add(goal),
          initialGoal: UserGoalSelectionEntity.loseWeight,
        ),
        textScale: 1,
      );
      expect(find.text('Your plan'), findsOneWidget);
      await tester.tap(find.text(l10nEn.goalLoseWeight));
      await tester.pump();
      expect(find.text('Your plan'), findsOneWidget);
      await tester.tap(find.text(l10nEn.goalMaintainWeight));
      await tester.pump();
      expect(OnboardingGoal.pending.value, isNull);
      expect(find.text('Your plan'), findsNothing);
      expect(find.text('Plan your goal'), findsOneWidget);
      expect(picked.last, UserGoalSelectionEntity.maintainWeight);
    });
  });

  group('the planner at first run', () {
    GoalPlannerScreen planner({required bool onboarding}) => GoalPlannerScreen(
      setup: PlannerSetup(
        nowKg: 79,
        unit: BodyWeightUnit.lb,
        expenditureKcal: 2386,
        formulaKcal: 2386,
        bodyFatPercent: 22,
        onboarding: onboarding,
      ),
      draft: GoalDraft.fresh(79, _day0, targetKg: 72.6),
      today: _day0,
      store: _Store(),
      onStart: (_) async => true,
    );

    Future<void> toStep(WidgetTester tester, String name) async {
      while (find
          .byKey(ValueKey('goal-planner-step-$name'))
          .evaluate()
          .isEmpty) {
        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();
      }
    }

    testWidgets('the expenditure step leaves out what is not met yet, and '
        'counts energy a lb', (tester) async {
      await _pump(tester, planner(onboarding: true));
      await toStep(tester, 'burn');
      expect(find.textContaining(_notMet), findsNothing);
      expect(find.text('Days left out'), findsNothing);
      expect(find.textContaining('every kg'), findsNothing);
      // At first run the estimate's settings are folded (G1-24).
      await tester.tap(find.text('Fine-tune the estimate'));
      await tester.pumpAndSettle();
      expect(find.textContaining(_notMet), findsNothing);
      expect(find.textContaining('every kg'), findsNothing);
      expect(find.text('Count every lb as 3500 kcal'), findsOneWidget);
    });

    testWidgets('the target step folds Formula against Adaptive away', (
      tester,
    ) async {
      await _pump(tester, planner(onboarding: true));
      await toStep(tester, 'target');
      expect(find.textContaining(_notMet), findsNothing);
      // The target's other modes are there, folded.
      await tester.tap(find.text('Other ways to set the target'));
      await tester.pumpAndSettle();
      expect(find.text('Adaptive'), findsOneWidget);
      expect(find.text('Fixed'), findsOneWidget);
    });

    testWidgets('outside onboarding the Formula line counts a lb too', (
      tester,
    ) async {
      await _pump(tester, planner(onboarding: false));
      await toStep(tester, 'burn');
      expect(
        find.textContaining('Formula counts every lb as 3500 kcal'),
        findsOneWidget,
      );
      expect(find.text('Days left out'), findsOneWidget);
    });

    testWidgets('the pace reads the same on every step', (tester) async {
      await _pump(tester, planner(onboarding: true));
      await toStep(tester, 'pace');
      expect(find.textContaining('1.1 lb a week'), findsWidgets);
      await toStep(tester, 'target');
      expect(find.text('Pace, 1.1 lb a week'), findsOneWidget);
    });
  });

  testWidgets("Settings' expenditure screen counts energy in the saved unit", (
    tester,
  ) async {
    locator.registerSingleton<GetConfigUsecase>(_Config());
    addTearDown(() => locator.unregister<GetConfigUsecase>());
    await _pump(tester, ExpenditureSettingsScreen(store: _Store()));
    expect(find.text('Count every lb as 3500 kcal'), findsOneWidget);
  });
}
