// Phase 4's dish checks, beside the photo test and with the same models
// (eval_model.dart):
//
// - Photo -> breakdown: each test photo's dish, as the model named it, is
//   broken into one serving's ingredients by the fork's own prompt
//   (BreakDownDishUseCase), each ingredient looked up in the bundled table,
//   and the total set against the recipe page's per-serving macros.
// - Typed and photographed names -> saved recipes: whether the model's name
//   for a dish finds the starter recipes (and a saved khachapuri) by the
//   app's recipe match, upstream's substring or every word (S5).
//
//   FORK_EVAL_REPLAY=build/fork-eval/replay/haiku flutter test test/fork/eval
//
// The report is written to build/fork-eval/<time>-dishes/report.md.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:opennutritracker/features/add_meal/data/model_meal_photo_interpreter.dart';
import 'package:opennutritracker/features/add_meal/data/model_meal_text_interpreter.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/meal_items_api.dart';
import 'package:opennutritracker/features/add_meal/domain/meal_photo_interpreter.dart';
import 'package:opennutritracker/fork/dish/break_down_dish_usecase.dart';
import 'package:opennutritracker/fork/dish/recipe_search.dart';
import 'package:opennutritracker/fork/dish/starter_recipes.dart';
import 'package:opennutritracker/fork/food/local_food_data_source.dart';

import 'eval_model.dart';

const _photoDir = 'build/fork-eval/photos';

/// What the user types for the dishes they log, by the recipe it should
/// find. "Adjarian khachapuri" stands for the one saved from a breakdown.
const _typed = {
  'khachapuri': 'Adjarian khachapuri',
  'adjaruli khachapuri': 'Adjarian khachapuri',
  'pelmeni': 'Pelmeni',
  '20 pelmeni with sour cream': 'Pelmeni',
  'grey peas': 'Grey peas with bacon',
  'grey peas with bacon and kefir': 'Grey peas with bacon',
  'sklandu rausi': 'Sklandu rauši',
  'sklandrausis': 'Sklandu rauši',
  '2 sklandrauši': 'Sklandu rauši',
};

/// Photos of dishes that have a saved recipe, by that recipe.
const _photographed = {
  'ge-khachapuri-adjaruli': 'Adjarian khachapuri',
  'ge-khachapuri': 'Adjarian khachapuri',
  'sl-pelmeni': 'Pelmeni',
  'lv-sklandrausis': 'Sklandu rauši',
};

