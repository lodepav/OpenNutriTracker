// Fork cases moved out of test/unit_test/meal_items_api_factory_test.dart (they test the fork's changes).
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:opennutritracker/core/utils/ai_credential_storage.dart';
import 'package:opennutritracker/core/utils/ai_model_catalogue.dart';
import 'package:opennutritracker/features/add_meal/data/meal_items_api_factory.dart';
import 'package:opennutritracker/features/add_meal/domain/meal_items_api.dart';

/// Records where a request actually went. Everything else in this suite
/// checks a shape; this checks a destination.
class CapturingClient extends http.BaseClient {
  Uri? url;
  Map<String, String>? headers;
  Map<String, dynamic>? body;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    url = request.url;
    headers = request.headers;
    body = jsonDecode((request as http.Request).body) as Map<String, dynamic>;
    // Enough of a reply to get past parsing; the assertions are on the way
    // out, not the way back.
    return http.StreamedResponse(
      Stream.value(
        utf8.encode(
          jsonEncode({
            'content': [
              {
                'type': 'tool_use',
                'name': 'log_meal_items',
                'input': {'items': []},
              },
            ],
            'choices': [
              {
                'finish_reason': 'tool_calls',
                'message': {
                  'tool_calls': [
                    {
                      'function': {
                        'name': 'log_meal_items',
                        'arguments': '{"items":[]}',
                      },
                    },
                  ],
                },
              },
            ],
            // OpenAI's Responses shape, so one canned body satisfies all
            // three clients and the assertions stay on the way out.
            'output': [
              {
                'type': 'function_call',
                'name': 'log_meal_items',
                'arguments': '{"items":[]}',
              },
            ],
          }),
        ),
      ),
      200,
      request: request,
    );
  }
}

Future<CapturingClient> send(AiSelection selection) async {
  final client = CapturingClient();
  await mealItemsApiFor(
    client,
    selection,
  ).requestItems(content: const MealTextContent('toast'), system: 'system');
  return client;
}

void main() {
  group('the model the settings screen named is the model that is sent', () {
    test('defaults to the curated first entry', () async {
      final client = await send(
        const AiSelection(provider: AiProvider.openrouter, apiKey: 'sk-or'),
      );

      expect(client.body!['model'], AiModelCatalogue.openrouter.first.id);
      expect(client.body!['model'], 'anthropic/claude-sonnet-5.5');
    });

    test('honours a stored choice', () async {
      final client = await send(
        const AiSelection(
          provider: AiProvider.openrouter,
          apiKey: 'sk-or',
          modelId: 'anthropic/claude-haiku-5.5',
        ),
      );

      expect(client.body!['model'], 'anthropic/claude-haiku-5.5');
    });
  });

  test('every curated OpenRouter model is pinned, fallbacks off; only a '
      'model asked not to think skips the parameter filter', () async {
    // OpenRouter's filter refuses a forced tool_choice to Haiku 5.5 on every
    // endpoint (404); the pin still names who serves it.
    for (final model in AiModelCatalogue.openrouter) {
      final client = await send(
        AiSelection(
          provider: AiProvider.openrouter,
          apiKey: 'sk-or',
          modelId: model.id,
        ),
      );

      final provider = client.body!['provider'] as Map;
      expect(provider['only'], isNotEmpty, reason: model.id);
      expect(provider['allow_fallbacks'], false, reason: model.id);
      expect(provider['data_collection'], 'deny', reason: model.id);
      expect(
        provider['require_parameters'],
        model.toolCall == AiToolCall.forcedThinkingOff ? isNull : true,
        reason: model.id,
      );
    }
  });
}
