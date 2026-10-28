// Phase 4's dish checks, beside the photo test and with the same models
// (eval_model.dart):
//
// - Photo -> breakdown: each test photo's dish, as the model named it, is
//   broken into ingredients as the app does it (BreakDownDishUseCase, sent
//   with the photo and the count the read gave), each ingredient resolved
//   over the bundled table, and the total set against the recipe page's
//   per-serving macros.
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
import 'package:opennutritracker/features/add_meal/data/data_sources/off_data_source.dart';
import 'package:opennutritracker/features/add_meal/data/model_meal_photo_interpreter.dart';
import 'package:opennutritracker/features/add_meal/data/model_meal_text_interpreter.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/meal_photo_interpreter.dart';
import 'package:opennutritracker/features/add_meal/data/repository/products_repository.dart';
import 'package:opennutritracker/features/add_meal/domain/usecase/resolve_parsed_meals_usecase.dart';
import 'package:opennutritracker/features/add_meal/util/meal_text_parser.dart';
import 'package:opennutritracker/fork/dish/recipe_search.dart';
import 'package:opennutritracker/fork/dish/starter_recipes.dart';
import 'package:opennutritracker/fork/food/local_food_data_source.dart';

import 'eval_model.dart';
import 'logged_kcal.dart';

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
  'sklandu rausi': 'Sklandu rauši (sklandrausis)',
  'sklandrausis': 'Sklandu rauši (sklandrausis)',
  '2 sklandrauši': 'Sklandu rauši (sklandrausis)',
};

/// Photos of dishes that have a saved recipe, by that recipe.
const _photographed = {
  'ge-khachapuri-adjaruli': 'Adjarian khachapuri',
  'ge-khachapuri': 'Adjarian khachapuri',
  'sl-pelmeni': 'Pelmeni',
  'lv-sklandrausis': 'Sklandu rauši (sklandrausis)',
  'lv-lido-grey-peas': 'Grey peas with bacon',
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
  final out = StringBuffer();
  final summary = StringBuffer(
    '| Model | Typed finds recipe | Photo finds recipe '
    '| kcal off, one-serving photos (median) | Ingredients unmatched |\n'
    '|---|---|---|---|---|\n',
  );

  late LocalFoodDataSource foods;
  setUpAll(() async => foods = await loadFoodTable());

  tearDownAll(() {
    if (out.length < 40) return;
    runDir.createSync(recursive: true);
    File(
      '${runDir.path}/report.md',
    ).writeAsStringSync('# Dish checks, ${DateTime.now()}\n\n$summary$out');
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
        final breakDown = evalBreakDown(
          api,
          ResolveParsedMealsUseCase(
            TableOnlySearch(ProductsRepository(OFFDataSource(), foods)),
          ),
        );
        final textReader = ModelMealTextInterpreter(api);
        var waiting = 0;
        out.writeln('\n## $spec\n');
        var typedOk = 0, photoOk = 0, photoRecipes = 0, unmatchedAll = 0;
        final rows = <String, String>{};
        final kcalOff = <double>[];

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
          if (found == expected) typedOk++;
          out.writeln(
            '| $typed | ${names.join('; ')} | ${found ?? '—'} '
            '| ${found == expected ? '✓' : '✗ $expected'} |',
          );
        }

        out
          ..writeln('\n### Photo → breakdown, the portion shown\n')
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
          // A set meal is several dishes, not one to break down.
          if (!file.existsSync() || photo['parts'] != null) continue;
          final mealPhoto = MealPhoto(
            bytes: file.readAsBytesSync(),
            mediaType: 'image/jpeg',
          );
          final List<ParsedMealItem> items;
          try {
            items = (await photoReader.interpret(
              mealPhoto,
              localeCode: 'en',
            )).items;
          } on MealInterpreterException {
            waiting++;
            continue;
          }
          final expected = (photo['expect_any'] as List).cast<String>();
          final item =
              items
                  .where(
                    (i) =>
                        expected.any((w) => i.query.toLowerCase().contains(w)),
                  )
                  .firstOrNull ??
              items.firstOrNull;
          if (item == null) continue;
          final dish = item.query;
          final recipe = _photographed[photo['id']];
          final found = recipeFor(dish);
          if (recipe != null) {
            photoRecipes++;
            if (found == recipe) photoOk++;
          }
          final recipeCell = recipe == null
              ? (found ?? '')
              : found == recipe
              ? '✓ $found'
              : '✗ ${found ?? 'none'}, wanted $recipe';

          final total = _Totals();
          final unmatched = <String>[];
          try {
            // A photo's count is the row's stated amount (statedAmount).
            final broken = await breakDown(
              dish,
              amount: switch (item.quantity) {
                null => null,
                final q when q == q.roundToDouble() => '${q.round()}',
                final q => '$q',
              },
              photo: mealPhoto,
            );
            for (final ingredient in broken!.ingredients) {
              final query = ingredient.parsed.query;
              final quantity = ingredient.parsed.quantity;
              final n = ingredient.selected?.nutriments;
              rows[query] = ingredient.selected?.name ?? '*none*';
              if (n == null || quantity == null) {
                unmatched.add(query);
                continue;
              }
              total.add(n, quantity);
            }
          } on MealInterpreterException {
            waiting++;
            continue;
          }
          // LIDO's restaurant dishes come with no macros (photos.json).
          final page = photo['per_serving'] as Map?;
          String pageOf(String key) =>
              page == null ? '-' : '${(page[key] as num).round()}';
          unmatchedAll += unmatched.length;
          if (page != null && photo['servings_shown'] == 1) {
            kcalOff.add((total.kcal / (page['kcal'] as num) - 1).abs());
          }
          out.writeln(
            '| ${photo['id']} | ${photo['servings_shown'] ?? '-'} | $dish '
            '| $recipeCell '
            '| ${total.kcal.round()} (${pageOf('kcal')}) '
            '| ${total.protein.round()} / ${total.carbs.round()} / '
            '${total.fat.round()} (${pageOf('protein_g')} / '
            '${pageOf('carbs_g')} / ${pageOf('fat_g')}) '
            '| ${unmatched.join('; ')} |',
          );
        }
        out.writeln('\n### Ingredient → table row\n');
        for (final MapEntry(:key, :value) in rows.entries) {
          out.writeln('- $key → $value');
        }
        kcalOff.sort();
        summary.writeln(
          '| $spec | $typedOk/${_typed.length} | $photoOk/$photoRecipes '
          '| ${kcalOff.isEmpty ? '-' : '${(kcalOff[kcalOff.length ~/ 2] * 100).round()}%'} '
          '| $unmatchedAll |',
        );
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