void main() {
  final models = EvalModels();
  final manifest =
      jsonDecode(File('fork/eval/photos.json').readAsStringSync()) as Map;
  final photos = (manifest['photos'] as List).cast<Map<String, dynamic>>();
  final recipes = [
    for (final starter in starterRecipes) starter.name,
    'Adjarian khachapuri',
  ];
  final runDir = evalRunDir('-dishes');
  final out = StringBuffer('# Dish checks, ${DateTime.now()}\n');

  late LocalFoodDataSource foods;
  setUpAll(() async => foods = await loadFoodTable());

  tearDownAll(() {
    if (out.length < 40) return;
    runDir.createSync(recursive: true);
    File('${runDir.path}/report.md').writeAsStringSync(out.toString());
    // ignore: avoid_print
    print('report: ${runDir.path}/report.md');
  });

  /// The recipe the app's recipe search would offer for [query], by
  /// upstream's substring match or the fork's every-word one.
  String? recipeFor(String query) {
    final lower = query.toLowerCase();
    return recipes
        .where(
          (name) =>
              name.toLowerCase().contains(lower) ||
              nameHasQueryWords(name, query),
        )
        .firstOrNull;
  }

  for (final spec in models.specs) {
    test(
      spec,
      () async {
        final client = http.Client();
        final api = models.api(spec, client);
        final photoReader = ModelMealPhotoInterpreter(api);
        final textReader = ModelMealTextInterpreter(api);
        var waiting = 0;
        out.writeln('\n## $spec\n');

        out
          ..writeln('### Typed names find the saved recipe\n')
          ..writeln('| Typed | Model\'s names | Recipe found | Expected |')
          ..writeln('|---|---|---|---|');
        for (final MapEntry(key: typed, value: expected) in _typed.entries) {
          final List<String> names;
          try {
            names = [
              for (final item in (await textReader.interpret(
                typed,
                localeCode: 'en',
              )).items)
                item.query,
            ];
          } on MealInterpreterException {
            waiting++;
            continue;
          }
          final found = names.map(recipeFor).nonNulls.firstOrNull;
          out.writeln(
            '| $typed | ${names.join('; ')} | ${found ?? '—'} '
            '| ${found == expected ? '✓' : '✗ $expected'} |',
          );
        }

        out
          ..writeln('\n### Photo → breakdown, one serving\n')
          ..writeln(
            'Page figures are the recipe sites\' own per serving. "Shown 1" '
            'marks the photos of one serving, the ones that can be '
            'compared fairly.\n',
          )
          ..writeln(
            '| Photo | Shown | Dish named | Recipe found | kcal (page) '
            '| P / C / F g (page) | Unmatched |',
          )
          ..writeln('|---|---|---|---|---|---|---|');
        for (final photo in photos) {
          final file = File('$_photoDir/${photo['id']}.jpg');
          if (!file.existsSync()) continue;
          final List<String> names;
          try {
            names = [
              for (final item in (await photoReader.interpret(
                MealPhoto(
                  bytes: file.readAsBytesSync(),
                  mediaType: 'image/jpeg',
                ),
                localeCode: 'en',
              )).items)
                item.query,
            ];
          } on MealInterpreterException {
            waiting++;
            continue;
          }
          final expected = (photo['expect_any'] as List).cast<String>();
          final dish =
              names
                  .where(
                    (n) => expected.any((w) => n.toLowerCase().contains(w)),
                  )
                  .firstOrNull ??
              names.firstOrNull;
          if (dish == null) continue;
          final recipe = _photographed[photo['id']];
          final found = recipeFor(dish);
          final recipeCell = recipe == null
              ? (found ?? '')
              : found == recipe
              ? '✓ $found'
              : '✗ ${found ?? 'none'}, wanted $recipe';

          final total = _Totals();
          final unmatched = <String>[];
          try {
            final reply = await api.requestItems(
              content: MealTextContent(BreakDownDishUseCase.contentFor(dish)),
              system: BreakDownDishUseCase.systemPrompt,
            );
            for (final item in reply.items) {
              final row = (await foods.fetchSearchWordResults(
                item.query,
                forResolution: true,
              )).firstOrNull;
              final n = row == null
                  ? null
                  : MealEntity.fromSpFood(row).nutriments;
              if (n == null || item.quantity == null) {
                unmatched.add(item.query);
                continue;
              }
              total.add(n, item.quantity!);
            }
          } on MealInterpreterException {
            waiting++;
            continue;
          }
          final page = photo['per_serving'] as Map;
          out.writeln(
            '| ${photo['id']} | ${photo['servings_shown'] ?? '-'} | $dish '
            '| $recipeCell '
            '| ${total.kcal.round()} (${(page['kcal'] as num).round()}) '
            '| ${total.protein.round()} / ${total.carbs.round()} / '
            '${total.fat.round()} (${(page['protein_g'] as num).round()} / '
            '${(page['carbs_g'] as num).round()} / '
            '${(page['fat_g'] as num).round()}) '
            '| ${unmatched.join('; ')} |',
          );
        }
        client.close();
        models.reportWaiting(waiting);
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

class _Totals {
  double kcal = 0, protein = 0, carbs = 0, fat = 0;

  /// [grams] of a food with [n] per 100 g. A millilitre counts as a gram.
  void add(MealNutrimentsEntity n, double grams) {
    final f = grams / 100;
    kcal += (n.energyKcal100 ?? 0) * f;
    protein += (n.proteins100 ?? 0) * f;
    carbs += (n.carbohydrates100 ?? 0) * f;
    fat += (n.fat100 ?? 0) * f;
  }
}
