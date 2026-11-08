// The live evals' token tally and photo split (fork/eval/CREDITS_PLAN.md,
// step 0). Unlike the evals beside it, this runs in the suite: no key needed.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'eval_model.dart';

void main() {
  test('usage is read from the Messages API and from OpenRouter', () {
    final haiku = EvalUsage(EvalUsage.pricesOf('direct:claude-haiku-5-5'))
      ..addAnswer(
        jsonEncode({
          'usage': {
            'input_tokens': 2000,
            'cache_creation_input_tokens': 500,
            'cache_read_input_tokens': 500,
            'output_tokens': 400,
          },
        }),
      )
      ..addAnswer(
        jsonEncode({
          'usage': {'input_tokens': 1000, 'output_tokens': 600},
        }),
      );
    expect((haiku.calls, haiku.input, haiku.output), (2, 4000, 1000));
    // 4000 × $0.10 + 1000 × $0.50, per million
    expect(haiku.usd, closeTo(0.0009, 1e-12));

    final routed =
        EvalUsage(EvalUsage.pricesOf('anthropic/claude-haiku-5.5@anthropic'))
          ..addAnswer(
            jsonEncode({
              'usage': {'prompt_tokens': 3000, 'completion_tokens': 200},
            }),
          );
    expect((routed.calls, routed.input, routed.output), (1, 3000, 200));
    expect(routed.usd, isNull);
  });

  test('an answer without usage, or not JSON, is not counted', () {
    final usage = EvalUsage()
      ..addAnswer('not json')
      ..addAnswer('[1, 2]')
      ..addAnswer(jsonEncode({'content': []}));
    expect(usage.calls, 0);
  });

  test('BackoffClient hands each 200 answer over, not an error', () async {
    final bodies = <String>[];
    var status = 200;
    final client = BackoffClient(
      MockClient((_) async => http.Response('{"usage":{}}', status)),
      onLimited: () {},
      onAnswer: bodies.add,
    );
    await client.post(Uri.parse('https://example.test'));
    status = 400;
    await client.post(Uri.parse('https://example.test'));
    expect(bodies, ['{"usage":{}}']);
  });

  test('a run writes usage.json and a Usage section after its report', () {
    final dir = Directory.systemTemp.createTempSync('eval-usage');
    addTearDown(() => dir.deleteSync(recursive: true));
    File('${dir.path}/report.md').writeAsStringSync('# Report\n');
    final models = EvalModels();
    models
        .usageOf('direct:claude-sonnet-5-5')
        .addAnswer(
          jsonEncode({
            'usage': {'input_tokens': 1000000, 'output_tokens': 100000},
          }),
        );
    // a model with no answer is not listed
    models.usageOf('direct:claude-haiku-5-5');
    models.addUsage(dir);

    expect(
      File('${dir.path}/report.md').readAsStringSync(),
      contains(
        '| direct:claude-sonnet-5-5 | 1 | 1000000 | 100000 | \$3.0000 |',
      ),
    );
    final json =
        jsonDecode(File('${dir.path}/usage.json').readAsStringSync()) as Map;
    expect(json.keys, ['direct:claude-sonnet-5-5']);
    expect(json['direct:claude-sonnet-5-5']['usd'], 3.0);
  });

  test('the split holds every photo once, each cuisine evenly', () {
    final tune = EvalSplit.read('tune').ids;
    final held = EvalSplit.read('held').ids;
    expect(tune.intersection(held), isEmpty);
    final cuisines = <String, List<String>>{};
    for (final set in ['photos.json', 'ilunch.json']) {
      for (final photo
          in (jsonDecode(File('fork/eval/$set').readAsStringSync())
                  as Map)['photos']
              as List) {
        (cuisines[photo['cuisine'] as String] ??= []).add(
          photo['id'] as String,
        );
      }
    }
    final all = {for (final ids in cuisines.values) ...ids};
    // a new photo goes in the smaller half of its cuisine (split.json)
    expect(tune.union(held), all);
    for (final MapEntry(key: cuisine, value: ids) in cuisines.entries) {
      final inTune = ids.where(tune.contains).length;
      expect(
        (inTune - (ids.length - inTune)).abs(),
        lessThanOrEqualTo(1),
        reason: cuisine,
      );
    }
    expect(() => EvalSplit.read('about'), throwsArgumentError);
  });
}
