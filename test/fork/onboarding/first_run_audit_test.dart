import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/app_theme.dart';
import 'package:opennutritracker/features/onboarding/presentation/onboarding_intro_page_body.dart';
import 'package:opennutritracker/fork/backup/storage_rescue.dart';
import 'package:opennutritracker/fork/display/contrast.dart';
import 'package:opennutritracker/fork/onboarding/start_failure.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../helpers/test_l10n.dart';

// The first-run audit of 2026-11-22: a failed Start says so, the intro's
// policy link reads with a picked accent, and a backup that could not be
// restored at start is said once on the first page.

const _yellow = Color(0xFFFDD835);

Future<void> _pump(WidgetTester tester, Widget body, {Color? accent}) async {
  final p = accent == null
      ? AppPalette.light
      : AppPalette.light.withAccent(accent);
  tester.view
    ..physicalSize = const Size(1080, 2340)
    ..devicePixelRatio = 2.625;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(p),
      localizationsDelegates: const [
        S.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: S.supportedLocales,
      home: Scaffold(body: body),
    ),
  );
  await tester.pump();
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
  tearDown(() => StorageRescue.failedRestore = null);

  testWidgets('a Start that throws says it was not saved', (tester) async {
    await _pump(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () =>
              startOrSay(context, () async => throw StateError('disk full')),
          child: const Text('Start'),
        ),
      ),
    );
    await tester.tap(find.text('Start'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('Not saved. Try again.'), findsOneWidget);
  });

  testWidgets('the policy link reads at 4.5:1 with a yellow accent', (
    tester,
  ) async {
    await _pump(
      tester,
      OnboardingIntroPageBody(setPageContent: (_, _) {}),
      accent: _yellow,
    );
    final rich = tester.widget<RichText>(
      find.byWidgetPredicate(
        (w) =>
            w is RichText &&
            w.text.toPlainText().contains(l10nEn.privacyPolicyLabel),
      ),
    );
    TextSpan? link;
    rich.text.visitChildren((span) {
      if (span is TextSpan &&
          (span.text ?? '').contains(l10nEn.privacyPolicyLabel)) {
        link = span;
      }
      return true;
    });
    expect(
      contrastRatio(link!.style!.color!, AppPalette.light.canvas),
      greaterThanOrEqualTo(4.5),
    );
  });

  testWidgets('a backup that failed at start is said once, on the first '
      'page', (tester) async {
    StorageRescue.failedRestore = 'Your backup could not be restored.';
    await _pump(tester, OnboardingIntroPageBody(setPageContent: (_, _) {}));
    expect(find.text('Your backup could not be restored.'), findsOneWidget);
    expect(StorageRescue.failedRestore, isNull);

    // a later trip through onboarding, adding a profile
    await tester.pumpWidget(const SizedBox());
    await _pump(tester, OnboardingIntroPageBody(setPageContent: (_, _) {}));
    expect(find.text('Your backup could not be restored.'), findsNothing);
  });
}
