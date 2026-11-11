import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:opennutritracker/features/add_meal/data/anthropic_meal_items_api.dart';
import 'package:opennutritracker/features/add_meal/data/model_meal_photo_interpreter.dart';
import 'package:opennutritracker/features/add_meal/data/openai_compatible_meal_items_api.dart';
import 'package:opennutritracker/features/add_meal/data/openai_meal_items_api.dart';
import 'package:opennutritracker/features/add_meal/domain/meal_items_api.dart';
import 'package:opennutritracker/features/add_meal/domain/meal_photo_interpreter.dart';
import 'package:opennutritracker/features/add_meal/util/meal_text_parser.dart';
import 'package:opennutritracker/fork/bulk/weighed_plate.dart';

/// Answers each request with the next of [replies]; a null reply throws.
class _Api implements MealItemsApi {
  final List<List<ParsedMealItem>?> replies;
  final systems = <String>[];

  _Api(this.replies);

  @override
  Future<MealTextParseResult> requestItems({
    required MealContent content,
    required String system,
  }) async {
    final reply = replies[systems.length];
    systems.add(system);
    if (reply == null) {
      throw const MealInterpreterException('offline');
    }
    return MealTextParseResult(items: reply, errors: const []);
  }
}

ParsedMealItem _g(String query, double grams) =>
    ParsedMealItem(query: query, quantity: grams, unit: 'g');

final _photo = MealPhoto(bytes: Uint8List(1), mediaType: 'image/webp');

Future<(_Api, MealTextParseResult)> _read(
  List<List<ParsedMealItem>?> replies, {
  String? note,
}) async {
  final api = _Api(replies);
  final result = await ModelMealPhotoInterpreter(
    api,
  ).interpret(_photo, note: note);
  return (api, result);
}

