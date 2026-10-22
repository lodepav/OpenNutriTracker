import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:opennutritracker/core/utils/ai_credential_storage.dart';

/// `--dart-define=FORK_FAKE_AI=true`: emulator runs without a model key.
/// Off in every normal build, where none of this is reached.
const forkFakeAi = bool.fromEnvironment('FORK_FAKE_AI');

/// Turns the AI features on with a dummy Anthropic key, as if the user had
/// agreed to the terms and pasted one.
Future<void> enableFakeAi(AiCredentialStorage storage) async {
  await storage.setTermsAccepted(true);
  await storage.writeApiKey('fake-key', provider: AiProvider.anthropic);
  await storage.setActiveProvider(AiProvider.anthropic);
}

/// Answers Anthropic's messages endpoint the way a model that recognises
/// most things would; every other request goes out as usual.
class FakeAiClient extends http.BaseClient {
  final http.Client _inner;

  FakeAiClient(this._inner);

  /// Ingredients of one serving, for the dishes the emulator check types.
  /// Anything else breaks down to nothing, like a dish the model does not
  /// know.
  static const _dishes = {
    'khachapuri': [
      ('wheat flour, white, all-purpose', 120),
      ('cheese, mozzarella, whole milk', 100),
      ('egg, whole, raw', 50),
      ('butter, salted', 20),
    ],
    'pelmeni': [
      ('wheat flour, white, all-purpose', 80),
      ('pork, ground, raw', 60),
      ('beef, ground, raw', 60),
      ('onion, raw', 15),
    ],
    'grey peas': [
      ('split peas, raw', 100),
      ('pork bacon', 30),
      ('onion, raw', 20),
    ],
  };

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.url.host != 'api.anthropic.com' || request is! http.Request) {
      return _inner.send(request);
    }
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    final system = '${body['system'] ?? ''}';
    final text = _userText(body);
    final items = system.contains('You break a dish into the ingredients')
        ? _breakdown(text)
        : _read(text);
    await Future<void>.delayed(const Duration(milliseconds: 700));
    final reply = jsonEncode({
      'content': [
        {
          'type': 'tool_use',
          'id': 'fake',
          'name': 'log_meal_items',
          'input': {'items': items},
        },
      ],
      'stop_reason': 'tool_use',
    });
    return http.StreamedResponse(
      Stream.value(utf8.encode(reply)),
      200,
      headers: {'content-type': 'application/json'},
    );
  }

  static String _userText(Map<String, dynamic> body) {
    final buffer = StringBuffer();
    for (final message in body['messages'] as List? ?? const []) {
      final content = (message as Map)['content'];
      if (content is String) buffer.writeln(content);
      if (content is List) {
        for (final block in content) {
          if (block is Map && block['type'] == 'text') {
            buffer.writeln(_withoutPhotoPrompt('${block['text']}'));
          }
          // A photo: the model "sees" a khachapuri.
          if (block is Map && block['type'] == 'image') {
            buffer.writeln('khachapuri');
          }
        }
      }
    }
    return buffer.toString();
  }

  /// A photo's text part is the fixed prompt plus, maybe, the user's
  /// note: only the note names food.
  static String _withoutPhotoPrompt(String text) {
    if (!text.startsWith('List the foods in this photo.')) return text;
    return RegExp(r'''The user's note: "(.*)"$''').firstMatch(text)?[1] ?? '';
  }

  static List<Map<String, Object>> _breakdown(String text) {
    final dish = RegExp(r'Dish: (.*?)\. One serving').firstMatch(text)?[1];
    final lower = dish?.toLowerCase() ?? '';
    final key = _dishes.keys.where(lower.contains).firstOrNull;
    return [
      for (final (query, grams) in _dishes[key] ?? const <(String, int)>[])
        {'query': query, 'quantity': grams, 'unit': 'g'},
    ];
  }

  /// The meal text, one item per comma, "and", "+" or line; a leading
  /// amount with g or ml is kept, as the real model keeps a stated one.
  static List<Map<String, Object>> _read(String text) {
    final amount = RegExp(r'^(\d+(?:[.,]\d+)?)\s*(g|ml)?\s+(.+)$');
    return [
      for (final part in text.split(RegExp(r',|\+|\n|\band\b')))
        if (part.trim().isNotEmpty)
          if (amount.firstMatch(part.trim()) case final m?)
            {
              'query': m[3]!,
              'quantity': double.parse(m[1]!.replaceAll(',', '.')),
              'unit': ?m[2],
            }
          else
            {'query': part.trim()},
    ];
  }
}
