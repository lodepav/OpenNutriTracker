import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/app_theme_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_gender_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_pal_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_weight_goal_entity.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/utils/calc/calorie_goal_calc.dart';
import 'package:opennutritracker/core/utils/calc/macro_calc.dart';
import 'package:opennutritracker/core/utils/theme_mode_provider.dart';
import 'package:opennutritracker/features/onboarding/presentation/onboarding_intro_page_body.dart';
import 'package:opennutritracker/features/onboarding/presentation/widgets/highlight_button.dart';
import 'package:opennutritracker/features/onboarding/presentation/widgets/onboarding_activity_page_body.dart';
import 'package:opennutritracker/features/onboarding/presentation/widgets/onboarding_other_options_page_body.dart';
import 'package:opennutritracker/fork/onboarding/onboarding_back.dart';
import 'package:opennutritracker/fork/onboarding/overview_grams.dart';
import 'package:opennutritracker/fork/screens/onboarding/onboarding_about_you_page_body.dart';
import 'package:opennutritracker/fork/settings/accent_view.dart';
import 'package:opennutritracker/fork/widget/macro_widget.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../../helpers/test_l10n.dart';
import '../../helpers/ux_checks.dart';

double _contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

/// The first-run critique of 2026-11-21 (G1, round 1).
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

  group('footer button', () {
    for (final dark in [false, true]) {
      testWidgets('a ready step reads its label (${dark ? 'dark' : 'light'})', (
        tester,
      ) async {
        await pumpOnPhone(
          tester,
          Center(
            child: HighlightButton(
              buttonLabel: 'Start',
              onButtonPressed: () {},
              buttonActive: true,
            ),
          ),
          textScale: 1,
          dark: dark,
        );
        final colors = Theme.of(tester.element(find.text('Start'))).colorScheme;
        final label = tester.renderObject<RenderParagraph>(
          find.descendant(
            of: find.text('Start'),
            matching: find.byType(RichText),
          ),
        );
        expect(label.text.style?.color, colors.onPrimaryContainer);
        await expectLater(tester, meetsGuideline(textContrastGuideline));
      });

      testWidgets('a blocked step still reads (${dark ? 'dark' : 'light'})', (
        tester,
      ) async {
        await pumpOnPhone(
          tester,
          Center(
            child: HighlightButton(
              buttonLabel: 'Next',
              onButtonPressed: () {},
              buttonActive: false,
              inactiveMessage: 'Pick one',
            ),
          ),
          textScale: 1,
          dark: dark,
        );
        await expectLater(tester, meetsGuideline(textContrastGuideline));
      });
    }
  });

  group('system Back', () {
    Future<List<String>> pumpAt(
      WidgetTester tester,
      int page, {
      bool addingProfile = false,
    }) async {
      final calls = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => OnboardingBack(
                    page: page,
                    onPrevious: () => calls.add('previous'),
                    onFirstPage: addingProfile
                        ? () => calls.add('cancel')
                        : null,
                    child: const Text('onboarding'),
                  ),
                ),
              ),
              child: const Text('home'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('home'));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      return calls;
    }

    testWidgets('past the first page it steps back and stays', (tester) async {
      expect(await pumpAt(tester, 3), ['previous']);
      expect(find.text('onboarding'), findsOneWidget);
    });

    testWidgets('on the first page it leaves, as before', (tester) async {
      expect(await pumpAt(tester, 0), isEmpty);
      expect(find.text('onboarding'), findsNothing);
    });

    testWidgets('adding a profile, the first page cancels the add', (
      tester,
    ) async {
      expect(await pumpAt(tester, 0, addingProfile: true), ['cancel']);
    });

    testWidgets('adding a profile, a later page only steps back', (
      tester,
    ) async {
      expect(await pumpAt(tester, 4, addingProfile: true), ['previous']);
      expect(find.text('onboarding'), findsOneWidget);
    });
  });

  group('consent rows', () {
    Future<void> pumpIntro(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [S.delegate],
          supportedLocales: S.supportedLocales,
          home: Scaffold(
            body: OnboardingIntroPageBody(setPageContent: (_, _) {}),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('each checkbox carries its sentence', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpIntro(tester);
      final policy = tester.getSemantics(
        find.bySemanticsIdentifier('onboarding-checkbox-privacy'),
      );
      expect(
        policy,
        isSemantics(
          label: l10nEn.readLabel,
          hasCheckedState: true,
          isChecked: false,
          hasTapAction: true,
        ),
      );
      // The link inside the row stays reachable as the row's action.
      expect(
        policy.getSemanticsData().customSemanticsActionIds!.map(
          (id) => CustomSemanticsAction.getAction(id)!.label,
        ),
        ['Open privacy policy'],
      );
      expect(
        tester.getSemantics(
          find.bySemanticsIdentifier('onboarding-checkbox-data'),
        ),
        isSemantics(
          label: l10nEn.dataCollectionLabel,
          hasCheckedState: true,
          isChecked: false,
          hasTapAction: true,
        ),
      );
      handle.dispose();
    });
  });

  group('activity radios', () {
    for (final dark in [false, true]) {
      testWidgets('an empty ring reaches 3:1 (${dark ? 'dark' : 'light'})', (
        tester,
      ) async {
        await pumpOnPhone(
          tester,
          OnboardingActivityPageBody(setButtonContent: (_, _) {}),
          textScale: 1,
          dark: dark,
        );
        final ring = tester.widget<Icon>(
          find.byIcon(Icons.radio_button_unchecked).first,
        );
        final card = (dark ? AppPalette.dark : AppPalette.light).surface;
        expect(_contrast(ring.color!, card), greaterThanOrEqualTo(3));
      });
    }
  });

  group('other options', () {
    Future<void> pumpOptions(WidgetTester tester) => pumpOnPhone(
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
    );

    testWidgets('each accent swatch is named, 48 dp and not cut top or '
        'bottom', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpOptions(tester);
      tester.view.physicalSize = const Size(1080, 7020);
      await tester.pumpAndSettle();
      final row = find.byWidgetPredicate(
        (w) => w is Scrollable && w.axisDirection == AxisDirection.right,
      );
      for (final name in accentPresetNames) {
        final swatch = find.bySemanticsLabel(name);
        // A lazy scrolling row: later swatches are built once scrolled to.
        await tester.scrollUntilVisible(swatch, 100, scrollable: row);
        expect(swatch, findsOneWidget, reason: name);
        final rect = tester.getRect(swatch);
        expect(rect.width, greaterThanOrEqualTo(48), reason: name);
        expect(rect.height, greaterThanOrEqualTo(48), reason: name);
        final rowRect = tester.getRect(row);
        expect(rect.top, greaterThanOrEqualTo(rowRect.top), reason: name);
        expect(rect.bottom, lessThanOrEqualTo(rowRect.bottom), reason: name);
        expect(
          tester.getSemantics(swatch),
          isSemantics(isButton: true, hasSelectedState: true),
        );
      }
      handle.dispose();
    });

    testWidgets('the theme choices stay whole words at 200%', (tester) async {
      await pumpOptions(tester);
      for (final label in [
        l10nEn.settingsThemeSystemDefaultLabel,
        l10nEn.settingsThemeLightLabel,
        l10nEn.settingsThemeDarkLabel,
      ]) {
        final paragraph = tester.renderObject<RenderParagraph>(
          find.descendant(
            of: find.text(label),
            matching: find.byType(RichText),
          ),
        );
        // A word wider than its box is split mid-word.
        expect(
          paragraph.getMinIntrinsicWidth(double.infinity),
          lessThanOrEqualTo(paragraph.size.width + 0.5),
          reason: label,
        );
      }
    });
  });

  testWidgets('the sources button on the about-you page is 48 dp', (
    tester,
  ) async {
    await pumpOnPhone(
      tester,
      OnboardingAboutYouPageBody(setPageContent: (_, _, _, _) {}),
      textScale: 1,
    );
    // The button's own box, padding included: what a finger can hit.
    final size = tester.getSize(
      find.ancestor(
        of: find.byTooltip(l10nEn.sourcesIconTooltip),
        matching: find.byType(IconButton),
      ),
    );
    expect(size.width, greaterThanOrEqualTo(48));
    expect(size.height, greaterThanOrEqualTo(48));
  });

  test('the overview shows the grams Home shows', () {
    var roundedUp = 0;
    for (var weight = 50.0; weight <= 100; weight += 0.7) {
      for (final goal in UserWeightGoalEntity.values) {
        final user = UserEntity(
          birthday: DateTime(1992, 5, 20),
          heightCM: 165,
          weightKG: weight,
          gender: UserGenderEntity.female,
          goal: goal,
          pal: UserPALEntity.lowActive,
          targetWeightKg: weight - 5,
        );
        // Onboarding's bloc: the formula with nothing logged.
        final kcal = CalorieGoalCalc.getTotalKcalGoal(user, 0);
        final carbs = MacroCalc.getTotalCarbsGoal(kcal);
        final fat = MacroCalc.getTotalFatsGoal(kcal);
        final protein = MacroCalc.getTotalProteinsGoal(kcal);
        // Home's kcal goal, no activity and no adjustment yet, then its
        // rounding.
        final homeKcal = CalorieGoalCalc.getTotalKcalGoal(
          user,
          0,
          kcalUserAdjustment: 0,
          caloriesTaperEnabled: user.caloriesTaperEnabled,
        );
        final home = MacroWidgetFigures.fromHome(
          logicalDay: DateTime(2026, 11, 21),
          offsetMinutes: 0,
          kilojoules: false,
          kcal: 0,
          kcalGoal: homeKcal,
          protein: 0,
          proteinGoal: MacroCalc.getTotalProteinsGoal(homeKcal),
          carbs: 0,
          carbsGoal: MacroCalc.getTotalCarbsGoal(homeKcal),
          fat: 0,
          fatGoal: MacroCalc.getTotalFatsGoal(homeKcal),
        );
        expect(overviewGrams(carbs), '${home.carbsGoal}');
        expect(overviewGrams(fat), '${home.fatGoal}');
        expect(overviewGrams(protein), '${home.proteinGoal}');
        if (carbs - carbs.floor() >= 0.5) roundedUp++;
      }
    }
    // The case the critique saw: 322.8 g, which truncating showed as 322.
    expect(roundedUp, greaterThan(0));
    expect(overviewGrams(322.8), '323');
    expect(overviewGrams(null), '?');
  });
}