void main() {
  group('which prompt a photo is read with (D42)', () {
    test('no note, or a blank one: estimated, the no-note wording', () async {
      for (final note in [null, '', '  ']) {
        final (api, _) = await _read([
          [_g('rice', 200)],
        ], note: note);
        expect(api.systems.single, startsWith(noNotePlatePrompt));
        expect(plateItemsSchemaFor(api.systems.single), plateItemsToolSchema);
      }
    });

    test('a note that states no amount: estimated, the note wording', () async {
      final (api, _) = await _read([
        [_g('rice', 200)],
      ], note: 'chicken plov');
      expect(api.systems.single, startsWith(estimatedPlatePrompt));
      expect(plateItemsSchemaFor(api.systems.single), plateItemsToolSchema);
    });

    test('a note that states a count: the counts prompt as before', () async {
      final (api, result) = await _read([
        [_g('rice', 200)],
      ], note: '2 eggs');
      expect(api.systems.single, isNot(startsWith(plateReadOpening)));
      expect(plateItemsSchemaFor(api.systems.single), forkItemsToolSchema);
      expect(result.items.single.quantity, isNull);
    });

    test('a note that states weights: the weighed plate', () async {
      final (api, _) = await _read([
        [_g('rice', 200)],
      ], note: 'plov 300g');
      expect(api.systems.single, startsWith(weighedPlatePrompt));
      expect(plateItemsSchemaFor(api.systems.single), plateItemsToolSchema);
    });
  });

  group('the estimating prompts', () {
    test('give no per-piece weights, but keep the patties and bones', () {
      for (final prompt in [estimatedPlatePrompt, noNotePlatePrompt]) {
        expect(prompt, isNot(contains('Weigh pieces by their size')));
        expect(prompt, isNot(contains('80-150 g')));
        expect(prompt, contains('Food on the bone is weighed without'));
      }
      expect(estimatedPlatePrompt, contains('with 3 patties'));
    });

    test('the no-note wording mentions no note to follow', () {
      expect(noNotePlatePrompt, contains('There is no note from the user.'));
      expect(noNotePlatePrompt, isNot(contains('the note names')));
      expect(noNotePlatePrompt, isNot(contains('the note gives')));
      expect(noNotePlatePrompt, isNot(contains('the note or the photo')));
      // the rest is shared, word for word
      expect(noNotePlatePrompt, contains('A salad or slaw lists its dressing'));
      expect(noNotePlatePrompt, contains('never the soup itself'));
    });
  });

  group('a first item with no quantity and no "dish="', () {
    test('names the meal when the rest have grams', () async {
      final (api, result) = await _read([
        [
          const ParsedMealItem(query: 'Chicken dinner plate'),
          _g('chicken breast, grilled', 150),
          _g('rice, white, cooked', 180),
        ],
      ]);
      expect(result.items.map((i) => i.query), [
        'chicken breast, grilled',
        'rice, white, cooked',
      ]);
      expect(result.items.map((i) => i.quantity), [150, 180]);
      expect(api.systems, hasLength(1), reason: 'a name needs no grams');
    });

    test('stays a food when nothing else has grams', () async {
      final reply = [
        const ParsedMealItem(query: 'banana'),
        const ParsedMealItem(query: 'yogurt, greek', quantity: 1),
      ];
      final (_, result) = await _read([reply, reply]);
      expect(result.items.map((i) => i.query), ['banana', 'yogurt, greek']);
    });

    test('a "dish=" item given already is left as it is', () async {
      final (_, result) = await _read([
        [
          const ParsedMealItem(query: 'dish=Plov'),
          _g('rice, pilaf', 250),
          _g('lamb, stewed', 90),
        ],
      ]);
      expect(result.items.map((i) => i.query), ['rice, pilaf', 'lamb, stewed']);
    });
  });

  group('a food left without grams', () {
    test('is asked for once more, with the line appended', () async {
      final (api, result) = await _read([
        [_g('chia pudding, base', 150), const ParsedMealItem(query: 'chia')],
        [_g('chia pudding, base', 150), _g('chia seeds', 13)],
      ]);
      expect(api.systems, hasLength(2));
      expect(api.systems.last, startsWith(noNotePlatePrompt));
      expect(api.systems.last, contains(everyFoodGramsLine));
      expect(api.systems.first, isNot(contains(everyFoodGramsLine)));
      expect(result.items.map((i) => i.quantity), [150, 13]);
    });

    test('is not asked for again when the caller says not to', () async {
      final api = _Api([
        [_g('rice', 200), const ParsedMealItem(query: 'sesame seeds')],
      ]);
      final result = await ModelMealPhotoInterpreter(
        api,
        askAgainForGrams: false,
      ).interpret(_photo);
      expect(api.systems, hasLength(1));
      expect(result.items.map((i) => i.query), ['rice', 'sesame seeds']);
    });

    test('is not asked for again when every food has grams', () async {
      final (api, _) = await _read([
        [_g('rice', 200)],
      ]);
      expect(api.systems, hasLength(1));
    });

    test('a retry still without grams: the count stands, or none', () async {
      final (api, result) = await _read([
        [
          const ParsedMealItem(query: 'pizza, cheese'),
          const ParsedMealItem(query: 'cola'),
        ],
        [
          const ParsedMealItem(query: 'pizza, cheese', quantity: 2),
          _g('cola', 330),
        ],
      ]);
      expect(api.systems, hasLength(2));
      final pizza = result.items.first;
      expect(pizza.quantity, 2, reason: 'two slices, not a default plate');
      expect(pizza.unit, isNull);
      expect(result.items.last.quantity, 330);
    });

    test('a retry with more foods without grams is not taken', () async {
      final (_, result) = await _read([
        [_g('rice', 200), const ParsedMealItem(query: 'sesame seeds')],
        [
          const ParsedMealItem(query: 'rice'),
          const ParsedMealItem(query: 'sesame seeds'),
        ],
      ]);
      expect(result.items.first.quantity, 200);
    });

    test('an empty retry is not taken', () async {
      final (_, result) = await _read([
        [_g('rice', 200), const ParsedMealItem(query: 'sesame seeds')],
        [],
      ]);
      expect(result.items.map((i) => i.query), ['rice', 'sesame seeds']);
    });

    test('a retry that fails leaves the first read', () async {
      final (api, result) = await _read([
        [_g('rice', 200), const ParsedMealItem(query: 'sesame seeds')],
        null,
      ]);
      expect(api.systems, hasLength(2));
      expect(result.items.map((i) => i.query), ['rice', 'sesame seeds']);
      expect(result.items.first.quantity, 200);
    });

    test('a first read that fails still fails', () async {
      expect(() => _read([null]), throwsA(isA<MealInterpreterException>()));
    });
  });

  group('the tool schema', () {
    Map<String, dynamic> props(Map<String, Object?> schema) =>
        ((schema['properties'] as Map)['items'] as Map)['items']['properties']
            as Map<String, dynamic>;

    test('a plate read differs only in quantity and unit', () {
      final plate = props(plateItemsToolSchema);
      final meal = props(forkItemsToolSchema);
      expect(plate.keys, meal.keys);
      for (final key in meal.keys) {
        if (key == 'quantity' || key == 'unit') continue;
        expect(plate[key], meal[key], reason: key);
      }
      expect(plate['quantity']['description'], contains('grams'));
      expect(plate['unit']['enum'], ['g', 'ml']);
      expect(plate['quantity'], isNot(meal['quantity']));
      expect(
        plate.keys,
        isNot(anyElement(anyOf('calories', 'kcal', 'protein'))),
      );
    });

    test('the fork schema differs from upstream\'s only in wording (D51)', () {
      String shape(Map<String, Object?> schema) => jsonEncode(
        schema,
      ).replaceAll(RegExp(r'"description":"(?:[^"\\]|\\.)*"'), '');
      expect(shape(forkItemsToolSchema), shape(mealItemsToolSchema));
      final fork = props(forkItemsToolSchema);
      final upstream = props(mealItemsToolSchema);
      for (final key in upstream.keys) {
        expect(fork[key]['description'], isNot(upstream[key]['description']));
      }
    });

    test('no field contradicts a fork prompt (D51)', () {
      for (final schema in [forkItemsToolSchema, plateItemsToolSchema]) {
        final text = jsonEncode(schema).toLowerCase();
        for (final stale in [
          "in the user's language",
          'only if the user stated',
        ]) {
          expect(text, isNot(contains(stale)));
        }
        for (final banned in [
          'kcal',
          'calorie',
          'energy',
          'protein',
          'carbohydrate',
          'fat',
          'sugar',
          'fiber',
          'nutriment',
        ]) {
          expect(text, isNot(contains(banned)), reason: banned);
        }
      }
    });

    for (final client in _clients) {
      test('${client.name} sends the fork tool description', () async {
        final http = _CapturingClient(client.reply);
        await client
            .build(http)
            .requestItems(
              content: const MealTextContent('rice'),
              system: 'You read a meal description',
            );
        final sent = jsonEncode(http.body);
        expect(sent, contains(jsonEncode(itemsToolDescription)));
        expect(sent, isNot(contains(mealItemsToolDescription)));
      });

      test(
        '${client.name} sends the plate schema on a plate read only',
        () async {
          for (final (system, schema) in [
            (noNotePlatePrompt, plateItemsToolSchema),
            (estimatedPlatePrompt, plateItemsToolSchema),
            (weighedPlatePrompt, plateItemsToolSchema),
            ('You read a meal description', forkItemsToolSchema),
          ]) {
            final http = _CapturingClient(client.reply);
            await client
                .build(http)
                .requestItems(
                  content: const MealTextContent('rice'),
                  system: system,
                );
            expect(
              jsonEncode(client.schemaOf(http.body!)),
              jsonEncode(schema),
              reason: system.split('\n').first,
            );
          }
        },
      );
    }
  });
}

