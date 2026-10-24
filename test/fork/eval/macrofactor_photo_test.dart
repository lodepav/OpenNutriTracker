// Phase 4: photos of dishes the user logs often, read alone and with the
// name the user logs them by. The dishes come from the user's MacroFactor
// log and stay out of the repo with its labels: the manifest is
// build/fork-eval/macrofactor/photos.json (web photos, each with the title
// words a right row holds and the words it must not, as in labels.json).
//
//   python3 -I fork/tools/fetch_eval_photos.py \
//       --manifest build/fork-eval/macrofactor/photos.json
//   FORK_EVAL_REPLAY=build/fork-eval/replay/haiku flutter test test/fork/eval
//
// "Named": a row's query holds the dish. "Right row": a row's table match
// does. The report is written to build/fork-eval/<time>-mf-photos/report.md.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:opennutritracker/features/add_meal/data/model_meal_photo_interpreter.dart';
import 'package:opennutritracker/features/add_meal/domain/meal_photo_interpreter.dart';
import 'package:opennutritracker/features/add_meal/util/meal_text_parser.dart';
import 'package:opennutritracker/fork/food/local_food_data_source.dart';

import 'eval_model.dart';

const _manifest = 'build/fork-eval/macrofactor/photos.json';
const _photoDir = 'build/fork-eval/photos';

/// Whether [text] holds the dish [photo] shows.
bool _right(Map<String, dynamic> photo, String? text) {
  final t = (text ?? '').toLowerCase();
  final reject = (photo['reject'] as List).cast<String>();
  if (t.isEmpty || reject.any(t.contains)) return false;
  return (photo['accept'] as List).any(
    (parts) => (parts as List).cast<String>().every(t.contains),
  );
}

void main() {
  final file = File(_manifest);
  final photos = !file.existsSync()
      ? <Map<String, dynamic>>[]
      : ((jsonDecode(file.readAsStringSync()) as Map)['photos'] as List)
            .cast<Map<String, dynamic>>()
            .where((p) => File('$_photoDir/${p['id']}.jpg').existsSync())
            .toList();
  final models = EvalModels();
  final runDir = evalRunDir('-mf-photos');
  final summary = StringBuffer(
    '| Model | Note | Dish named | Right row | Rows | With a table row |\n'
    '|---|---|---|---|---|---|\n',
  );
  final rows = StringBuffer();

  late LocalFoodDataSource foods;
  setUpAll(() async {
    if (photos.isNotEmpty) foods = await loadFoodTable();
  });

  tearDownAll(() {
    if (rows.isEmpty) return;
    runDir.createSync(recursive: true);
    File('${runDir.path}/report.md').writeAsStringSync(
      '# MacroFactor dish photos, ${DateTime.now()}\n\n$summary\n$rows',
    );
    // ignore: avoid_print
    print('report: ${runDir.path}/report.md');
  });

  for (final spec in models.specs) {
    test(
      spec,
      () async {
        final client = http.Client();
        final interpreter = ModelMealPhotoInterpreter(models.api(spec, client));
        var waiting = 0;
        rows
          ..writeln('## $spec\n')
          ..writeln('| Photo | Note | Named | Right row | Rows |')
          ..writeln('|---|---|---|---|---|');

        for (final withNote in [false, true]) {
          var read = 0, named = 0, right = 0, total = 0, matched = 0;
          for (final photo in photos) {
            final note = withNote ? photo['user_note'] as String : null;
            final List<ParsedMealItem> items;
            try {
              items = (await interpreter.interpret(
                MealPhoto(
                  bytes: File(
                    '$_photoDir/${photo['id']}.jpg',
                  ).readAsBytesSync(),
                  mediaType: 'image/jpeg',
                ),
                localeCode: 'en',
                note: note,
              )).items;
            } on MealInterpreterException {
              waiting++;
              continue;
            }
            read++;
            final isNamed = items.any((i) => _right(photo, i.query));
            if (isNamed) named++;
            var isRight = false;
            final cells = <String>[];
            for (final item in items) {
              total++;
              final row = await tableMatch(foods, item.query);
              if (row != null) matched++;
              if (_right(photo, row?.name)) isRight = true;
              cells.add('${item.query} → ${row?.name ?? '*none*'}');
            }
            if (isRight) right++;
            rows.writeln(
              '| ${photo['id']} | ${note ?? ''} | ${isNamed ? '✓' : '✗'} '
              '| ${isRight ? '✓' : '✗'} | ${cells.join('; ')} |',
            );
          }
          if (read == 0) continue;
          summary.writeln(
            '| $spec | ${withNote ? 'yes' : 'no'} | $named/$read '
            '| $right/$read | $total | $matched/$total |',
          );
        }
        rows.writeln();
        client.close();
        models.reportWaiting(spec, waiting);
      },
      timeout: const Timeout(Duration(minutes: 30)),
      skip: models.skip != false
          ? models.skip
          : photos.isEmpty
          ? 'needs $_manifest and its photos, fetched by '
                'fork/tools/fetch_eval_photos.py --manifest $_manifest'
          : false,
    );
  }
}
