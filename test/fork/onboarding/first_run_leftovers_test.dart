import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/app_theme_entity.dart';
import 'package:opennutritracker/core/domain/entity/body_weight_unit_entity.dart';
import 'package:opennutritracker/core/domain/entity/config_entity.dart';
import 'package:opennutritracker/core/domain/usecase/add_config_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/add_user_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/add_weight_log_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/delete_all_user_data_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/core/presentation/splash_screen.dart';
import 'package:opennutritracker/core/presentation/storage_recovery_app.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/utils/ai_credential_storage.dart';
import 'package:opennutritracker/core/utils/daily_reminder_scheduler.dart';
import 'package:opennutritracker/features/add_meal/domain/usecase/run_ai_endpoint_probe_usecase.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/core/utils/navigation_options.dart';
import 'package:opennutritracker/features/onboarding/domain/entity/user_gender_selection_entity.dart';
import 'package:opennutritracker/features/onboarding/onboarding_screen.dart';
import 'package:opennutritracker/features/onboarding/presentation/bloc/onboarding_bloc.dart';
import 'package:opennutritracker/features/onboarding/presentation/onboarding_intro_page_body.dart';
import 'package:opennutritracker/features/onboarding/presentation/widgets/highlight_button.dart';
import 'package:opennutritracker/features/onboarding/presentation/widgets/onboarding_goal_page_body.dart';
import 'package:opennutritracker/features/onboarding/presentation/widgets/onboarding_other_options_page_body.dart';
import 'package:opennutritracker/fork/settings/accent_view.dart';
import 'package:opennutritracker/core/utils/theme_mode_provider.dart';
import 'package:opennutritracker/features/profile/presentation/widgets/body_weight_input.dart';
import 'package:opennutritracker/features/profile/presentation/widgets/feet_inches_input.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_store.dart';
import 'package:opennutritracker/fork/goal/goal_planner.dart';
import 'package:opennutritracker/fork/goal/onboarding_goal.dart';
import 'package:opennutritracker/fork/goal/planner_screen.dart';
import 'package:opennutritracker/fork/screens/onboarding/onboarding_about_you_page_body.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../../helpers/test_l10n.dart';
import '../../helpers/ux_checks.dart';

/// What was left for first run on 2026-11-22: G1-6, G1-13, G1-20, G1-24,
/// G1-29, G1-32 and the audit's P3s.

const _delegates = [
  S.delegate,
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];

Widget _app(Widget home) => ChangeNotifierProvider(
  create: (_) => EnergyUnitProvider(usesKilojoules: false),
  child: MaterialApp(
    localizationsDelegates: _delegates,
    supportedLocales: S.supportedLocales,
    home: home,
  ),
);