class _Client {
  final String name;
  final MealItemsApi Function(http.Client) build;
  final String reply;
  final Object? Function(Map<String, dynamic> body) schemaOf;

  const _Client(this.name, this.build, this.reply, this.schemaOf);
}

String _chatReply() => jsonEncode({
  'id': 'gen_1',
  'choices': [
    {
      'finish_reason': 'tool_calls',
      'message': {
        'role': 'assistant',
        'tool_calls': [
          {
            'id': 'call_1',
            'type': 'function',
            'function': {
              'name': mealItemsToolName,
              'arguments': jsonEncode({'items': []}),
            },
          },
        ],
      },
    },
  ],
});

final _clients = [
  _Client(
    'Anthropic',
    (c) => AnthropicMealItemsApi(c, () => 'test-key'),
    jsonEncode({
      'id': 'msg_1',
      'type': 'message',
      'role': 'assistant',
      'content': [
        {
          'type': 'tool_use',
          'id': 'tu_1',
          'name': mealItemsToolName,
          'input': {'items': []},
        },
      ],
    }),
    (body) => body['tools'][0]['input_schema'],
  ),
  _Client(
    'OpenAI',
    (c) => OpenAiMealItemsApi(c, () => 'test-key', model: 'gpt-5.6-luna'),
    jsonEncode({
      'id': 'resp_1',
      'object': 'response',
      'status': 'completed',
      'output': [
        {
          'type': 'function_call',
          'id': 'fc_1',
          'call_id': 'call_1',
          'name': mealItemsToolName,
          'arguments': jsonEncode({'items': []}),
        },
      ],
    }),
    (body) => body['tools'][0]['parameters'],
  ),
  _Client(
    'OpenAI-compatible',
    (c) => OpenAiCompatibleMealItemsApi.openRouter(
      c,
      () => 'test-key',
      model: 'anthropic/claude-haiku-4.5',
    ),
    _chatReply(),
    (body) => body['tools'][0]['function']['parameters'],
  ),
];

class _CapturingClient extends http.BaseClient {
  final String reply;
  Map<String, dynamic>? body;

  _CapturingClient(this.reply);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    body =
        jsonDecode(utf8.decode(await request.finalize().toBytes()))
            as Map<String, dynamic>;
    return http.StreamedResponse(
      Stream.value(utf8.encode(reply)),
      200,
      request: request,
    );
  }
}
