// Phase 4: iLunch's Riga menu, recognition only. iLunch publishes no
// nutrition, so unlike LIDO there is no kcal to score: each photo
// (fork/eval/ilunch.json) is read alone and with the Latvian note a person
// would type, and the report says whether the main dish was named and how
// many rows found a table row.
//
//   python3 -I fork/tools/fetch_eval_photos.py --manifest fork/eval/ilunch.json
//   FORK_EVAL_REPLAY=build/fork-eval/replay/haiku flutter test test/fork/eval
//
// The report is written to build/fork-eval/<time>-ilunch/report.md.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:opennutritracker/features/add_meal/data/model_meal_photo_interpreter.dart';
import 'package:opennutritracker/features/add_meal/domain/meal_photo_interpreter.dart';
import 'package:opennutritracker/features/add_meal/util/meal_text_parser.dart';
import 'package:opennutritracker/fork/food/local_food_data_source.dart';

import 'eval_model.dart';

const _photoDir = 'build/fork-eval/photos';

void main() {
  final models = EvalModels();
  final photos =
      ((jsonDecode(File('fork/eval/ilunch.json').readAsStringSync())
                  as Map)['photos']
              as List)
          .cast<Map<String, dynamic>>();
  final runDir = evalRunDir('-ilunch');
  final summary = StringBuffer(
    '| Model | Note | Dish named | Rows | With a table row |\n'
    '|---|---|---|---|---|\n',
  );
  final rows = StringBuffer();

  late LocalFoodDataSource foods;
  setUpAll(() async => foods = await loadFoodTable());

  tearDownAll(() {
    if (rows.isEmpty) return;
    runDir.createSync(recursive: true);
    File('${runDir.path}/report.md').writeAsStringSync(
      '# iLunch recognition, ${DateTime.now()}\n\n'
      '"Dish named": a row holds one of the words fork/eval/ilunch.json '
      'expects for the main dish.\n\n$summary\n$rows',
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
          ..writeln('| Photo | Note | Named | Rows |')
          ..writeln('|---|---|---|---|');

        for (final withNote in [false, true]) {
          var read = 0, named = 0, total = 0, matched = 0;
          for (final photo in photos) {
            final file = File('$_photoDir/${photo['id']}.jpg');
            if (!file.existsSync()) continue;
            final note = withNote ? photo['user_note'] as String : null;
            final List<ParsedMealItem> items;
            try {
              items = (await interpreter.interpret(
                MealPhoto(
                  bytes: file.readAsBytesSync(),
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
            final words = (photo['expect_any'] as List).cast<String>();
            final isNamed = items.any(
              (i) => words.any((w) => i.query.toLowerCase().contains(w)),
            );
            if (isNamed) named++;
            final cells = <String>[];
            for (final item in items) {
              total++;
              final row = await tableMatch(foods, item.query);
              if (row != null) matched++;
              cells.add('${item.query} → ${row?.name ?? '*none*'}');
            }
            rows.writeln(
              '| ${photo['id']} | ${note ?? ''} | ${isNamed ? '✓' : '✗'} '
              '| ${cells.join('; ')} |',
            );
          }
          if (read == 0) continue;
          summary.writeln(
            '| $spec | ${withNote ? 'yes' : 'no'} | $named/$read | $total '
            '| $matched/$total |',
          );
        }
        rows.writeln();
        client.close();
        models.reportWaiting(spec, waiting);
      },
      timeout: const Timeout(Duration(minutes: 30)),
      skip: models.skip != false
          ? models.skip
          : !File('$_photoDir/lv-ilunch-rice.jpg').existsSync()
          ? 'run fork/tools/fetch_eval_photos.py --manifest '
                'fork/eval/ilunch.json first'
          : false,
    );
  }
}
