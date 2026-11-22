// The AI dialog and its consent screen use the words the user acted on
// (the 2026-11-21 G6 critique): a key for the Google Gemini row, a title
// naming the provider when AI is already on, the features' own names,
// sentence case, a declined key that is said, and Close when nothing changed.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/utils/ai_credential_storage.dart';
import 'package:opennutritracker/features/settings/presentation/widgets/ai_assist_dialog.dart';
import 'package:opennutritracker/features/settings/presentation/widgets/ai_consent_screen.dart';
import 'package:opennutritracker/generated/l10n.dart';

import '../../helpers/test_l10n.dart';

class _MemoryStorage implements FlutterSecureStorage {
  final store = <String, String>{};

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => store[key];

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      store.remove(key);
    } else {
      store[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => store.remove(key);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late AiCredentialStorage storage;

  setUp(() {
    storage = AiCredentialStorage(_MemoryStorage());
  });

  Widget app() => MaterialApp(
    localizationsDelegates: const [
      S.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: S.supportedLocales,
    home: Scaffold(body: AiAssistDialog(storage: storage)),
  );

  Finder keyField() => find.bySemanticsIdentifier('ai-assist-key-field');
  Finder ok() => find.bySemanticsIdentifier('ai-assist-save-key');

  Future<void> anthropicOn() async {
    await storage.setTermsAccepted(true);
    await storage.setActiveProvider(AiProvider.anthropic);
    await storage.writeApiKey('sk-ant', provider: AiProvider.anthropic);
    expect(await storage.isEnabled(), isTrue);
  }

  Future<void> typeGeminiKeyAndSave(WidgetTester tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsIdentifier('ai-assist-provider-gemini'));
    await tester.pumpAndSettle();
    await tester.enterText(keyField(), 'AIza-key');
    await tester.ensureVisible(ok());
    await tester.tap(ok());
    await tester.pumpAndSettle();
    expect(find.byType(AiConsentScreen), findsOneWidget);
  }

  testWidgets('a Gemini key with AI on asks "Send meals to Google?" in key '
      'words, naming the features', (tester) async {
    await anthropicOn();
    await typeGeminiKeyAndSave(tester);

    expect(find.text('Send meals to Google?'), findsOneWidget);
    expect(find.text(l10nEn.aiConsentTitle), findsNothing);
    expect(
      find.textContaining(
        'With a key saved, the text you type in Log with AI and Photo log, '
        "and any photo you choose to read there, is sent to Google's Gemini "
        'API',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('With an address saved'), findsNothing);
    expect(find.textContaining('multi-item'), findsNothing);
    expect(find.text('I understand', skipOffstage: false), findsOneWidget);
    expect(find.text('I UNDERSTAND', skipOffstage: false), findsNothing);
  });

  testWidgets('the dialog names the features on the Gemini row as well', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsIdentifier('ai-assist-provider-gemini'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('the text you type in Log with AI and Photo log'),
      findsOneWidget,
    );
  });

  testWidgets('with AI off, the title stays "Before you turn this on"', (
    tester,
  ) async {
    await typeGeminiKeyAndSave(tester);

    expect(find.text(l10nEn.aiConsentTitle), findsOneWidget);
  });

  testWidgets('declining says the key was not saved, until the next edit', (
    tester,
  ) async {
    await typeGeminiKeyAndSave(tester);
    final decline = find.bySemanticsIdentifier('ai-consent-decline');
    await tester.scrollUntilVisible(decline, 200);
    await tester.tap(decline);
    await tester.pumpAndSettle();

    expect(find.byType(AiConsentScreen), findsNothing);
    expect(find.text('Key not saved'), findsOneWidget);
    expect(
      await storage.readApiKey(provider: AiProvider.ownServer),
      isNull,
    );

    await tester.enterText(keyField(), 'A');
    await tester.pump();
    expect(find.text('Key not saved'), findsNothing);
  });

  testWidgets('with a key saved and nothing changed, the way out is Close', (
    tester,
  ) async {
    await anthropicOn();
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(ok(), findsNothing);
    expect(find.text('Close'), findsOneWidget);
    expect(find.text(l10nEn.dialogCancelLabel), findsNothing);

    // Pausing is a change that Cancel could undo, so OK and Cancel return.
    final toggle = find.bySemanticsIdentifier('ai-assist-enabled');
    await tester.ensureVisible(toggle);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    expect(ok(), findsOneWidget);
    expect(find.text(l10nEn.dialogCancelLabel), findsOneWidget);
    expect(find.text('Close'), findsNothing);
  });
}
