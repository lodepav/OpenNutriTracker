import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/app_theme_entity.dart';
import 'package:opennutritracker/core/domain/entity/body_weight_unit_entity.dart';
import 'package:opennutritracker/core/domain/entity/config_entity.dart';
import 'package:opennutritracker/core/domain/entity/kcal_goal_breakdown_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_gender_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_pal_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_weight_goal_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/core/utils/calc/unit_calc.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/onboarding/domain/entity/user_activity_selection_entity.dart';
import 'package:opennutritracker/features/onboarding/domain/entity/user_data_mask_entity.dart';
import 'package:opennutritracker/features/onboarding/domain/entity/user_gender_selection_entity.dart';
import 'package:opennutritracker/features/onboarding/domain/entity/user_goal_selection_entity.dart';
import 'package:opennutritracker/features/onboarding/presentation/bloc/onboarding_bloc.dart';
import 'package:opennutritracker/features/settings/presentation/widgets/kcal_goal_info_screen.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_store.dart';
import 'package:opennutritracker/fork/goal/goal_explained.dart';
import 'package:opennutritracker/fork/goal/goal_planner.dart';
import 'package:opennutritracker/fork/goal/onboarding_goal.dart';
import 'package:opennutritracker/fork/goal/planner_screen.dart';
import 'package:opennutritracker/fork/phases/phases.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:provider/provider.dart';

import '../../helpers/test_l10n.dart';

class _Bloc extends Fake implements OnboardingBloc {
  @override
  UserDataMaskEntity userSelection;

  _Bloc([UserDataMaskEntity? selection])
    : userSelection =
          selection ??
          UserDataMaskEntity(
            heightUsesImperial: true,
            bodyWeightUnit: BodyWeightUnit.lb,
          );
}

class _Config extends Fake implements GetConfigUsecase {
  @override
  Future<ConfigEntity> getConfig() async => ConfigEntity(
    true,
    true,
    false,
    AppThemeEntity.values.first,
    usesImperialHeightUnits: true,
    bodyWeightUnit: BodyWeightUnit.st,
  );
}

class _Store extends Fake implements AdaptiveStore {
  @override
  Future<void> save(AdaptiveSettings value) async =>
      AdaptiveStore.settings.value = value;

  @override
  Future<CheckInRecord?> lastCheckIn() async => null;
}

