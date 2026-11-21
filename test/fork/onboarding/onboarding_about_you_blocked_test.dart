import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/fork/screens/onboarding/onboarding_about_you_page_body.dart';
import 'package:opennutritracker/fork/screens/onboarding/onboarding_limits.dart';

import '../../helpers/test_l10n.dart';
import '../../helpers/ux_checks.dart';

/// The first-run critique of 2026-11-21, round 3: About you's blocked Next
/// names the one thing missing.
void main() {
  test('the blocked message names the one wrong field', () {
    const wrongDate = 'Enter a birthday between 1898 and 2012';
    expect(
      aboutYouBlockedMessage(
        genderOk: true,
        birthdayOk: false,
        birthdayError: wrongDate,
      ),
      wrongDate,
    );
    expect(
      aboutYouBlockedMessage(genderOk: true, birthdayOk: false),
      'Enter your birthday to continue',
    );
    expect(
      aboutYouBlockedMessage(genderOk: false, birthdayOk: true),
      'Select your gender to continue',
    );
    // Both wrong: upstream's message, which names both.
    expect(
      aboutYouBlockedMessage(
        genderOk: false,
        birthdayOk: false,
        birthdayError: wrongDate,
      ),
      isNull,
    );
    expect(aboutYouBlockedMessage(genderOk: true, birthdayOk: true), isNull);
  });

  testWidgets('a birthday in the future with a gender given names the date', (
    tester,
  ) async {
    final message = ValueNotifier<String?>(null);
    addTearDown(message.dispose);
    await pumpOnPhone(
      tester,
      OnboardingAboutYouPageBody(
        setPageContent: (_, _, _, _) {},
        blockedMessage: message,
      ),
      textScale: 1,
    );
    await tester.tap(find.text(l10nEn.genderMaleLabel));
    await tester.pump();
    expect(message.value, 'Enter your birthday to continue');
    await tester.enterText(find.byType(TextFormField), '06012030');
    await tester.pump();
    expect(message.value, startsWith('Enter a birthday between'));
    await tester.enterText(find.byType(TextFormField), '06011990');
    await tester.pump();
    expect(message.value, isNull);
  });
}
