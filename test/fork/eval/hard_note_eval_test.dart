// Phase 4's harder notes, beside the photo test and with the same models
// (eval_model.dart):
//
// - The Latvian app locale. The photo prompt asks for names "in the user's
//   app language", and the bundled table is English. LIDO's single dishes
//   and three set meals are read with `localeCode: 'lv'`, alone and with
//   their notes, against the same photos read in English.
// - Notes that do more than name the food: one that contradicts the photo,
//   grams, a fraction, a count lower than the photo's, and a food the photo
//   does not show. Each case says what the note asks for.
//
//   FORK_EVAL_REPLAY=build/fork-eval/replay/haiku flutter test test/fork/eval
//
// The report is written to build/fork-eval/<time>-notes/report.md.
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

/// The set meals read in Latvian beside the single dishes.
const _lvSets = {
  'lv-lido-set-karbonade-potatoes',
  'lv-lido-set-tradicionalais',
  'lv-lido-set-saimnieks',
};

bool _has(ParsedMealItem item, List<String> words) =>
    words.any((w) => item.query.toLowerCase().contains(w));

/// The first item named by one of [words], or null.
ParsedMealItem? _named(List<ParsedMealItem> items, List<String> words) =>
    items.where((i) => _has(i, words)).firstOrNull;

bool _amount(ParsedMealItem? item, double quantity, [String? unit]) =>
    item != null && item.quantity == quantity && item.unit == unit;

/// A note that does more than name the food, and what it asks for.
typedef _Case = ({
  String photo,
  String note,
  String asks,
  bool Function(List<ParsedMealItem>) ok,
});

final _cases = <_Case>[
  (
    photo: 'lv-lido-karbonade',
    note: 'vistas fileja',
    asks: 'the note over the photo: chicken, not pork',
    ok: (items) =>
        _named(items, ['chicken', 'vistas']) != null &&
        _named(items, ['pork', 'karbon']) == null,
  ),
  (
    photo: 'lv-lido-buckwheat',
    note: 'rīsi',
    asks: 'the note over the photo: rice, not buckwheat',
    ok: (items) =>
        _named(items, ['rice', 'rīs']) != null &&
        _named(items, ['buckwheat', 'griķ']) == null,
  ),
  (
    photo: 'lv-lido-lyulya',
    note: '2 ļuļa kebabi',
    asks: "the note's count over the photo's three: 2 kebabs",
    ok: (items) => _amount(_named(items, ['kebab', 'lyul', 'ļuļa', 'lula']), 2),
  ),
  (
    photo: 'lv-lido-set-karbonade-potatoes',
    note: 'karbonāde 150 g, kartupeļi 200 g, sēņu mērce',
    asks: 'the grams kept: 150 g karbonāde, 200 g potatoes, sauce unweighed',
    ok: (items) =>
        _amount(_named(items, ['karbon', 'pork', 'chop']), 150, 'g') &&
        _amount(_named(items, ['potato', 'kartup']), 200, 'g') &&
        _named(items, ['sauce', 'mērce'])?.quantity == null,
  ),
  (
    photo: 'lv-lido-buckwheat',
    note: '200g griķu',
    asks: 'the grams kept: 200 g buckwheat',
    ok: (items) => _amount(_named(items, ['buckwheat', 'griķ']), 200, 'g'),
  ),
  (
    photo: 'lv-lido-karbonade',
    note: 'puse karbonādes',
    asks: 'half a karbonāde: 0.5',
    ok: (items) => _amount(_named(items, ['karbon', 'pork', 'chop']), 0.5),
  ),
  (
    photo: 'lv-lido-cabbage-rolls',
    note: '1.5 kāpostu tītenīši',
    asks: 'one and a half cabbage rolls: 1.5',
    ok: (items) => _amount(_named(items, ['cabbage', 'kāpost', 'tīten']), 1.5),
  ),
  (
    photo: 'lv-lido-karbonade',
    note: 'karbonāde, kafija ar pienu',
    asks: 'the coffee the photo does not show, added',
    ok: (items) =>
        _named(items, ['coffee', 'kafij']) != null &&
        _named(items, ['karbon', 'pork', 'chop']) != null,
  ),
];