Future<void> _pump(WidgetTester tester, Widget home) async {
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

// 5 ft 6 in and 165 lb, as typed in onboarding.
final _breakdown = KcalGoalBreakdownEntity.compute(
  user: UserEntity(
    birthday: DateTime(1990, 6, 15),
    heightCM: 167.64,
    weightKG: UnitCalc.lbsToKg(165),
    gender: UserGenderEntity.female,
    goal: UserWeightGoalEntity.loseWeight,
    pal: UserPALEntity.active,
  ),
  totalKcalActivities: 0,
);

/// The first-run critique of 2026-11-21, round 2.
void main() {
  group('the inputs in the user units', () {
    test('ft and in with the cm the formula uses', () {
      expect(heightInputText(l10nEn, 167.64, true), '5 ft 6 in (168 cm)');
      expect(heightInputText(l10nEn, 167.64, false), '168 cm');
    });

    test('lb and st with the kg the formula uses', () {
      final kg = UnitCalc.lbsToKg(165);
      expect(
        weightInputText(l10nEn, kg, BodyWeightUnit.lb),
        '165 lb (74.8 kg)',
      );
      expect(
        weightInputText(l10nEn, kg, BodyWeightUnit.st),
        '11 st 11 lb (74.8 kg)',
      );
      expect(weightInputText(l10nEn, kg, BodyWeightUnit.kg), '74.8 kg');
    });

    testWidgets("onboarding's link: titled as the link, onboarding's units", (
      tester,
    ) async {
      locator.registerSingleton<OnboardingBloc>(_Bloc());
      addTearDown(() => locator.unregister<OnboardingBloc>());
      await _pump(
        tester,
        KcalGoalInfoScreen(
          breakdown: _breakdown,
          equations: true,
          onboarding: true,
        ),
      );
      expect(find.text(l10nEn.settingsKcalGoalInfoLabel), findsOneWidget);
      expect(find.text('The equations'), findsNothing);
      expect(find.text('5 ft 6 in (168 cm)'), findsOneWidget);
      expect(find.text('165 lb (74.8 kg)'), findsOneWidget);
    });

    testWidgets("Settings' page reads the saved units", (tester) async {
      locator.registerSingleton<GetConfigUsecase>(_Config());
      addTearDown(() => locator.unregister<GetConfigUsecase>());
      await _pump(tester, KcalGoalInfoScreen(breakdown: _breakdown));
      await tester.scrollUntilVisible(
        find.byKey(const Key('goal-equations')),
        100,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        find.textContaining('5 ft 6 in (168 cm) · 11 st 11 lb (74.8 kg)'),
        findsOneWidget,
      );
      await tester.ensureVisible(find.byKey(const Key('goal-equations')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('goal-equations')));
      await tester.pumpAndSettle();
      // Opened from the tile, the page keeps its name.
      expect(find.text('The equations'), findsOneWidget);
      expect(find.text('11 st 11 lb (74.8 kg)'), findsOneWidget);
    });
  });

  group('the planner from onboarding', () {
    GoalPlannerScreen planner({bool onboarding = true}) => GoalPlannerScreen(
      setup: PlannerSetup(
        nowKg: 86.4,
        unit: BodyWeightUnit.kg,
        expenditureKcal: 3045,
        bodyFatPercent: 22,
        onboarding: onboarding,
      ),
      draft: GoalDraft.fresh(86.4, DateTime(2026, 11, 21), targetKg: 80),
      onStart: (_) async => true,
      store: _Store(),
    );

    Widget opener(GoalPlannerScreen screen) => Scaffold(
      body: Builder(
        builder: (context) => TextButton(
          onPressed: () => Navigator.of(
            context,
          ).push(MaterialPageRoute<bool>(builder: (_) => screen)),
          child: const Text('open'),
        ),
      ),
    );

    for (final onboarding in [true, false]) {
      testWidgets('left untouched it closes without asking '
          '(onboarding: $onboarding)', (tester) async {
        await _pump(tester, opener(planner(onboarding: onboarding)));
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Close'));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        expect(find.text('open'), findsOneWidget);
      });
    }

    testWidgets('changed, it asks without a goal to stay', (tester) async {
      addTearDown(
        () => AdaptiveStore.settings.value = const AdaptiveSettings(),
      );
      await _pump(tester, opener(planner()));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Maintain'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(find.text('Leave the planner?'), findsOneWidget);
      expect(find.text('Nothing you set here is kept.'), findsOneWidget);
    });

    testWidgets('the goal page opens it on the goal chosen there', (
      tester,
    ) async {
      locator.registerSingleton<OnboardingBloc>(
        _Bloc(
          UserDataMaskEntity(
            gender: UserGenderSelectionEntity.genderFemale,
            birthday: DateTime(1990, 6, 15),
            height: 168,
            weight: 75,
            activity: UserActivitySelectionEntity.active,
            goal: UserGoalSelectionEntity.maintainWeight,
          ),
        ),
      );
      addTearDown(() => locator.unregister<OnboardingBloc>());
      await _pump(tester, Scaffold(body: OnboardingPlanRow(onPlanned: (_) {})));
      await tester.tap(find.text('Plan your goal'));
      await tester.pumpAndSettle();
      expect(
        tester.getSemantics(find.bySemanticsIdentifier('goal-kind-maintain')),
        isSemantics(isChecked: true),
      );
    });

    test('a new plan starts on the goal chosen on the page', () {
      final today = DateTime(2026, 11, 21);
      GoalDraft draft(UserGoalSelectionEntity? chosen) =>
          OnboardingGoal.freshDraft(86.4, today, targetKg: 80, chosen: chosen);
      expect(draft(null).kind, PhaseKind.cut);
      expect(draft(UserGoalSelectionEntity.loseWeight), draft(null));
      final maintain = draft(UserGoalSelectionEntity.maintainWeight);
      expect(maintain.kind, PhaseKind.maintain);
      expect(maintain.paceKg, 0);
      final gain = draft(UserGoalSelectionEntity.gainWeigh);
      expect(gain.kind, PhaseKind.bulk);
      expect(gain.paceKg, bulkPacesKg[1]);
    });
  });
}
