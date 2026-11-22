import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/features/onboarding/domain/entity/user_goal_selection_entity.dart';
import 'package:opennutritracker/features/onboarding/presentation/onboarding_intro_page_body.dart';
import 'package:opennutritracker/features/onboarding/presentation/widgets/onboarding_body_measurements_page_body.dart';
import 'package:opennutritracker/features/onboarding/presentation/widgets/onboarding_goal_page_body.dart';
import 'package:opennutritracker/fork/display/contrast.dart';
import 'package:opennutritracker/fork/goal/goal_planner.dart';
import 'package:opennutritracker/fork/goal/onboarding_goal.dart';
import 'package:opennutritracker/fork/phases/phases.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../helpers/test_l10n.dart';
import '../../helpers/ux_checks.dart';

/// The first-run critique of 2026-11-22, round 4.
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
  tearDown(() => OnboardingGoal.pending.value = null);

  Color canvas(bool dark) => (dark ? AppPalette.dark : AppPalette.light).canvas;

  group('body measurements', () {
    for (final dark in [false, true]) {
      testWidgets(
        'the chosen unit toggle reaches 3:1 (${dark ? 'dark' : 'light'})',
        (tester) async {
          await pumpOnPhone(
            tester,
            OnboardingBodyMeasurementsPageBody(
              setButtonContent: (_, _, _, _, _, _, _) {},
            ),
            textScale: 1,
            dark: dark,
          );
          final toggles = tester.widgetList<ToggleButtons>(
            find.byType(ToggleButtons),
          );
          expect(toggles, hasLength(2));
          for (final toggle in toggles) {
            // The unselected segment has no fill: it shows the canvas.
            expect(
              contrastRatio(toggle.fillColor!, canvas(dark)),
              greaterThanOrEqualTo(3),
            );
            expect(
              contrastRatio(toggle.selectedColor!, toggle.fillColor!),
              greaterThanOrEqualTo(4.5),
            );
          }
        },
      );
    }
  });

  group('intro', () {
    for (final dark in [false, true]) {
      testWidgets('Try Demo and Restore read at 4.5:1 before the policy '
          '(${dark ? 'dark' : 'light'})', (tester) async {
        await pumpOnPhone(
          tester,
          OnboardingIntroPageBody(setPageContent: (_, _) {}),
          textScale: 1,
          dark: dark,
        );
        Color label(String text) => tester
            .widget<RichText>(
              find.descendant(
                of: find.text(text),
                matching: find.byType(RichText),
              ),
            )
            .text
            .style!
            .color!;
        for (final text in [
          l10nEn.onboardingTryDemoLabel,
          'Restore a backup',
        ]) {
          expect(
            // Blended, as a faded label is drawn over the canvas.
            contrastRatio(
              Color.alphaBlend(label(text), canvas(dark)),
              canvas(dark),
            ),
            greaterThanOrEqualTo(4.5),
            reason: text,
          );
        }
        // The tap still says what is missing.
        await tester.tap(find.text(l10nEn.onboardingTryDemoLabel));
        await tester.pump();
        expect(
          find.text('Accept the privacy policy to try the demo'),
          findsOneWidget,
        );
      });
    }
  });

  group('goal page', () {
    testWidgets('a goal that clears the plan offers Undo', (tester) async {
      OnboardingGoal.pending.value = GoalDraft(
        kind: PhaseKind.cut,
        startKg: 79,
        targetKg: 72.6,
        start: DateTime(2026, 11, 21),
        paceKg: 0.5,
      ).toPlan();
      final plan = OnboardingGoal.pending.value;
      final picked = <UserGoalSelectionEntity?>[];
      await pumpOnPhone(
        tester,
        OnboardingGoalPageBody(
          setButtonContent: (_, goal) => picked.add(goal),
          initialGoal: UserGoalSelectionEntity.loseWeight,
        ),
        textScale: 1,
      );
      // The plan's own goal clears nothing and says nothing.
      await tester.tap(find.text(l10nEn.goalLoseWeight));
      await tester.pump();
      expect(find.text('Plan cleared'), findsNothing);

      await tester.tap(find.text(l10nEn.goalMaintainWeight));
      await tester.pumpAndSettle();
      expect(OnboardingGoal.pending.value, isNull);
      expect(find.text('Plan cleared'), findsOneWidget);

      await tester.tap(find.text('Undo'));
      await tester.pump();
      expect(OnboardingGoal.pending.value, same(plan));
      expect(picked.last, UserGoalSelectionEntity.loseWeight);
      expect(find.text('Your plan'), findsOneWidget);
    });
  });
}
