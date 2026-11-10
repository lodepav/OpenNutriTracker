// The dialog's radios still use the deprecated groupValue form.
// ignore_for_file: deprecated_member_use

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:opennutritracker/core/presentation/ai_assist_summary.dart';
import 'package:opennutritracker/core/utils/ai_credential_storage.dart';
import 'package:opennutritracker/core/utils/ai_model_list_api.dart';
import 'package:opennutritracker/features/add_meal/domain/meal_items_api.dart';
import 'package:opennutritracker/features/add_meal/domain/meal_photo_interpreter.dart';
import 'package:opennutritracker/features/add_meal/domain/usecase/probe_ai_endpoint_usecase.dart';
import 'package:opennutritracker/features/add_meal/domain/usecase/run_ai_endpoint_probe_usecase.dart';
import 'package:opennutritracker/features/settings/presentation/widgets/ai_assist_dialog.dart';
import 'package:opennutritracker/features/settings/presentation/widgets/ai_consent_screen.dart';
import 'package:opennutritracker/fork/ai/gemini_preset.dart';
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

/// Google's side of the setup check: every request answered with a meal.
class _Google extends http.BaseClient {
  final requests = <http.Request>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request as http.Request);
    final body = jsonEncode({
      'choices': [
        {
          'finish_reason': 'tool_calls',
          'message': {
            'tool_calls': [
              {
                'function': {
                  'name': mealItemsToolName,
                  'arguments': '{"items":[{"query":"bread"}]}',
                },
              },
            ],
          },
        },
      ],
    });
    return http.StreamedResponse(
      Stream.value(utf8.encode(body)),
      200,
      request: request,
    );
  }
}

const _ollama = 'http://192.168.1.5:11434/v1/chat/completions';
const _host = 'generativelanguage.googleapis.com';

