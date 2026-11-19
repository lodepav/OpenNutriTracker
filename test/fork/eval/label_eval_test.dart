// The AI label reader on nutrition-panel photos from Open Food Facts, whose
// typed per-100 g values are the expected answer. Those values are
// crowd-entered and sometimes come from another pack than the photo, so a
// miss is checked against the photo before it counts.
//
//   python3 -I fork/tools/fetch_label_photos.py
//   FORK_EVAL_ONLINE=1 FORK_EVAL_ANTHROPIC_KEY=... flutter test test/fork/eval/label_eval_test.dart
//
// The report is written to build/fork-eval/<time>-labels/report.md.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:opennutritracker/features/add_meal/domain/meal_items_api.dart';
import 'package:opennutritracker/fork/label/label_scan.dart';

import 'eval_model.dart';

const _dir = 'build/fork-eval/labels';
const _keys = ['energyKcal', 'fat', 'carbs', 'protein', 'sugars'];

/// Within 5 %, or half a unit for small values.
bool _close(double got, num want) =>
    (got - want).abs() <= (want.abs() * 0.05).clamp(0.5, double.infinity);

void main() {
  final models = EvalModels();
  final manifest = File('$_dir/labels.json');
  final labels = manifest.existsSync()
      ? (jsonDecode(manifest.readAsStringSync()) as List)
            .cast<Map<String, dynamic>>()
      : <Map<String, dynamic>>[];
  final runDir = evalRunDir('-labels');
  final summary = StringBuffer(
    '| Model | Labels | Read | ${_keys.join(' | ')} | All five |\n'
    '|---|---|---|${'---|' * _keys.length}---|\n',
  );
  final rows = StringBuffer();

  tearDownAll(() {
    if (rows.isEmpty) return;
    runDir.createSync(recursive: true);
    File('${runDir.path}/report.md').writeAsStringSync(
      '# Label reader, ${DateTime.now()}\n\n'
      'A value is right within 5 % (or 0.5) of the Open Food Facts entry. '
      '"Read": the reply parsed to a non-empty reading. Cells show what '
      'was read, then the entry.\n\n$summary\n$rows',
    );
    models.addUsage(runDir);
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
        final right = {for (final k in _keys) k: 0};
        final asked = {for (final k in _keys) k: 0};
        rows
          ..writeln('## $spec\n')
          ..writeln('| Label | ${_keys.join(' | ')} |')
          ..writeln('|---|${'---|' * _keys.length}');
        for (final label in labels) {
          final file = File('$_dir/${label['code']}.jpg');
          if (!file.existsSync()) continue;
          final LabelReading reading;
          try {
            final result = await api.requestItems(
              content: MealPhotoContent(
                mediaType: 'image/jpeg',
                base64Data: base64Encode(file.readAsBytesSync()),
              ),
              system: labelSystemPrompt,
            );
            reading = LabelReading.fromItems(result.items);
          } on MealInterpreterException {
            waiting++;
            continue;
          }
          final expect = label['expect'] as Map<String, dynamic>;
          final cells = <String>[];
          var all = !reading.isEmpty;
          if (!reading.isEmpty) read++;
          for (final key in _keys) {
            final want = expect[key] as num?;
            final got = reading.per100[key];
            if (want == null) {
              cells.add(got == null ? '' : '$got');
              continue;
            }
            asked[key] = asked[key]! + 1;
            final ok = got != null && _close(got, want);
            if (ok) right[key] = right[key]! + 1;
            all &= ok;
            cells.add('${got ?? '-'} / $want ${ok ? '✓' : '✗'}');
          }
          if (all) allRight++;
          final name = '${label['name']}'.replaceAll('|', '/');
          rows.writeln('| ${label['code']} $name | ${cells.join(' | ')} |');
        }
        rows.writeln();
        client.close();
        models.reportWaiting(spec, waiting);
        String of(String key) => '${right[key]}/${asked[key]}';
        summary.writeln(
          '| $spec | ${labels.length} | $read | '
          '${_keys.map(of).join(' | ')} | $allRight |',
        );
      },
      timeout: const Timeout(Duration(minutes: 30)),
      skip: models.skip != false
          ? models.skip
          : labels.isEmpty
          ? 'run fork/tools/fetch_label_photos.py first'
          : false,
    );
  }
}
