// The phase 1.4 model comparison (D7): upstream's photo path, unchanged, run
// over the photo test set in fork/eval/photos.json for each model, with every
// returned name looked up in the bundled food table. Makes paid API calls, so
// it is skipped unless a key is given:
//
//   python3 -I fork/tools/fetch_eval_photos.py
//   FORK_EVAL_OPENROUTER_KEY=sk-or-... flutter test test/fork/eval
//
// FORK_EVAL_MODELS overrides the models, as `model@provider` separated by
// commas (no `@provider` lets OpenRouter route). The report is written to
// build/fork-eval/<time>/report.md, with the raw answers beside it.
//
// FORK_EVAL_REPLAY=build/fork-eval/replay/<name> runs it with no key and no
// call out, on answers a subagent wrote (fork/eval/REPLAY.md): the first run
// saves the requests, the run after the answers are in scores them.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:opennutritracker/features/add_meal/data/model_meal_photo_interpreter.dart';
import 'package:opennutritracker/features/add_meal/domain/meal_photo_interpreter.dart';
import 'package:opennutritracker/fork/food/local_food_data_source.dart';

import 'eval_model.dart';

const _photoDir = 'build/fork-eval/photos';

void main() {
  final models = EvalModels();
  final skip = models.skip != false
      ? models.skip
      : !Directory(_photoDir).existsSync()
      ? 'run fork/tools/fetch_eval_photos.py first'
      : false;

  final manifest =
      jsonDecode(File('fork/eval/photos.json').readAsStringSync()) as Map;
  final photos = (manifest['photos'] as List).cast<Map<String, dynamic>>();
  final runDir = evalRunDir('');
  final report = <String, List<_PhotoResult>>{};

  late LocalFoodDataSource foods;
  setUpAll(() async => foods = await loadFoodTable());

  tearDownAll(() {
    if (report.isEmpty) return;
    runDir.createSync(recursive: true);
    File('${runDir.path}/results.json').writeAsStringSync(
      const JsonEncoder.withIndent(' ').convert({
        for (final MapEntry(:key, :value) in report.entries)
          key: [for (final r in value) r.toJson()],
      }),
    );
    File(
      '${runDir.path}/report.md',
    ).writeAsStringSync(_markdown(report, photos));
    // ignore: avoid_print
    print('report: ${runDir.path}/report.md');
  });

  for (final spec in models.specs) {
    test(
      spec,
      () async {
        final client = http.Client();
        final interpreter = ModelMealPhotoInterpreter(models.api(spec, client));
        final results = report[spec] = [];
        for (final photo in photos) {
          final file = File('$_photoDir/${photo['id']}.jpg');
          if (!file.existsSync()) continue;
          final watch = Stopwatch()..start();
          try {
            final parsed = await interpreter.interpret(
              MealPhoto(bytes: file.readAsBytesSync(), mediaType: 'image/jpeg'),
              localeCode: 'en',
            );
            final items = <_Item>[];
            for (final item in parsed.items) {
              final top = (await foods.fetchSearchWordResults(
                item.query,
                forResolution: true,
              )).firstOrNull;
              items.add(
                _Item(item.query, item.quantity, item.portion, top?.name),
              );
            }
            results.add(
              _PhotoResult(photo, items, null, watch.elapsedMilliseconds),
            );
          } on MealInterpreterException catch (e) {
            results.add(
              _PhotoResult(photo, const [], '$e', watch.elapsedMilliseconds),
            );
          }
        }
        client.close();
        models.reportWaiting(results.where((r) => r.error != null).length);
      },
      timeout: const Timeout(Duration(minutes: 30)),
      skip: skip,
    );
  }
}

class _Item {
  final String query;
  final double? quantity;
  final String? portion;

  /// The bundled table's first row for [query], or null when it has none:
  /// the dish phase 1c breaks into ingredients.
  final String? match;

  _Item(this.query, this.quantity, this.portion, this.match);

  Map<String, Object?> toJson() => {
    'query': query,
    'quantity': quantity,
    'portion': portion,
    'match': match,
  };
}

class _PhotoResult {
  final Map<String, dynamic> photo;
  final List<_Item> items;
  final String? error;
  final int ms;

  _PhotoResult(this.photo, this.items, this.error, this.ms);

  List<String> get _expected => (photo['expect_any'] as List).cast<String>();

  bool _isDish(_Item item) =>
      _expected.any((word) => item.query.toLowerCase().contains(word));

  /// Some returned name holds one of the words the dish goes by.
  bool get identified => items.any(_isDish);

  /// Pieces of the dish counted, when the photo has a countable dish.
  double? get counted {
    if (photo['count'] == null) return null;
    final dish = items.where(_isDish);
    if (dish.isEmpty) return null;
    return dish.fold<double>(0, (sum, item) => sum + (item.quantity ?? 0));
  }

  bool? get countOk {
    final range = photo['count'] as List?;
    final n = counted;
    if (range == null) return null;
    return n != null && n >= (range[0] as num) && n <= (range[1] as num);
  }

  Map<String, Object?> toJson() => {
    'id': photo['id'],
    'error': error,
    'ms': ms,
    'identified': identified,
    'counted': counted,
    'count_ok': countOk,
    'items': [for (final item in items) item.toJson()],
  };
}

String _markdown(
  Map<String, List<_PhotoResult>> report,
  List<Map<String, dynamic>> photos,
) {
  final out = StringBuffer('# Photo test, ${DateTime.now()}\n\n')
    ..writeln(
      '| Model | Dish named | Count right | No table match | Errors '
      '| Median s |',
    )
    ..writeln('|---|---|---|---|---|---|');
  for (final MapEntry(:key, :value) in report.entries) {
    final counts = value.where((r) => r.countOk != null);
    final unmatched = value.where(
      (r) => r.items.any((i) => r._isDish(i) && i.match == null),
    );
    final ms = [for (final r in value) r.ms]..sort();
    out.writeln(
      '| $key | ${value.where((r) => r.identified).length}/${value.length} '
      '| ${counts.where((r) => r.countOk!).length}/${counts.length} '
      '| ${unmatched.length} '
      '| ${value.where((r) => r.error != null).length} '
      '| ${ms.isEmpty ? '-' : (ms[ms.length ~/ 2] / 1000).toStringAsFixed(1)} |',
    );
  }
  out.writeln('\n## Per photo\n');
  for (final photo in photos) {
    out.writeln('### ${photo['id']} — ${photo['dish']}\n');
    out.writeln(
      '${photo['note']}. Expected count: ${photo['count'] ?? '-'}.\n',
    );
    for (final MapEntry(:key, :value) in report.entries) {
      final r = value.where((r) => r.photo['id'] == photo['id']).firstOrNull;
      if (r == null) continue;
      final items =
          r.error ??
          r.items
              .map(
                (i) =>
                    '${i.quantity == null ? '' : '${i.quantity!.toStringAsFixed(0)}× '}'
                    '${i.query}${i.portion == null ? '' : ' (${i.portion})'}'
                    ' → ${i.match ?? '*no match*'}',
              )
              .join('; ');
      out.writeln('- **$key** ${r.identified ? '✓' : '✗'}: $items');
    }
    out.writeln();
  }
  return out.toString();
}
