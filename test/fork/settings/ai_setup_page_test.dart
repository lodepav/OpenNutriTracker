// AI setup after the G6 rounds of 2026-11-22: every provider's paragraph
// names the features the app shows (S581, G6-18), the setup is a
// full-screen page rather than a dialog (S582, G6-27), a passed check is
// drawn in the readable accent and a server's model id gets two lines
// (S583, audit G6 a3).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:opennutritracker/core/utils/ai_credential_storage.dart';
import 'package:opennutritracker/core/utils/ai_model_list_api.dart';
import 'package:opennutritracker/features/add_meal/domain/usecase/probe_ai_endpoint_usecase.dart';
import 'package:opennutritracker/features/add_meal/domain/usecase/run_ai_endpoint_probe_usecase.dart';
import 'package:opennutritracker/features/settings/presentation/widgets/ai_assist_dialog.dart';
import 'package:opennutritracker/features/settings/presentation/widgets/ai_consent_screen.dart';
import 'package:opennutritracker/fork/ai/setup_page.dart';
import 'package:opennutritracker/fork/display/contrast.dart';
import 'package:opennutritracker/generated/l10n.dart';

import '../../helpers/test_l10n.dart';
import '../../helpers/ux_checks.dart';

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

class _PassingProber implements AiEndpointProber {
  @override
  Future<AiEndpointProbe> probe(
    AiSelection selection, {
    String? localeCode,
    Future<bool> Function()? stillWanted,
  }) async => const AiEndpointProbe(
    text: AiCapability.passed,
    photo: AiCapability.passed,
    checked: true,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late AiCredentialStorage storage;

  setUp(() {
    storage = AiCredentialStorage(_MemoryStorage());
  });

  Widget app(Widget home) => MaterialApp(
    localizationsDelegates: const [
      S.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: S.supportedLocales,
    home: home,
  );

  const named = 'the text you type in Log with AI and Photo log';

  for (final provider in [
    AiProvider.anthropic,
    AiProvider.openrouter,
    AiProvider.openai,
  ]) {
    testWidgets('the ${provider.name} paragraph names Log with AI and Photo '
        'log', (tester) async {
      await tester.pumpWidget(
        app(Scaffold(body: AiAssistDialog(storage: storage))),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.bySemanticsIdentifier(AiAssistDialog.providerIdentifier(provider)),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining(named), findsOneWidget);
      expect(find.textContaining('multi-item'), findsNothing);
      // Only the chosen provider's paragraph, which upstream's findsNothing
      // lines on the raw strings no longer show
      final paragraphs = {
        AiProvider.anthropic: l10nEn.aiAssistDisclosureAnthropic,
        AiProvider.openrouter: l10nEn.aiAssistDisclosureOpenRouter,
        AiProvider.openai: l10nEn.aiAssistDisclosureOpenAI,
      };
      for (final MapEntry(key: other, value: text) in paragraphs.entries) {
        expect(
          find.textContaining(forkFeatureNames(text)),
          other == provider ? findsOneWidget : findsNothing,
        );
      }
    });
  }

  testWidgets('the consent screen names them for a server the user runs', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        const AiConsentScreen(
          provider: AiProvider.ownServer,
          typedEndpoint: 'https://ollama.example.com',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining(named), findsOneWidget);
    expect(find.textContaining('multi-item'), findsNothing);
  });

  testWidgets("the page's close button leaves it as Cancel does", (
    tester,
  ) async {
    late Future<bool> changed;
    await tester.pumpWidget(
      app(
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => changed = AiAssistDialog.show(context, storage),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(CloseButton));
    await tester.pumpAndSettle();
    expect(find.byType(AiAssistDialog), findsNothing);
    expect(await changed, isFalse);
  });

  testWidgets('AI setup opens as a full-screen page, and back leaves it', (
    tester,
  ) async {
    late Future<bool> changed;
    await tester.pumpWidget(
      app(
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => changed = AiAssistDialog.show(context, storage),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    final route = ModalRoute.of(tester.element(find.byType(AiAssistDialog)));
    expect(route, isA<PageRoute<bool>>());
    expect((route! as PageRoute<bool>).fullscreenDialog, isTrue);
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.text(l10nEn.settingsAiAssistLabel),
      ),
      findsOneWidget,
    );

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(AiAssistDialog), findsNothing);
    expect(await changed, isFalse);
  });

  Future<void> ownServerSaved() => storage.writeOwnServerConfiguration(
    endpoint: 'http://192.168.1.5:11434',
    model: 'gemma3:4b',
    provider: AiProvider.ownServer,
  );

  testWidgets('a passed check is drawn in the accent as text, not the raw '
      'one', (tester) async {
    await storage.setTermsAccepted(true);
    await ownServerSaved();
    await storage.setActiveProvider(AiProvider.ownServer);
    await storage.writeProbe(
      const AiEndpointProbe(
        text: AiCapability.passed,
        photo: AiCapability.passed,
        checked: true,
      ),
      provider: AiProvider.ownServer,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFFFFEB3B),
            primary: const Color(0xFFFFEB3B),
          ),
        ),
        localizationsDelegates: const [
          S.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: S.supportedLocales,
        home: Scaffold(
          body: AiAssistDialog(
            storage: storage,
            probeRunner: AiEndpointProbeRunner(storage, _PassingProber()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final icon = find
        .byIcon(Icons.check_circle_outline_rounded, skipOffstage: false)
        .first;
    final context = tester.element(icon);
    expect(
      tester.widget<Icon>(icon).color,
      textAccent(context),
    );
    expect(
      tester.widget<Icon>(icon).color,
      isNot(Theme.of(context).colorScheme.primary),
    );
  });

  testWidgets("a server's model ids get a second line", (tester) async {
    final api = AiModelListApi(
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'object': 'list',
            'data': [
              {'id': 'qwen3:8b', 'object': 'model'},
            ],
          }),
          200,
        ),
      ),
    );
    await tester.pumpWidget(
      app(Scaffold(body: AiAssistDialog(storage: storage, modelList: api))),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.bySemanticsIdentifier(
        AiAssistDialog.providerIdentifier(AiProvider.ownServer),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.bySemanticsIdentifier('ai-assist-endpoint-field'),
      'http://192.168.1.5:11434',
    );
    await tester.pumpAndSettle();
    final load = find.bySemanticsIdentifier('ai-assist-load-models');
    await tester.ensureVisible(load);
    await tester.pumpAndSettle();
    await tester.tap(load);
    await tester.pumpAndSettle();

    final picker = find.byType(DropdownButton<String>);
    expect(tester.widget<DropdownButton<String>>(picker).itemHeight, isNull);
    await tester.ensureVisible(picker);
    await tester.pumpAndSettle();
    await tester.tap(picker);
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(find.text('qwen3:8b').last).maxLines, 2);
  });

  testWidgets('the AI setup page passes the screen checks', (tester) async {
    await checkScreen(
      tester,
      AiSetupPage(
        title: const Text('Set up AI'),
        content: const Text('Pick a provider and paste its key.'),
        actions: [
          TextButton(onPressed: () {}, child: const Text('Cancel')),
          FilledButton(onPressed: () {}, child: const Text('Save')),
        ],
      ),
    );
  });
}
