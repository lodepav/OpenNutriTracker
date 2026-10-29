// Weighed plates (S175, D24), beside the photo test and with the same models
// (eval_model.dart): the five ways a photo's note can state weights, on
// three plates, as the photo reader returns them. Each case says what the
// rows must add up to.
//
//   FORK_EVAL_REPLAY=build/fork-eval/replay/plates flutter test \
//     test/fork/eval/weighed_plate_eval_test.dart
//
// The report is written to build/fork-eval/<time>-plates/report.md.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:opennutritracker/features/add_meal/data/model_meal_photo_interpreter.dart';
import 'package:opennutritracker/features/add_meal/domain/meal_photo_interpreter.dart';
import 'package:opennutritracker/features/add_meal/util/meal_text_parser.dart';
import 'package:opennutritracker/fork/dish/dish_breakdown_rows.dart';
import 'package:opennutritracker/fork/food/local_food_data_source.dart';

import 'eval_model.dart';

const _photoDir = 'build/fork-eval/photos';

typedef _Case = ({
  String photo,
  String? note,
  String asks,
  bool Function(List<ParsedMealItem>) ok,
});

double _sum(List<ParsedMealItem> items) =>
    items.fold(0, (sum, i) => sum + (i.unit == 'g' ? i.quantity ?? 0 : 0));

bool _grouped(List<ParsedMealItem> items) =>
    items.length > 1 &&
    items.every(
      (i) =>
          i is DishIngredientItem &&
          identical(i.group, (items.first as DishIngredientItem).group),
    );

ParsedMealItem? _named(List<ParsedMealItem> items, List<String> words) => items
    .where((i) => words.any((w) => i.query.toLowerCase().contains(w)))
    .firstOrNull;

/// Each food the note weighs at its weight, under one dish.
bool Function(List<ParsedMealItem>) _each(Map<List<String>, double> weights) =>
    (items) =>
        _grouped(items) &&
        weights.entries.every((e) => _named(items, e.key)?.quantity == e.value);

/// The plate adds up to [grams], as one row or one dish; with [foods],
/// each of them named.
bool Function(List<ParsedMealItem>) _total(
  double grams, [
  List<List<String>> foods = const [],
]) =>
    (items) =>
        (items.length == 1 || _grouped(items)) &&
        _sum(items) == grams &&
        foods.every((words) => _named(items, words) != null);

/// No weight taken from the photograph.
bool _unweighed(List<ParsedMealItem> items) =>
    items.isNotEmpty && items.every((i) => i.unit == null);

const _bowl = 'lv-ilunch-grilled-chicken-bowl';
const _chop = 'lv-lido-set-karbonade-potatoes';
const _pasta = 'ev-bolognese';

final _bowlFoods = [
  ['chicken'],
  ['rice'],
  ['spinach'],
  ['carrot'],
  ['cabbage'],
];

