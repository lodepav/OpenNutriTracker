// A hosted provider's typed key is asked about before it is saved (S357),
// and Remove can be undone (S358): the round-2 G6 critique.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:opennutritracker/core/utils/ai_credential_storage.dart';
import 'package:opennutritracker/features/settings/presentation/widgets/ai_assist_dialog.dart';
import 'package:opennutritracker/features/settings/presentation/widgets/ai_consent_screen.dart';
import 'package:opennutritracker/fork/ai/hosted_key_check.dart';
import 'package:opennutritracker/generated/l10n.dart';

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

const _refusal =
    '{"type":"error","error":{"type":"authentication_error",'
    '"message":"invalid x-api-key"}}';

void main() {
  group('checkHostedKey', () {
    test('asks each provider a route that needs the key', () async {
      final asked = <http.BaseRequest>[];
      final client = MockClient((request) async {
        asked.add(request);
        return http.Response('{}', 200);
      });
      for (final provider in [
        AiProvider.anthropic,
        AiProvider.openai,
        AiProvider.openrouter,
      ]) {
        final result = await checkHostedKey(client, provider, 'k1');
        expect(result.verdict, HostedKeyVerdict.checked, reason: '$provider');
      }
      expect(asked.map((r) => '${r.method} ${r.url}'), [
        'GET https://api.anthropic.com/v1/models',
        'GET https://api.openai.com/v1/models',
        'GET https://openrouter.ai/api/v1/key',
      ]);
      expect(asked[0].headers['x-api-key'], 'k1');
      expect(asked[0].headers['anthropic-version'], '2023-06-01');
      expect(asked[1].headers['authorization'], 'Bearer k1');
      expect(asked[2].headers['authorization'], 'Bearer k1');
    });

    test("a 401 is refused, in the provider's words", () async {
      final result = await checkHostedKey(
        MockClient((_) async => http.Response(_refusal, 401)),
        AiProvider.anthropic,
        'bad',
      );
      expect(result.verdict, HostedKeyVerdict.refused);
      expect(result.message, 'invalid x-api-key');
      final bare = await checkHostedKey(
        MockClient((_) async => http.Response('nope', 401)),
        AiProvider.openai,
        'bad',
      );
      expect(bare.message, 'The provider refused this key');
    });

    test('no answer is offline, any other answer unchecked', () async {
      final offline = await checkHostedKey(
        MockClient((_) async => throw const SocketException('no route')),
        AiProvider.openrouter,
        'k',
      );
      expect(offline.verdict, HostedKeyVerdict.offline);

      final slow = await checkHostedKey(
        MockClient((_) => Completer<http.Response>().future),
        AiProvider.openrouter,
        'k',
        timeout: const Duration(milliseconds: 10),
      );
      expect(slow.verdict, HostedKeyVerdict.offline);

      for (final code in [403, 429, 500]) {
        final result = await checkHostedKey(
          MockClient((_) async => http.Response('', code)),
          AiProvider.openai,
          'k',
        );
        expect(result.verdict, HostedKeyVerdict.unchecked);
      }
    });
  });

  group('the dialog', () {
    late AiCredentialStorage storage;
    late List<http.Request> asked;
    late Future<http.Response> Function(http.Request) answer;

    setUp(() {
      storage = AiCredentialStorage(_MemoryStorage());
      asked = [];
      answer = (_) async => http.Response('{}', 200);
    });

    Widget app() => MaterialApp(
      localizationsDelegates: const [
        S.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: S.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => AiAssistDialog.show(
              context,
              storage,
              forkKeyCheckClient: MockClient((request) {
                asked.add(request);
                return answer(request);
              }),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );

    Finder keyField() => find.bySemanticsIdentifier('ai-assist-key-field');
    Finder ok() => find.bySemanticsIdentifier('ai-assist-save-key');

    Future<void> typeOpenRouterKey(WidgetTester tester, String key) async {
      await storage.setActiveProvider(AiProvider.openrouter);
      await tester.pumpWidget(app());
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.enterText(keyField(), key);
      await tester.ensureVisible(ok());
      await tester.tap(ok());
      await tester.pumpAndSettle();
    }

    testWidgets('a refused key stays in the dialog with the reason', (
      tester,
    ) async {
      await storage.setTermsAccepted(true);
      answer = (_) async => http.Response(_refusal, 401);
      await typeOpenRouterKey(tester, 'sk-or-typo');

      expect(asked.single.url.path, '/api/v1/key');
      expect(find.byType(AiAssistDialog), findsOneWidget);
      expect(find.text('invalid x-api-key'), findsOneWidget);
      expect(await storage.readApiKey(provider: AiProvider.openrouter), isNull);
      expect(await storage.isEnabled(), isFalse);

      // The next edit clears the reason.
      await tester.enterText(keyField(), 'sk-or-right');
      await tester.pump();
      expect(find.text('invalid x-api-key'), findsNothing);
    });

    testWidgets('an agreement first given on a refused OK is taken back', (
      tester,
    ) async {
      answer = (_) async => http.Response(_refusal, 401);
      await typeOpenRouterKey(tester, 'sk-or-typo');
      expect(find.byType(AiConsentScreen), findsOneWidget);
      final accept = find.bySemanticsIdentifier('ai-consent-agree');
      await tester.scrollUntilVisible(accept, 200);
      await tester.tap(accept);
      await tester.pumpAndSettle();

      expect(asked, hasLength(1));
      expect(find.text('invalid x-api-key'), findsOneWidget);
      expect(await storage.hasAcceptedTerms(), isFalse);
    });

    testWidgets('an agreement given for a check left by Cancel is taken back',
        (tester) async {
      final reply = Completer<http.Response>();
      answer = (_) => reply.future;
      await storage.setActiveProvider(AiProvider.openrouter);
      await tester.pumpWidget(app());
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.enterText(keyField(), 'sk-or-key');
      await tester.ensureVisible(ok());
      await tester.tap(ok());
      await tester.pumpAndSettle();
      final agree = find.bySemanticsIdentifier('ai-consent-agree');
      await tester.scrollUntilVisible(agree, 200);
      await tester.tap(agree);
      await tester.pump();
      await tester.pump();
      expect(find.text('Checking key…'), findsOneWidget);
      expect(await storage.hasAcceptedTerms(), isTrue);

      await tester.tap(find.bySemanticsIdentifier('ai-assist-cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(AiAssistDialog), findsNothing);
      reply.complete(http.Response('{}', 200));
      await tester.pumpAndSettle();
      expect(await storage.hasAcceptedTerms(), isFalse);
      expect(await storage.readApiKey(provider: AiProvider.openrouter), isNull);
    });

    testWidgets('an accepted key is saved and said to be checked', (
      tester,
    ) async {
      await storage.setTermsAccepted(true);
      await typeOpenRouterKey(tester, 'sk-or-good');

      expect(find.byType(AiAssistDialog), findsNothing);
      expect(find.text('Key checked'), findsOneWidget);
      expect(
        await storage.readApiKey(provider: AiProvider.openrouter),
        'sk-or-good',
      );
      expect(await storage.isEnabled(), isTrue);
    });

    testWidgets('offline, the key is saved and said to be unchecked', (
      tester,
    ) async {
      await storage.setTermsAccepted(true);
      answer = (_) async => throw const SocketException('offline');
      await typeOpenRouterKey(tester, 'sk-or-good');

      expect(find.byType(AiAssistDialog), findsNothing);
      expect(find.text('Saved, not checked (offline)'), findsOneWidget);
      expect(
        await storage.readApiKey(provider: AiProvider.openrouter),
        'sk-or-good',
      );
    });

    testWidgets('Remove can be undone, and a paused AI stays paused', (
      tester,
    ) async {
      await storage.setTermsAccepted(true);
      await storage.setActiveProvider(AiProvider.anthropic);
      await storage.writeApiKey('sk-ant', provider: AiProvider.anthropic);
      await storage.setEnabled(false);
      await tester.pumpWidget(app());
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final remove = find.bySemanticsIdentifier('ai-assist-remove-key');
      await tester.ensureVisible(remove);
      await tester.tap(remove);
      await tester.pumpAndSettle();
      expect(await storage.readApiKey(provider: AiProvider.anthropic), isNull);
      expect(await storage.hasAcceptedTerms(), isFalse);
      expect(find.text('Key removed'), findsOneWidget);
      // Typed after Remove, then dropped by Undo rather than saved over it.
      await tester.enterText(keyField(), 'half-typed');
      await tester.pump();

      final undo = find.bySemanticsIdentifier('ai-assist-undo-remove');
      await tester.ensureVisible(undo);
      await tester.pumpAndSettle();
      await tester.tap(undo);
      await tester.pumpAndSettle();
      expect(
        await storage.readApiKey(provider: AiProvider.anthropic),
        'sk-ant',
      );
      expect(await storage.hasAcceptedTerms(), isTrue);
      expect(await storage.isEnabled(), isFalse);
      expect(find.text('Key removed'), findsNothing);

      final okAfterUndo = ok();
      await tester.ensureVisible(okAfterUndo);
      await tester.tap(okAfterUndo);
      await tester.pumpAndSettle();
      expect(
        await storage.readApiKey(provider: AiProvider.anthropic),
        'sk-ant',
      );
      expect(asked, isEmpty);
    });
  });
}
