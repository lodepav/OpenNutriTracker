import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:opennutritracker/core/utils/ai_credential_storage.dart';
import 'package:opennutritracker/core/utils/ai_model_list_api.dart';
import 'package:opennutritracker/features/settings/presentation/widgets/ai_assist_dialog.dart';

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
  }) async => value == null ? store.remove(key) : store[key] = value;

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

  // pumpOnPhone: a 1080x2340, 420 dpi phone (411x891 dp) at twice the font
  // size, in the app's theme and fonts.
  setUp(() => storage = AiCredentialStorage(_MemoryStorage()));

  Widget dialog() => AiAssistDialog(
    storage: storage,
    modelList: AiModelListApi(
      client: MockClient(
        (_) async => http.Response('{"object":"list","data":[]}', 200),
      ),
    ),
  );

  Map<String, bool> clippedUnder(WidgetTester tester, String id) => {
    for (final p in tester.renderObjectList<RenderParagraph>(
      find.descendant(
        of: find.bySemanticsIdentifier(id),
        matching: find.byType(RichText),
      ),
    ))
      p.text.toPlainText(): p.didExceedMaxLines,
  };

  /// The key field's name for each row, and how to choose the row.
  final rows = <String, Future<void> Function(WidgetTester)>{
    'Anthropic API key': (_) async {},
    'OpenRouter API key': (t) => t.tap(find.text('OpenRouter')),
    'OpenAI API key': (t) => t.tap(find.text('OpenAI')),
    'Your own server API key': (t) =>
        t.tap(find.text(l10nEn.aiAssistProviderOwnServerLabel)),
    'Google Gemini API key': (t) =>
        t.tap(find.bySemanticsIdentifier('ai-assist-provider-gemini')),
  };

  for (final MapEntry(key: name, value: choose) in rows.entries) {
    testWidgets('at twice the font size, "$name" is whole and named once', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await pumpOnPhone(tester, dialog());
      await tester.pumpAndSettle();
      await choose(tester);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      final label = find.text(name);
      expect(label, findsOneWidget);
      final paragraph = tester.renderObject<RenderParagraph>(label);
      expect(paragraph.didExceedMaxLines, isFalse);
      expect(cutText(tester), isNot(contains(name)));
      expect(
        clippedUnder(tester, 'ai-assist-key-field').values,
        everyElement(isFalse),
      );

      final named = find.semantics.byLabel(RegExp(RegExp.escape(name)));
      expect(named, findsOne);
      final data = named.evaluate().single.getSemanticsData();
      expect(data.label, name);
      expect(data.flagsCollection.isTextField, isTrue);
      expect(data.identifier, 'ai-assist-key-field');
      semantics.dispose();
    });
  }
}