final _cases = <_Case>[
  // 1. each food and its weight
  (
    photo: _bowl,
    note:
        'grilled chicken 120g, rice 100g, spinach 30g, carrot 40g, '
        'red cabbage 40g',
    asks: 'each weight kept, one dish',
    ok: _each({
      ['chicken']: 120,
      ['rice']: 100,
      ['spinach']: 30,
      ['carrot']: 40,
      ['cabbage']: 40,
    }),
  ),
  (
    photo: _chop,
    note: 'pork chop - 150g, potatoes - 180g, mushroom sauce - 60g',
    asks: 'each weight kept, one dish',
    ok: _each({
      ['pork', 'chop']: 150,
      ['potato']: 180,
      ['sauce', 'mushroom']: 60,
    }),
  ),
  (
    photo: _pasta,
    note: 'spaghetti: 200g, bolognese sauce: 150g, parmesan: 10g',
    asks: 'each weight kept, one dish',
    ok: _each({
      ['spaghetti', 'pasta']: 200,
      ['bolognese', 'sauce', 'beef']: 150,
      ['parmesan']: 10,
    }),
  ),
  // 2. each food named, and the total
  (
    photo: _bowl,
    note: 'grilled chicken, rice, spinach, carrot, red cabbage - 350g',
    asks: '350 g in all, the five foods',
    ok: _total(350, _bowlFoods),
  ),
  (
    photo: _bowl,
    note: 'grilled chicken, rice, spinach, carrot, red cabbage. 350g total',
    asks: '350 g in all, the five foods',
    ok: _total(350, _bowlFoods),
  ),
  (
    photo: _chop,
    note: '400g: pork chop, potatoes, mushroom sauce',
    asks: '400 g in all, the three foods',
    ok: _total(400, [
      ['pork', 'chop'],
      ['potato'],
      ['sauce', 'mushroom'],
    ]),
  ),
  (
    photo: _pasta,
    note: 'spaghetti, bolognese sauce, parmesan 380g:',
    asks: '380 g in all, the three foods',
    ok: _total(380, [
      ['spaghetti', 'pasta'],
      ['bolognese', 'sauce', 'beef'],
      ['parmesan'],
    ]),
  ),
  // 3. the dish named, and the total
  (
    photo: _bowl,
    note: 'chicken rice bowl 350g',
    asks: '350 g of one dish',
    ok: _total(350),
  ),
  (
    photo: _chop,
    note: 'pork chop with potatoes - 400 g',
    asks: '400 g of one dish',
    ok: _total(400),
  ),
  (
    photo: _pasta,
    note: 'spaghetti bolognese 380g total',
    asks: '380 g of one dish',
    ok: _total(380),
  ),
  // 4. the total alone
  (photo: _bowl, note: '350g', asks: '350 g in all', ok: _total(350)),
  (photo: _chop, note: '400 g total', asks: '400 g in all', ok: _total(400)),
  (photo: _pasta, note: '380g', asks: '380 g in all', ok: _total(380)),
  // 5. the photo alone
  (photo: _bowl, note: null, asks: 'no weight guessed', ok: _unweighed),
  (photo: _chop, note: null, asks: 'no weight guessed', ok: _unweighed),
  (photo: _pasta, note: null, asks: 'no weight guessed', ok: _unweighed),
];

void main() {
  final models = EvalModels();
  final runDir = evalRunDir('-plates');
  final out = StringBuffer();

  late LocalFoodDataSource foods;
  setUpAll(() async => foods = await loadFoodTable());

  tearDownAll(() {
    if (out.isEmpty) return;
    runDir.createSync(recursive: true);
    File('${runDir.path}/report.md').writeAsStringSync(
      '# Weighed plates, ${DateTime.now()}\n\n'
      '| Model | Photo | Note | Asks | Right | Rows (→ table row) |\n'
      '|---|---|---|---|---|---|\n$out',
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
        var waiting = 0, right = 0, read = 0;
        for (final c in _cases) {
          final file = File('$_photoDir/${c.photo}.jpg');
          final List<ParsedMealItem> items;
          try {
            items = (await interpreter.interpret(
              MealPhoto(bytes: file.readAsBytesSync(), mediaType: 'image/jpeg'),
              localeCode: 'en',
              note: c.note,
            )).items;
          } on MealInterpreterException {
            waiting++;
            continue;
          }
          read++;
          final ok = c.ok(items);
          if (ok) right++;
          final cells = <String>[];
          for (final item in items) {
            final row = await tableMatch(foods, item.query);
            cells.add('${_describe(item)} → ${row?.name ?? '*none*'}');
          }
          final dish = items.firstOrNull is DishIngredientItem
              ? '**${(items.first as DishIngredientItem).dish}**: '
              : '';
          out.writeln(
            '| $spec | ${c.photo} | ${c.note ?? '—'} | ${c.asks} '
            '| ${ok ? '✓' : '✗'} | $dish${cells.join('; ')} |',
          );
        }
        out.writeln('| $spec | | | **right** | **$right/$read** | |');
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
