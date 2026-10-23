import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:opennutritracker/features/add_meal/data/anthropic_meal_items_api.dart';
import 'package:opennutritracker/features/add_meal/domain/meal_items_api.dart';
import 'package:opennutritracker/features/add_meal/util/meal_text_parser.dart';
import 'package:opennutritracker/fork/dev/replay_ai.dart';

void main() {
  late Directory dir;
  late AnthropicMealItemsApi api;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('replay_ai_test');
    final outside = MockClient((_) async => http.Response('outside', 200));
    api = AnthropicMealItemsApi(
      ReplayAiClient(outside, () async => dir),
      () => 'replay',
    );
  });

  tearDown(() => dir.deleteSync(recursive: true));

  const photo = MealPhotoContent(
    mediaType: 'image/jpeg',
    base64Data: 'AQID',
    note: '2 eggs',
  );

  Future<MealTextParseResult> ask() =>
      api.requestItems(content: photo, system: 'You list foods.');

  test('saves an unanswered request and fails it as retryable', () async {
    await expectLater(
      ask(),
      throwsA(
        isA<MealInterpreterException>().having(
          (e) => e.failure,
          'failure',
          MealInterpreterFailure.transient,
        ),
      ),
    );
    final saved = Directory('${dir.path}/requests').listSync();
    final json = saved.whereType<File>().singleWhere(
      (f) => f.path.endsWith('.json'),
    );
    final request = jsonDecode(json.readAsStringSync()) as Map;
    expect(request['system'], 'You list foods.');
    expect(request['text'], contains('2 eggs'));
    expect(request['tool']['input_schema'], isNotNull);
    expect(File('${dir.path}/requests/${request['image']}').readAsBytesSync(), [
      1,
      2,
      3,
    ]);
  });

  test('answers the same request from its saved answer', () async {
    await expectLater(ask(), throwsA(isA<MealInterpreterException>()));
    final key = Directory('${dir.path}/requests')
        .listSync()
        .map((f) => f.uri.pathSegments.last)
        .firstWhere((name) => name.endsWith('.json'))
        .replaceAll('.json', '');
    File('${dir.path}/answers/$key.json')
      ..createSync(recursive: true)
      ..writeAsStringSync(
        jsonEncode({
          'items': [
            {'query': 'egg', 'quantity': 2},
          ],
        }),
      );

    final result = await ask();
    expect(result.items.single.query, 'egg');
    expect(result.items.single.quantity, 2);
  });

  test('the key follows the body', () {
    expect(replayKey('a'), replayKey('a'));
    expect(replayKey('a'), isNot(replayKey('b')));
    expect(replayKey('a'), hasLength(16));
  });
}
