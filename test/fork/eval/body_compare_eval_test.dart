// The AI body comparison on progress-photo pairs from Wikimedia Commons
// (fork/eval/bodies.json): real before/after pairs whose captions give the
// direction, weights and dates, and controls built from them (the same
// photo twice, the same with other lighting, the pair reversed, two
// people). Each pair goes in as the app sends it, joined side by side, with
// the captions' figures as the days' logs.
//
//   python3 -I fork/tools/fetch_body_pairs.py
//   FORK_EVAL_REPLAY=build/fork-eval/replay/haiku flutter test test/fork/eval
//
// The report is written to build/fork-eval/<time>-bodies/report.md.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:opennutritracker/features/add_meal/domain/meal_photo_interpreter.dart';
import 'package:opennutritracker/fork/photos/body_compare.dart';

import 'eval_model.dart';

const _pairDir = 'build/fork-eval/bodies';

/// One side's day: the caption's date and weight, or [days] apart.
BodyDay _day(Map<String, dynamic>? side, DateTime fallback) => BodyDay(
  date: side?['date'] == null
      ? fallback
      : DateTime.parse(side!['date'] as String),
  weightKg: (side?['weight_kg'] as num?)?.toDouble(),
);

void main() {
  final models = EvalModels();
  final pairs =
      ((jsonDecode(File('fork/eval/bodies.json').readAsStringSync())
                  as Map)['pairs']
              as List)
          .cast<Map<String, dynamic>>();
  final runDir = evalRunDir('-bodies');
  final summary = StringBuffer(
    '| Model | Pairs | Fat right | Muscle right | Not overconfident '
    '| Lighting named | All right |\n'
    '|---|---|---|---|---|---|---|\n',
  );
  final rows = StringBuffer();

  tearDownAll(() {
    if (rows.isEmpty) return;
    runDir.createSync(recursive: true);
    File('${runDir.path}/report.md').writeAsStringSync(
      '# Body comparison, ${DateTime.now()}\n\n'
      '"Right": the verdict is one fork/eval/bodies.json allows for the '
      'pair. "Not overconfident": certainty at most the pair\'s '
      'certainty_max. "Lighting named": the control with changed light '
      'got a lighting note other than same.\n\n$summary\n$rows',
    );
    // ignore: avoid_print
    print('report: ${runDir.path}/report.md');
  });

  for (final spec in models.specs) {
    test(
      spec,
      () async {
        final client = http.Client();
        final api = models.api(spec, client);
        var waiting = 0, read = 0, allRight = 0;
        final right = {'fat': 0, 'muscle': 0, 'certainty': 0, 'lighting': 0};
        final asked = {'fat': 0, 'muscle': 0, 'certainty': 0, 'lighting': 0};
        rows
          ..writeln('## $spec\n')
          ..writeln(
            '| Pair | Fat | Muscle | Certainty | Lighting | Pose | Summary |',
          )
          ..writeln('|---|---|---|---|---|---|---|');

        for (final pair in pairs) {
          final file = File('$_pairDir/${pair['id']}.jpg');
          if (!file.existsSync()) continue;
          final later = DateTime(2026, 10, 1);
          final earlier = later.subtract(
            Duration(days: (pair['days'] as int?) ?? 0),
          );
          final BodyComparison c;
          try {
            c = await compareJoinedBodies(
              api,
              photo: MealPhoto(
                bytes: file.readAsBytesSync(),
                mediaType: 'image/jpeg',
              ),
              earlierDay: _day(
                pair['earlier'] as Map<String, dynamic>?,
                earlier,
              ),
              laterDay: _day(pair['later'] as Map<String, dynamic>?, later),
            );
          } on MealInterpreterException {
            waiting++;
            continue;
          }
          read++;
          final expect = pair['expect'] as Map<String, dynamic>;
          final checks = <String, bool>{
            'fat': (expect['fat'] as List).contains(c.fat.name),
            if (expect['muscle'] case final List m)
              'muscle': m.contains(c.muscle.name),
            if (expect['certainty_max'] case final num max)
              'certainty': c.certainty <= max,
            if (expect['lighting'] == true)
              'lighting':
                  c.lighting != null &&
                  c.lighting!.trim().toLowerCase() != 'same',
          };
          for (final MapEntry(:key, :value) in checks.entries) {
            asked[key] = asked[key]! + 1;
            if (value) right[key] = right[key]! + 1;
          }
          if (checks.values.every((ok) => ok)) allRight++;
          String mark(String key, String text) => switch (checks[key]) {
            true => '$text ✓',
            false => '$text ✗',
            null => text,
          };
          String cell(String? s) => (s ?? '').replaceAll('|', '/');
          rows.writeln(
            '| ${pair['id']} | ${mark('fat', c.fat.name)} '
            '| ${mark('muscle', c.muscle.name)} '
            '| ${mark('certainty', '${c.certainty}')} '
            '| ${mark('lighting', cell(c.lighting))} | ${cell(c.pose)} '
            '| ${cell(c.summary)} |',
          );
        }
        rows.writeln();
        client.close();
        models.reportWaiting(spec, waiting);
        if (read == 0) return;
        String of(String key) => '${right[key]}/${asked[key]}';
        summary.writeln(
          '| $spec | $read | ${of('fat')} | ${of('muscle')} '
          '| ${of('certainty')} | ${of('lighting')} | $allRight/$read |',
        );
      },
      timeout: const Timeout(Duration(minutes: 30)),
      skip: models.skip != false
          ? models.skip
          : !File('$_pairDir/riggs.jpg').existsSync()
          ? 'run fork/tools/fetch_body_pairs.py first'
          : false,
    );
  }
}