void _surface(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

class _Store extends AdaptiveStore {
  @override
  Future<void> save(AdaptiveSettings value) async =>
      AdaptiveStore.settings.value = value;

  @override
  Future<CheckInRecord?> lastCheckIn() async => null;
}

class _Config extends Fake implements GetConfigUsecase {
  @override
  Future<bool> hasExplicitUnitPreferences() async => true;

  @override
  Future<bool> hasExplicitFoodSourceToggles() async => true;

  @override
  Future<ConfigEntity> getConfig() async =>
      const ConfigEntity(false, false, false, AppThemeEntity.system);
}

class _AddUser extends Fake implements AddUserUsecase {}

class _AddConfig extends Fake implements AddConfigUsecase {}

class _AddWeight extends Fake implements AddWeightLogUsecase {}

class _Reminders extends Fake implements DailyReminderScheduler {}

class _Keys extends Fake implements AiCredentialStorage {}

class _Probe extends Fake implements AiEndpointProbeRunner {}

/// A demo wipe that has not finished.
class _PendingWipe extends Fake implements DeleteAllUserDataUsecase {
  final done = Completer<void>();

  @override
  Future<void> deleteAll() => done.future;
}

final _day0 = DateTime(2026, 11, 21);

GoalPlannerScreen _planner({bool onboarding = true}) => GoalPlannerScreen(
  setup: PlannerSetup(
    nowKg: 79,
    unit: BodyWeightUnit.kg,
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

Future<void> _toStep(WidgetTester tester, String name) async {
  while (find.byKey(ValueKey('goal-planner-step-$name')).evaluate().isEmpty) {
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
  }
}

Future<void> _pumpOnboarding(WidgetTester tester) async {
  locator.registerSingleton<OnboardingBloc>(
    OnboardingBloc(
      _AddUser(),
      _AddConfig(),
      _Config(),
      _AddWeight(),
      _Reminders(),
    ),
  );
  locator.registerSingleton<AiCredentialStorage>(_Keys());
  locator.registerSingleton<AiEndpointProbeRunner>(_Probe());
  addTearDown(() {
    locator.unregister<OnboardingBloc>();
    locator.unregister<AiCredentialStorage>();
    locator.unregister<AiEndpointProbeRunner>();
  });
  await tester.pumpWidget(_app(const OnboardingScreen()));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() {
    PackageInfo.setMockInitialValues(
      appName: 'OpenBite',
      packageName: 'test',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  tearDown(() {
    AdaptiveStore.settings.value = const AdaptiveSettings();
    OnboardingGoal.pending.value = null;
  });

  group('G1-20: a pair with its second half empty', () {
    testWidgets('5 ft is 5 ft 0 in; inches alone are no height', (
      tester,
    ) async {
      double? cm = -1;
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: FeetInchesInput(
              initialCm: null,
              onChangedCm: (v) => cm = v,
              identifierPrefix: 't',
            ),
          ),
        ),
      );
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), '5');
      expect(cm, closeTo(152.4, 0.5));
      await tester.enterText(fields.at(0), '');
      await tester.enterText(fields.at(1), '7');
      expect(cm, isNull);
    });

    testWidgets('11 st is 11 st 0 lb; pounds alone are no weight', (
      tester,
    ) async {
      double? kg = -1;
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: BodyWeightInput(
              initialKg: null,
              unit: BodyWeightUnit.st,
              onChangedKg: (v) => kg = v,
              identifierPrefix: 't',
            ),
          ),
        ),
      );
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), '11');
      expect(kg, closeTo(69.85, 0.01));
      await tester.enterText(fields.at(0), '');
      await tester.enterText(fields.at(1), '7');
      expect(kg, isNull);
    });
  });

  group('G1-32: the splash', () {
    Future<void> pumpSplash(WidgetTester tester) => tester.pumpWidget(
      MaterialApp(
        initialRoute: NavigationOptions.splashRoute,
        routes: {
          NavigationOptions.splashRoute: (_) =>
              const SplashScreen(userInitialized: false),
          NavigationOptions.onboardingRoute: (_) => const Text('onboarding'),
        },
      ),
    );

    testWidgets('leaves within 300 ms, and its logo is named', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpSplash(tester);
      expect(find.bySemanticsLabel('OpenBite'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(find.text('onboarding'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('leaves within 300 ms with animations off', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await pumpSplash(tester);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(find.text('onboarding'), findsOneWidget);
    });
  });

  group('G1-29: width cap', () {
    testWidgets('onboarding is centred at 600 dp on a tablet', (tester) async {
      _surface(tester, const Size(1200, 900));
      await _pumpOnboarding(tester);
      final rect = tester.getRect(find.byType(HighlightButton));
      // The footer's button sits in the capped page, 16 dp in from each side.
      expect(rect.width, lessThanOrEqualTo(600));
      expect(rect.center.dx, moreOrLessEquals(600, epsilon: 0.5));
    });

    testWidgets('a phone keeps its full width', (tester) async {
      _surface(tester, const Size(400, 900));
      await _pumpOnboarding(tester);
      expect(
        tester.getSize(find.byType(PageView)).width,
        moreOrLessEquals(400, epsilon: 0.5),
      );
    });

    testWidgets('the planner is centred at 600 dp on a tablet', (tester) async {
      _surface(tester, const Size(1200, 900));
      await tester.pumpWidget(_app(_planner()));
      await tester.pumpAndSettle();
      final list = tester.getRect(find.byType(ListView).first);
      expect(list.width, moreOrLessEquals(600, epsilon: 0.5));
      expect(list.center.dx, moreOrLessEquals(600, epsilon: 0.5));
      final next = tester.getRect(find.widgetWithText(FilledButton, 'Next'));
      expect(next.right, lessThanOrEqualTo(900));
    });
  });

  group('G1-24: the planner in plain words', () {
    testWidgets('step 3 folds the estimate\'s settings at first run', (
      tester,
    ) async {
      _surface(tester, const Size(800, 5000));
      await tester.pumpWidget(_app(_planner()));
      await tester.pumpAndSettle();
      await _toStep(tester, 'burn');
      expect(find.text('Fine-tune the estimate'), findsOneWidget);
      expect(find.byKey(const ValueKey('flat-energy')), findsNothing);
      await tester.tap(find.text('Fine-tune the estimate'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('flat-energy')), findsOneWidget);
    });

    testWidgets('from the goal page the estimate stays open', (tester) async {
      _surface(tester, const Size(800, 5000));
      await tester.pumpWidget(_app(_planner(onboarding: false)));
      await tester.pumpAndSettle();
      await _toStep(tester, 'burn');
      expect(find.text('Fine-tune the estimate'), findsNothing);
      expect(find.byKey(const ValueKey('flat-energy')), findsOneWidget);
    });

    testWidgets('step 5 says what the numbers are; step 6 has no formula '
        'talk at first run', (tester) async {
      _surface(tester, const Size(800, 5000));
      await tester.pumpWidget(_app(_planner()));
      await tester.pumpAndSettle();
      await _toStep(tester, 'macros');
      expect(find.textContaining('macro split'), findsNothing);
      expect(find.textContaining('The grams of each'), findsOneWidget);
      expect(find.textContaining('by your split'), findsNothing);
      await _toStep(tester, 'plan');
      expect(find.textContaining('by the formula'), findsNothing);
      expect(find.textContaining('your split'), findsNothing);
      expect(
        find.textContaining('a day, from your age, height, weight'),
        findsOneWidget,
      );
    });
  });

  group('G1-13 and G1-6: lows', () {
    testWidgets('the policy link\'s underline starts on the word', (
      tester,
    ) async {
      await pumpOnPhone(
        tester,
        OnboardingIntroPageBody(setPageContent: (_, _) {}),
        textScale: 1,
      );
      TextSpan? link;
      String? row;
      for (final r in tester.widgetList<RichText>(find.byType(RichText))) {
        r.text.visitChildren((span) {
          if (span is TextSpan &&
              span.style?.decoration == TextDecoration.underline) {
            link = span;
            row = r.text.toPlainText();
          }
          return true;
        });
      }
      expect(link?.text, 'privacy policy');
      // the sentence names the policy once
      expect(row, 'I have read and accept the privacy policy.');
    });

    testWidgets('the intro says when the demo seeds and when it stops', (
      tester,
    ) async {
      final wipe = _PendingWipe();
      locator.registerSingleton<DeleteAllUserDataUsecase>(wipe);
      addTearDown(() => locator.unregister<DeleteAllUserDataUsecase>());
      final busy = <bool>[];
      await pumpOnPhone(
        tester,
        OnboardingIntroPageBody(
          setPageContent: (_, _) {},
          initialAcceptedPolicy: true,
          onBusy: busy.add,
        ),
        textScale: 1,
      );
      final demo = find.widgetWithText(
        OutlinedButton,
        l10nEn.onboardingTryDemoLabel,
      );
      await tester.ensureVisible(demo);
      await tester.tap(demo);
      await tester.pump();
      expect(busy, [true]);
      // The seed fails past the wipe (nothing else is registered).
      wipe.done.complete();
      await tester.pump();
      await tester.pump();
      expect(busy, [true, false]);
    });

    testWidgets('Start waits while the demo seeds', (tester) async {
      _surface(tester, const Size(400, 1600));
      final wipe = _PendingWipe();
      locator.registerSingleton<DeleteAllUserDataUsecase>(wipe);
      addTearDown(() => locator.unregister<DeleteAllUserDataUsecase>());
      await _pumpOnboarding(tester);
      await tester.tap(find.byType(Checkbox).first);
      await tester.pump();
      final demo = find.widgetWithText(
        OutlinedButton,
        l10nEn.onboardingTryDemoLabel,
      );
      await tester.ensureVisible(demo);
      await tester.tap(demo);
      await tester.pump();
      await tester.tap(find.text(l10nEn.buttonStartLabel));
      await tester.pump();
      expect(find.text('Wait until it has loaded.'), findsOneWidget);
      wipe.done.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('the chosen gender shows the check, not over the symbol', (
      tester,
    ) async {
      await pumpOnPhone(
        tester,
        OnboardingAboutYouPageBody(
          setPageContent: (_, _, _, _) {},
          initialGender: UserGenderSelectionEntity.genderFemale,
        ),
        textScale: 1,
      );
      final chips = tester.widgetList<ChoiceChip>(find.byType(ChoiceChip));
      for (final chip in chips) {
        expect(chip.avatar == null, chip.selected, reason: '${chip.label}');
      }
    });

    testWidgets('Suggested is a label, not a filled pill like the chips', (
      tester,
    ) async {
      await pumpOnPhone(
        tester,
        OnboardingGoalPageBody(
          setButtonContent: (_, _) {},
          heightCm: 180,
          weightKg: 110,
        ),
        textScale: 1,
      );
      final badge = find.text(l10nEn.onboardingGoalSuggestedBadge);
      expect(badge, findsOneWidget);
      final filled = find.ancestor(
        of: badge,
        matching: find.byWidgetPredicate(
          (w) => w is Container && w.decoration is BoxDecoration,
        ),
      );
      expect(filled, findsNothing);
    });

    testWidgets('the recovery screen wears the app\'s palette and names '
        'where to report', (tester) async {
      await tester.pumpWidget(
        StorageRecoveryApp(
          errorCode: 'hive_encryption_key_missing_with_existing_data',
          onRetry: () async {},
        ),
      );
      final scaffold = tester.element(find.byType(Scaffold));
      expect(
        Theme.of(scaffold).scaffoldBackgroundColor,
        AppPalette.light.canvas,
      );
      expect(find.textContaining('contact support'), findsNothing);
      expect(
        find.textContaining('github.com/lodepav/OpenNutriTracker/issues'),
        findsOneWidget,
      );
    });
  });

  group('audit P3s', () {
    testWidgets('the footer is as tall as its button, not a seventh', (
      tester,
    ) async {
      _surface(tester, const Size(400, 2000));
      await _pumpOnboarding(tester);
      expect(
        tester.getSize(find.byType(HighlightButton)).height,
        lessThan(100),
      );
    });

    testWidgets('a page change leaves no orphan focus', (tester) async {
      _surface(tester, const Size(400, 1600));
      await _pumpOnboarding(tester);
      await tester.tap(find.byType(Checkbox).first);
      await tester.pump();
      await tester.tap(find.text(l10nEn.buttonStartLabel));
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus?.context, isNotNull);
    });

    testWidgets('a page change says the page', (tester) async {
      _surface(tester, const Size(400, 1600));
      await _pumpOnboarding(tester);
      await tester.tap(find.byType(Checkbox).first);
      await tester.pump();
      tester.takeAnnouncements();
      await tester.tap(find.text(l10nEn.buttonStartLabel));
      await tester.pumpAndSettle();
      expect(
        tester.takeAnnouncements().map((a) => a.message),
        contains(l10nEn.onboardingPageProgressSemantic(2, 7)),
      );
    });

    testWidgets('every accent swatch is in view without scrolling a row', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpOnPhone(
        tester,
        ChangeNotifierProvider<ThemeModeProvider>(
          create: (_) => ThemeModeProvider(appTheme: AppThemeEntity.system),
          child: OnboardingOtherOptionsPageBody(
            setPageContent: (_, _, _, _, _) {},
            initialTheme: AppThemeEntity.system,
            initialFoodSourceToggles: const {},
            initialDailyReminderEnabled: false,
            initialUseMaterialYou: false,
            initialAccentColor: null,
          ),
        ),
        textScale: 1,
      );
      final screen = tester.getRect(find.byType(Scaffold).first);
      for (final name in accentPresetNames) {
        final swatch = find.bySemanticsLabel(name);
        expect(swatch, findsOneWidget, reason: name);
        expect(tester.getRect(swatch).right, lessThanOrEqualTo(screen.right));
      }
      handle.dispose();
    });

    testWidgets('the busy spinner is named', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HighlightButton(
              buttonLabel: 'Start',
              onButtonPressed: () {},
              buttonActive: true,
              busy: true,
            ),
          ),
        ),
      );
      expect(find.bySemanticsLabel(RegExp('Saving')), findsOneWidget);
      handle.dispose();
    });
  });
}
