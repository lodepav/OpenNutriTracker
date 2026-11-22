import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:opennutritracker/core/domain/entity/profile_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_profiles_usecase.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/onboarding/presentation/onboarding_intro_page_body.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../helpers/test_l10n.dart';

class _FakeGetProfilesUsecase implements GetProfilesUsecase {
  _FakeGetProfilesUsecase(int count)
    : _profiles = [
        for (var i = 0; i < count; i++)
          ProfileEntity(
            id: 'p$i',
            name: 'P$i',
            createdAt: DateTime(2026, 1, 1),
            boxSuffix: i == 0 ? '' : '_p$i',
          ),
      ];

  final List<ProfileEntity> _profiles;

  @override
  List<ProfileEntity> getProfiles() => _profiles;

  @override
  String get activeProfileId => _profiles.last.id;

  @override
  ProfileEntity? getActiveProfile() => _profiles.last;
}

/// S430: the demo wipe clears the shared recipe, custom food and activity
/// template boxes, so Try Demo is offered only while there is one profile.
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

  tearDown(() => GetIt.instance.reset());

  Finder tryDemo() => find.byWidgetPredicate(
    (w) => w is Semantics && w.properties.identifier == 'onboarding-try-demo',
  );

  Future<void> pump(WidgetTester tester, int profiles) async {
    locator.registerSingleton<GetProfilesUsecase>(
      _FakeGetProfilesUsecase(profiles),
    );
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [S.delegate],
        supportedLocales: S.supportedLocales,
        home: Scaffold(body: OnboardingIntroPageBody(setPageContent: (_, _) {})),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('one profile: Try Demo shows', (tester) async {
    await pump(tester, 1);
    expect(tryDemo(), findsOneWidget);
    expect(
      find.text(
        'Skip setup and explore the app with sample data. Accept the privacy '
        'policy first.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('with the policy accepted, the demo caption stops asking for '
      'it', (tester) async {
    await pump(tester, 1);
    await tester.tap(find.bySemanticsIdentifier('onboarding-checkbox-privacy'));
    await tester.pumpAndSettle();
    expect(
      find.text('Skip setup and explore the app with sample data.'),
      findsOneWidget,
    );
  });

  testWidgets('two profiles: Try Demo and its captions are gone', (
    tester,
  ) async {
    await pump(tester, 2);
    expect(tryDemo(), findsNothing);
    expect(find.text(l10nEn.onboardingTryDemoLabel), findsNothing);
    expect(find.textContaining('Skip setup'), findsNothing);
    expect(find.text(l10nEn.onboardingTryDemoDisclaimer), findsNothing);
    expect(find.text('Restore a backup'), findsOneWidget);
  });
}