void main() {
  final models = EvalModels();
  final manifest =
      jsonDecode(File('fork/eval/photos.json').readAsStringSync()) as Map;
  final photos = {
    for (final photo
        in (manifest['photos'] as List).cast<Map<String, dynamic>>())
      photo['id'] as String: photo,
  };
  final lvPhotos = [
    for (final photo in photos.values)
      if (photo['user_note'] != null &&
          (photo['parts'] == null || _lvSets.contains(photo['id'])))
        photo,
  ];
  final runDir = evalRunDir('-notes');
  final summary = StringBuffer(
    '| Model | Locale | Note | Rows | With a table row | Dish named |\n'
    '|---|---|---|---|---|---|\n',
  );
  final cases = StringBuffer();
  final rows = StringBuffer();

  late LocalFoodDataSource foods;
  setUpAll(() async => foods = await loadFoodTable());

  tearDownAll(() {
    if (rows.isEmpty) return;
    runDir.createSync(recursive: true);
    File('${runDir.path}/report.md').writeAsStringSync(
      '# Hard notes, ${DateTime.now()}\n\n'
      '## The Latvian app locale\n\n'
      '"Dish named" checks the English words photos.json expects, plus the '
      'Latvian note\'s own first word.\n\n$summary'
      '\n## Notes that do more than name the food\n\n'
      '| Model | Photo | Note | Asks | Right | Rows |\n'
      '|---|---|---|---|---|---|\n$cases'
      '\n## Rows, Latvian locale\n\n$rows',
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

        Future<List<ParsedMealItem>?> read(
          Map<String, dynamic> photo,
          String locale,
          String? note,
        ) async {
          final file = File('$_photoDir/${photo['id']}.jpg');
          if (!file.existsSync()) return null;
          try {
            return (await interpreter.interpret(
              MealPhoto(bytes: file.readAsBytesSync(), mediaType: 'image/jpeg'),
              localeCode: locale,
              note: note,
            )).items;
          } on MealInterpreterException {
            waiting++;
            return null;
          }
        }

        rows.writeln('### $spec\n');
        for (final locale in ['en', 'lv']) {
          for (final withNote in [false, true]) {
            var total = 0, matched = 0, named = 0, read_ = 0;
            for (final photo in lvPhotos) {
              final note = withNote ? photo['user_note'] as String : null;
              final items = await read(photo, locale, note);
              if (items == null) continue;
              read_++;
              final words = [
                ...(photo['expect_any'] as List).cast<String>(),
                (photo['user_note'] as String)
                    .split(RegExp(r'[ ,]'))
                    .firstWhere((w) => w.length > 2, orElse: () => '')
                    .toLowerCase(),
              ];
              if (items.any((i) => _has(i, words))) named++;
              final cells = <String>[];
              for (final item in items) {
                total++;
                final row = await tableMatch(foods, item.query);
                if (row != null) matched++;
                cells.add('${item.query} → ${row?.name ?? '*none*'}');
              }
              if (locale == 'lv') {
                rows.writeln(
                  '- ${photo['id']}${note == null ? '' : ' + "$note"'}: '
                  '${cells.join('; ')}',
                );
              }
            }
            if (read_ == 0) continue;
            summary.writeln(
              '| $spec | $locale | ${withNote ? 'yes' : 'no'} | $total '
              '| $matched/$total | $named/$read_ |',
            );
          }
        }
        rows.writeln();

        for (final c in _cases) {
          final items = await read(photos[c.photo]!, 'en', c.note);
          if (items == null) continue;
          cases.writeln(
            '| $spec | ${c.photo} | ${c.note} | ${c.asks} '
            '| ${c.ok(items) ? '✓' : '✗'} '
            '| ${items.map(_describe).join('; ')} |',
          );
        }
        client.close();
        models.reportWaiting(spec, waiting);
      },
      timeout: const Timeout(Duration(minutes: 30)),
      skip: models.skip != false
          ? models.skip
          : !Directory(_photoDir).existsSync()
          ? 'run fork/tools/fetch_eval_photos.py first'
          : false,
    );
  }
}

String _describe(ParsedMealItem item) {
  final q = item.quantity;
  final amount = q == null
      ? ''
      : '${q == q.roundToDouble() ? q.round() : q}${item.unit == null ? '× ' : ' ${item.unit} '}';
  return '$amount${item.query}';
}
