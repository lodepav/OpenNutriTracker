import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:opennutritracker/core/utils/ai_credential_storage.dart';
import 'package:opennutritracker/features/add_meal/data/meal_items_api_factory.dart';
import 'package:opennutritracker/features/add_meal/domain/meal_items_api.dart';
import 'package:opennutritracker/features/add_meal/domain/meal_photo_interpreter.dart';
import 'package:opennutritracker/features/add_meal/domain/usecase/probe_ai_endpoint_usecase.dart';
import 'package:opennutritracker/fork/ai/gemini_preset.dart';

/// Answers every request with [body], and keeps what was sent.
class _Client extends http.BaseClient {
  final String body;
  final requests = <http.Request>[];

  _Client(this.body);

  Map<String, dynamic> get sent =>
      jsonDecode(requests.last.body) as Map<String, dynamic>;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request as http.Request);
    return http.StreamedResponse(
      Stream.value(utf8.encode(body)),
      200,
      request: request,
    );
  }
}

String _toolReply(List<Map<String, dynamic>> items, {String? finish}) =>
    jsonEncode({
      'choices': [
        {
          'finish_reason': ?finish,
          'message': {
            'role': 'assistant',
            'tool_calls': [
              {
                'id': 'call_1',
                'type': 'function',
                'function': {
                  'name': mealItemsToolName,
                  'arguments': jsonEncode({'items': items}),
                },
              },
            ],
          },
        },
      ],
    });

/// What Google's OpenAI-compatible layer answers when the model spends the
/// output limit thinking: a 200, `finish_reason: "length"`, a message with
/// no content and no tool call, every completion token a reasoning token.
/// Shaped after Google's documented reply and the OpenAI usage fields; not
/// captured from a live call.
final _cutOff = jsonEncode({
  'id': 'resp-1',
  'object': 'chat.completion',
  'created': 1762770000,
  'model': geminiPresetModel,
  'choices': [
    {
      'index': 0,
      'finish_reason': 'length',
      'message': {'role': 'assistant'},
    },
  ],
  'usage': {
    'prompt_tokens': 1830,
    'completion_tokens': 1024,
    'total_tokens': 2854,
    'completion_tokens_details': {'reasoning_tokens': 1024},
  },
});

const _gemini = AiSelection(
  provider: AiProvider.ownServer,
  apiKey: 'google-key',
  endpoint: geminiPresetEndpoint,
  modelId: geminiPresetModel,
);

Future<MealInterpreterException> _failure(_Client client) async {
  try {
    await mealItemsApiFor(client, _gemini).requestItems(
      content: const MealTextContent('two eggs and toast'),
      system: 'system',
    );
  } on MealInterpreterException catch (e) {
    return e;
  }
  fail('the request did not fail');
}

void main() {
  group('the request the Google Gemini row sends', () {
    test(
      'goes to Google with the key, the model and the tool by name',
      () async {
        final client = _Client(
          _toolReply([
            {'query': 'egg'},
          ]),
        );
        await mealItemsApiFor(client, _gemini).requestItems(
          content: const MealTextContent('two eggs'),
          system: 'system',
        );

        final request = client.requests.single;
        expect(request.url.toString(), geminiPresetEndpoint);
        expect(request.headers['authorization'], 'Bearer google-key');
        expect(client.sent['model'], 'gemini-3.8-flash');
        expect(client.sent['tool_choice'], {
          'type': 'function',
          'function': {'name': mealItemsToolName},
        });
      },
    );

    test('leaves room for the thinking Google counts in max_tokens', () async {
      // At 1,024 Gemini 3.8 Flash returned nothing for 25 of 67 photos.
      final client = _Client(
        _toolReply([
          {'query': 'egg'},
        ]),
      );
      await mealItemsApiFor(client, _gemini).requestItems(
        content: const MealTextContent('two eggs'),
        system: 'system',
      );

      expect(client.sent['max_tokens'], 4096);
    });

    test(
      'and leaves thinking at the model default, as it was measured',
      () async {
        final client = _Client(
          _toolReply([
            {'query': 'egg'},
          ]),
        );
        await mealItemsApiFor(client, _gemini).requestItems(
          content: const MealTextContent('two eggs'),
          system: 'system',
        );

        expect(client.sent.containsKey('reasoning_effort'), isFalse);
        expect(client.sent.containsKey('reasoning'), isFalse);
        expect(client.sent.containsKey('extra_body'), isFalse);
      },
    );

    test('a server the user runs keeps the 1,024 limit', () async {
      final client = _Client(
        _toolReply([
          {'query': 'egg'},
        ]),
      );
      await mealItemsApiFor(
        client,
        const AiSelection(
          provider: AiProvider.ownServer,
          endpoint: 'http://192.168.1.5:11434/v1/chat/completions',
          modelId: 'gemma3:4b',
        ),
      ).requestItems(
        content: const MealTextContent('two eggs'),
        system: 'system',
      );

      expect(client.sent['max_tokens'], 1024);
    });
  });

  group('a reply cut off at the output limit', () {
    test(
      'is a retryable failure, not a model that cannot call tools',
      () async {
        // Read as `unsupported` it hid the camera and failed the setup check
        // for good (#782), over a reply that only ran out of room.
        final e = await _failure(_Client(_cutOff));

        expect(e.failure, MealInterpreterFailure.transient);
        expect(e.reason, contains('cut off'));
      },
    );

    test('with an empty list is a failure, not an empty meal', () async {
      final e = await _failure(_Client(_toolReply(const [], finish: 'length')));

      expect(e.failure, MealInterpreterFailure.transient);
    });

    test('keeps a tool call that was finished before the limit', () async {
      final client = _Client(
        _toolReply([
          {'query': 'egg'},
        ], finish: 'length'),
      );
      final result = await mealItemsApiFor(client, _gemini).requestItems(
        content: const MealTextContent('two eggs'),
        system: 'system',
      );

      expect(result.items.map((i) => i.query), ['egg']);
    });

    test('leaves the setup check without a verdict', () async {
      final prober = AiEndpointProber(
        _Client(_cutOff),
        sampleImage: (format) async => MealPhoto(
          bytes: Uint8List.fromList([1, 2, 3]),
          mediaType: format.mediaType,
        ),
      );

      final probe = await prober.probe(_gemini);

      expect(probe.text, AiCapability.unknown);
      expect(probe.photo, AiCapability.unknown);
      expect(probe.checked, isTrue);
    });
  });

  test('the setup check asks Google as a meal does', () async {
    final client = _Client(
      _toolReply([
        {'query': 'bread'},
      ]),
    );
    final prober = AiEndpointProber(
      client,
      sampleImage: (format) async => MealPhoto(
        bytes: Uint8List.fromList([1, 2, 3]),
        mediaType: format.mediaType,
      ),
    );

    final probe = await prober.probe(_gemini);

    expect(probe.text, AiCapability.passed);
    expect(probe.photo, AiCapability.passed);
    expect(client.requests.map((r) => r.url.toString()).toSet(), {
      geminiPresetEndpoint,
    });
    for (final request in client.requests) {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['max_tokens'], 4096);
      expect(body['model'], geminiPresetModel);
    }
  });
}