void main() {
  late _MemoryStorage backing;
  late AiCredentialStorage storage;
  late _Google google;
  late AiEndpointProbeRunner runner;
  late List<Uri> modelListRequests;
  late AiModelListApi modelList;

  setUp(() async {
    backing = _MemoryStorage();
    storage = AiCredentialStorage(backing);
    google = _Google();
    runner = AiEndpointProbeRunner(
      storage,
      AiEndpointProber(
        google,
        sampleImage: (format) async => MealPhoto(
          bytes: Uint8List.fromList([1, 2, 3]),
          mediaType: format.mediaType,
        ),
      ),
    );
    modelListRequests = [];
    modelList = AiModelListApi(
      client: MockClient((request) async {
        modelListRequests.add(request.url);
        return http.Response('{"object":"list","data":[]}', 200);
      }),
    );
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
      body: AiAssistDialog(
        storage: storage,
        modelList: modelList,
        probeRunner: runner,
      ),
    ),
  );

  Finder geminiRow() => find.bySemanticsIdentifier('ai-assist-provider-gemini');
  Finder endpointField() =>
      find.bySemanticsIdentifier('ai-assist-endpoint-field');
  Finder keyField() => find.bySemanticsIdentifier('ai-assist-key-field');
  Finder ok() => find.bySemanticsIdentifier('ai-assist-save-key');

  Future<void> chooseGemini(WidgetTester tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(geminiRow());
    await tester.pumpAndSettle();
  }

  Future<void> agree(WidgetTester tester) async {
    final agree = find.bySemanticsIdentifier('ai-consent-agree');
    await tester.scrollUntilVisible(agree, 200);
    await tester.tap(agree);
    await tester.pumpAndSettle();
  }

  testWidgets('Google Gemini is a choice beside the providers', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.text('Google Gemini'), findsOneWidget);
    expect(
      tester
          .widget<RadioListTile<bool>>(find.byType(RadioListTile<bool>))
          .groupValue,
      isFalse,
    );
  });

  testWidgets('choosing it asks for a key, and no address or model', (
    tester,
  ) async {
    await chooseGemini(tester);

    expect(await storage.activeProvider(), AiProvider.ownServer);
    expect(endpointField(), findsNothing);
    expect(find.bySemanticsIdentifier('ai-assist-model-field'), findsNothing);
    expect(find.bySemanticsIdentifier('ai-assist-load-models'), findsNothing);
    expect(keyField(), findsOneWidget);
    expect(find.text('Google Gemini API key'), findsOneWidget);
    expect(find.text('gemini-3.8-flash — Served by Google'), findsOneWidget);
    expect(
      find.text(r'About 13 s and $0.006 a photo (Haiku 5.5: 1.6 s, $0.0005).'),
      findsOneWidget,
    );
    // One run on lab plates is no accuracy claim (D43).
    expect(find.textContaining('error'), findsNothing);
    // The own-server row is not chosen beside it.
    for (final tile in tester.widgetList<RadioListTile<AiProvider>>(
      find.byType(RadioListTile<AiProvider>),
    )) {
      expect(tile.groupValue, isNull);
    }
    expect(modelListRequests, isEmpty);
  });

  testWidgets('the key setup states Google\'s terms', (tester) async {
    await chooseGemini(tester);

    expect(find.text(geminiKeyHint), findsOneWidget);
    expect(
      find.text(
        "On Google's free tier, Google may use what you send to improve its "
        "products; on the paid tier it does not. Google's terms require users "
        'to be 18 or over.',
      ),
      findsOneWidget,
    );
    expect(find.text(geminiReplacesOwnServer), findsNothing);
  });

  testWidgets('the disclosure names Google', (tester) async {
    await chooseGemini(tester);

    expect(
      find.textContaining(l10nEn.aiAssistDisclosureOwnServerGemini(_host)),
      findsOneWidget,
    );
  });

  testWidgets('OK without a key says so and stores nothing', (tester) async {
    await chooseGemini(tester);
    await tester.ensureVisible(ok());
    await tester.tap(ok());
    await tester.pumpAndSettle();

    expect(find.text(geminiKeyMissing), findsOneWidget);
    expect(find.text(l10nEn.aiConsentTitle), findsNothing);
    expect(await storage.readEndpoint(provider: AiProvider.ownServer), isNull);

    await tester.enterText(keyField(), 'g');
    await tester.pump();
    expect(find.text(geminiKeyMissing), findsNothing);
  });

  testWidgets('a pasted key saves Google\'s address, the model and the key, '
      'after the agreement naming Google, and runs the setup check', (
    tester,
  ) async {
    await chooseGemini(tester);
    await tester.enterText(keyField(), ' AIza-key ');
    await tester.ensureVisible(ok());
    await tester.tap(ok());
    await tester.pumpAndSettle();

    expect(find.byType(AiConsentScreen), findsOneWidget);
    expect(
      find.text(l10nEn.aiAssistDisclosureOwnServerGemini(_host)),
      findsOneWidget,
    );
    // Below the fold of the agreement's list.
    expect(find.text(geminiCheckNote, skipOffstage: false), findsOneWidget);
    expect(
      find.text(l10nEn.aiConsentOwnServerCheckNote, skipOffstage: false),
      findsNothing,
    );
    await agree(tester);

    final selection = await storage.readSelection();
    expect(selection?.provider, AiProvider.ownServer);
    expect(selection?.endpoint, geminiPresetEndpoint);
    expect(selection?.modelId, 'gemini-3.8-flash');
    expect(selection?.apiKey, 'AIza-key');
    expect(
      await storage.hasAcceptedTerms(
        provider: AiProvider.ownServer,
        endpoint: geminiPresetEndpoint,
      ),
      isTrue,
    );

    // The setup check, a text line and a photo, went to Google as a meal
    // would: the key, the model, room for thinking.
    await tester.runAsync(() async => runner.current(AiProvider.ownServer));
    await tester.pumpAndSettle();
    expect(google.requests, hasLength(2));
    for (final request in google.requests) {
      expect(request.url.toString(), geminiPresetEndpoint);
      expect(request.headers['authorization'], 'Bearer AIza-key');
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['model'], geminiPresetModel);
      expect(body['max_tokens'], geminiMaxTokens);
      expect(body.containsKey('reasoning_effort'), isFalse);
    }
    final probe = await storage.readProbe(provider: AiProvider.ownServer);
    expect(probe.text, AiCapability.passed);
    expect(probe.photo, AiCapability.passed);
    expect(modelListRequests, isEmpty);
  });

  testWidgets('a saved Gemini key reopens on the Google Gemini row', (
    tester,
  ) async {
    await storage.setActiveProvider(AiProvider.ownServer);
    await storage.setTermsAccepted(true, endpoint: geminiPresetEndpoint);
    await storage.writeOwnServerConfiguration(
      endpoint: geminiPresetEndpoint,
      model: geminiPresetModel,
      provider: AiProvider.ownServer,
    );
    await storage.writeApiKey('AIza-key', provider: AiProvider.ownServer);
    await storage.writeProbe(
      const AiEndpointProbe(
        text: AiCapability.passed,
        photo: AiCapability.passed,
        checked: true,
      ),
      provider: AiProvider.ownServer,
    );

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<RadioListTile<bool>>(find.byType(RadioListTile<bool>))
          .groupValue,
      isTrue,
    );
    expect(endpointField(), findsNothing);
    expect(find.textContaining(l10nEn.aiAssistKeySavedLabel), findsOneWidget);
    expect(find.bySemanticsIdentifier('ai-assist-enabled'), findsOneWidget);
    expect(find.text(l10nEn.aiAssistProbeSectionLabel), findsOneWidget);
    // Nothing to type, so OK closes without asking for a key again.
    await tester.ensureVisible(ok());
    await tester.tap(ok());
    await tester.pumpAndSettle();
    expect(find.text(geminiKeyMissing), findsNothing);
    expect(find.byType(AiAssistDialog), findsNothing);
  });

  testWidgets('Remove keeps the Google Gemini row', (tester) async {
    await storage.setActiveProvider(AiProvider.ownServer);
    await storage.writeOwnServerConfiguration(
      endpoint: geminiPresetEndpoint,
      model: geminiPresetModel,
      provider: AiProvider.ownServer,
    );
    await storage.writeApiKey('AIza-key', provider: AiProvider.ownServer);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    final remove = find.bySemanticsIdentifier('ai-assist-remove-key');
    await tester.ensureVisible(remove);
    await tester.tap(remove);
    await tester.pumpAndSettle();

    expect(await storage.readApiKey(provider: AiProvider.ownServer), isNull);
    expect(
      tester
          .widget<RadioListTile<bool>>(find.byType(RadioListTile<bool>))
          .groupValue,
      isTrue,
    );
    expect(keyField(), findsOneWidget);
    expect(find.text('gemini-3.8-flash — Served by Google'), findsOneWidget);
  });

  group('beside a server the user runs', () {
    setUp(() async {
      await storage.setActiveProvider(AiProvider.ownServer);
      await storage.setTermsAccepted(true);
      await storage.writeOwnServerConfiguration(
        endpoint: _ollama,
        model: 'gemma3:4b',
        provider: AiProvider.ownServer,
      );
    });

    testWidgets('says saving replaces it, and hides its switch and check', (
      tester,
    ) async {
      await chooseGemini(tester);

      expect(find.text(geminiReplacesOwnServer), findsOneWidget);
      expect(find.bySemanticsIdentifier('ai-assist-enabled'), findsNothing);
      expect(find.bySemanticsIdentifier('ai-assist-remove-key'), findsNothing);
      expect(find.text(l10nEn.aiAssistProbeSectionLabel), findsNothing);
      expect(modelListRequests, isEmpty);
    });

    testWidgets('going back to your own server shows what it holds', (
      tester,
    ) async {
      await chooseGemini(tester);
      await tester.tap(find.text(l10nEn.aiAssistProviderOwnServerLabel));
      await tester.pumpAndSettle();

      expect(endpointField(), findsOneWidget);
      expect(find.widgetWithText(TextField, _ollama), findsWidgets);
      expect(find.widgetWithText(TextField, 'gemma3:4b'), findsWidgets);
      expect(modelListRequests, isEmpty);
    });

    testWidgets('saving Gemini replaces it', (tester) async {
      await chooseGemini(tester);
      await tester.enterText(keyField(), 'AIza-key');
      await tester.ensureVisible(ok());
      await tester.tap(ok());
      await tester.pumpAndSettle();
      await agree(tester);

      final selection = await storage.readSelection();
      expect(selection?.endpoint, geminiPresetEndpoint);
      expect(selection?.modelId, geminiPresetModel);
      expect(selection?.apiKey, 'AIza-key');
      await tester.runAsync(() async => runner.current(AiProvider.ownServer));
    });

    testWidgets('its key is not Google\'s: OK asks for one, sends nothing', (
      tester,
    ) async {
      // The key is bound to the server it was saved for (#1257). Were the
      // check on any stored key rather than one for Google's address, OK
      // would save Google's address over the Ollama key.
      await storage.writeApiKey('ollama-key', provider: AiProvider.ownServer);
      await chooseGemini(tester);

      expect(find.textContaining(l10nEn.aiAssistKeySavedLabel), findsNothing);
      expect(
        tester
            .widget<TextField>(
              find.descendant(of: keyField(), matching: find.byType(TextField)),
            )
            .controller
            ?.text,
        isEmpty,
      );

      await tester.ensureVisible(ok());
      await tester.tap(ok());
      await tester.pumpAndSettle();

      expect(find.text(geminiKeyMissing), findsOneWidget);
      expect(find.byType(AiConsentScreen), findsNothing);
      expect(
        await storage.readEndpoint(provider: AiProvider.ownServer),
        _ollama,
      );
      expect(
        await storage.readApiKey(provider: AiProvider.ownServer),
        'ollama-key',
      );
      await tester.runAsync(() async => runner.current(AiProvider.ownServer));
      expect(google.requests, isEmpty);

      await tester.enterText(keyField(), 'AIza-key');
      await tester.tap(ok());
      await tester.pumpAndSettle();
      await agree(tester);

      final selection = await storage.readSelection();
      expect(selection?.endpoint, geminiPresetEndpoint);
      expect(selection?.apiKey, 'AIza-key');
      await tester.runAsync(() async => runner.current(AiProvider.ownServer));
      await tester.pumpAndSettle();
      expect(google.requests, isNotEmpty);
      for (final request in google.requests) {
        expect(request.headers['authorization'], 'Bearer AIza-key');
      }
    });
  });

  testWidgets('a Gemini address typed under your own server stays there', (
    tester,
  ) async {
    // Upstream's #1257 path: another model on Google's address is the user's
    // own configuration, fields and all.
    await storage.setActiveProvider(AiProvider.ownServer);
    await storage.setTermsAccepted(true, endpoint: geminiPresetEndpoint);
    await storage.writeOwnServerConfiguration(
      endpoint: 'https://generativelanguage.googleapis.com/v1beta/openai/',
      model: 'gemini-3.1-pro',
      provider: AiProvider.ownServer,
    );
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(endpointField(), findsOneWidget);
    expect(
      tester
          .widget<RadioListTile<bool>>(find.byType(RadioListTile<bool>))
          .groupValue,
      isFalse,
    );
  });

  testWidgets('Cancel puts the provider back', (tester) async {
    await chooseGemini(tester);
    await tester.tap(find.bySemanticsIdentifier('ai-assist-cancel'));
    await tester.pumpAndSettle();

    expect(await storage.readActiveProviderTag(), isNull);
    expect(await storage.activeProvider(), AiProvider.anthropic);
  });

  test('the presets are Google\'s documented address and model', () {
    expect(
      AiCredentialStorage.resolveEndpoint(
        'https://generativelanguage.googleapis.com/v1beta/openai/',
      ).toString(),
      geminiPresetEndpoint,
    );
    expect(geminiPresetModel, 'gemini-3.8-flash');
    expect(
      isGeminiPreset(
        provider: AiProvider.ownServer,
        endpoint: geminiPresetEndpoint,
        model: geminiPresetModel,
      ),
      isTrue,
    );
    expect(
      isGeminiPreset(
        provider: AiProvider.ownServer,
        endpoint: 'https://generativelanguage.googleapis.com.example.org/v1',
        model: geminiPresetModel,
      ),
      isFalse,
    );
  });

  test('the settings row and the agreement name Google for it', () {
    expect(
      aiDisclosureFor(
        l10nEn,
        provider: AiProvider.ownServer,
        typedEndpoint: geminiPresetEndpoint,
      ),
      l10nEn.aiAssistDisclosureOwnServerGemini(_host),
    );
  });
}
