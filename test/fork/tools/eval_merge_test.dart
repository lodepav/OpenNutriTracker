// fork/tools/eval_merge.dart, which sets repeated live eval runs side by side.
import 'package:flutter_test/flutter_test.dart';

import '../../../fork/tools/eval_merge.dart';

Map<String, Object?> _read(String photo, double kcal, {String? note}) => {
  'spec': 'direct:claude-haiku-5-5',
  'photo': photo,
  'note': note,
  'kcal': kcal,
  'reference': 500.0,
};

void main() {
  test('usage adds up by model; a run without a price leaves no total', () {
    final merged = mergeUsage([
      {
        'direct:claude-haiku-5-5': {
          'calls': 10,
          'input_tokens': 30000,
          'output_tokens': 4000,
          'usd': 0.005,
        },
        'anthropic/claude-haiku-5.5@anthropic': {
          'calls': 2,
          'input_tokens': 10,
          'output_tokens': 5,
          'usd': null,
        },
      },
      {
        'direct:claude-haiku-5-5': {
          'calls': 5,
          'input_tokens': 15000,
          'output_tokens': 2000,
          'usd': 0.0025,
        },
      },
    ]);
    final haiku = merged['direct:claude-haiku-5-5']!;
    expect((haiku.calls, haiku.input, haiku.output), (15, 45000, 6000));
    expect(haiku.usd, closeTo(0.0075, 1e-9));
    expect(merged['anthropic/claude-haiku-5.5@anthropic']!.usd, isNull);
  });

  test('a read over three runs: its mean, spread and whether it held', () {
    final reads = mergeKcal([
      [_read('pork', 450), _read('pork', 500, note: 'pork chop')],
      [_read('pork', 600), _read('soup', 500)],
      [_read('pork', 480)],
    ]);
    // pork without a note moved most, so it comes first
    final pork = reads.first;
    expect((pork.photo, pork.note), ('pork', null));
    expect(pork.kcal, [450.0, 600.0, 480.0]);
    expect(pork.mean, closeTo(510, 1e-9));
    expect(pork.spread, closeTo(0.3, 1e-9));
    expect(pork.off, closeTo(0.02, 1e-9));
    expect(pork.alwaysWithin(0.25), isTrue);
    expect(pork.alwaysWithin(0.1), isFalse);
    // the same photo with its note is a read of its own
    expect(reads.where((r) => r.photo == 'pork'), hasLength(2));
  });

  test('the report lists the steadiness per model and the widest reads', () {
    final text = render(
      2,
      mergeUsage([
        {
          'direct:claude-haiku-5-5': {
            'calls': 3,
            'input_tokens': 9000,
            'output_tokens': 900,
            'usd': 0.00135,
          },
        },
      ]),
      mergeKcal([
        [_read('pork', 450), _read('soup', 900)],
        [_read('pork', 600)],
      ]),
    );
    expect(text, contains('# 2 eval runs merged'));
    expect(
      text,
      contains('| direct:claude-haiku-5-5 | 3 | 9000 | 900 | \$0.0014 |'),
    );
    // two reads, one repeated; soup at 80% off was never within 25%
    expect(text, contains('| direct:claude-haiku-5-5 | 2 | 1 |'));
    expect(text, contains('| 1/2 |'));
    expect(
      text,
      contains('| direct:claude-haiku-5-5 | pork |  | 450, 600 | 500 | 30% |'),
    );
    // a read made once has no spread to list
    expect(text, isNot(contains('| soup |')));
  });

  test('runs without usage or kcal give only the heading', () {
    expect(render(1, mergeUsage([]), mergeKcal([])), '# 1 eval runs merged\n');
  });
}
