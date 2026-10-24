// Phase 4's typed meals, end to end: what a typed meal logs, in kcal,
// through the bulk-add screen's own text path (BulkAddBloc, the model read,
// upstream's resolver over the bundled table, D9 breakdowns), each row at
// the amount the screen starts it at.
//
// Most meals state their amounts, so the reference is worked out from
// standard figures (USDA, the pack) and written beside each one; a
// reference for an unstated amount is a typical serving and counts for
// less. Latvian meals run in the English and the Latvian locale.
//
//   FORK_EVAL_REPLAY=build/fork-eval/replay/haiku flutter test test/fork/eval
//
// The report is written to build/fork-eval/<time>-typed/report.md.
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:opennutritracker/features/add_meal/data/data_sources/off_data_source.dart';
import 'package:opennutritracker/features/add_meal/data/repository/products_repository.dart';
import 'package:opennutritracker/features/add_meal/domain/usecase/resolve_parsed_meals_usecase.dart';
import 'package:opennutritracker/features/add_meal/presentation/bloc/bulk_add_bloc.dart';
import 'package:opennutritracker/fork/food/local_food_data_source.dart';

import 'eval_model.dart';
import 'logged_kcal.dart';

/// A typed meal, its reference kcal and how that was reached.
typedef _Meal = ({String text, bool latvian, double kcal, String basis});

const _meals = <_Meal>[
  (
    text: '2 eggs, 2 slices of rye bread with butter, coffee with milk',
    latvian: false,
    kcal: 420,
    basis: 'eggs 2×50 g 143; rye 2×32 g 166; butter 2×7 g 100; coffee 15',
  ),
  (
    text: '2 olas, 2 šķēles rupjmaizes ar sviestu, kafija ar pienu',
    latvian: true,
    kcal: 420,
    basis: 'as the English line',
  ),
  (
    text: '200 g griķu ar 150 g vistas krūtiņas',
    latvian: true,
    kcal: 430,
    basis: 'boiled buckwheat 200 g 184; cooked chicken breast 150 g 248',
  ),
  (
    text: '1 banana, 200 g greek yogurt, 30 g granola',
    latvian: false,
    kcal: 390,
    basis: 'banana 118 g 105; 2% greek yogurt 200 g 146; granola 30 g 141',
  ),
  (
    text: 'kefīrs 500 ml',
    latvian: true,
    kcal: 280,
    basis: 'kefir 2.5% about 56 per 100 ml',
  ),
  (
    text: '200 g biezpiena ar 2 ēdamkarotēm skābā krējuma',
    latvian: true,
    kcal: 220,
    basis: 'quark 9% 200 g 160 (lean 140, fat 230); sour cream 2×15 g 60',
  ),
  (
    text: 'a 330 ml can of coke and a cheeseburger',
    latvian: false,
    kcal: 440,
    basis: 'cola 139; fast-food cheeseburger 300',
  ),
  (
    text: '2 slices of pepperoni pizza',
    latvian: false,
    kcal: 600,
    basis: 'a 14" slice of about 110 g at 270',
  ),
  (
    text: '1 apple and 30 g almonds',
    latvian: false,
    kcal: 270,
    basis: 'apple 182 g 95; almonds 30 g 174',
  ),
  (
    text: 'omlete no 3 olām ar 30 g siera',
    latvian: true,
    kcal: 400,
    basis: 'eggs 150 g 215; cheese 30 g 120; butter for the pan 60',
  ),
  (
    text: '200 ml apelsīnu sulas',
    latvian: true,
    kcal: 90,
    basis: 'orange juice 45 per 100 ml',
  ),
  (
    text: '2 sviestmaizes ar šķiņķi un sieru',
    latvian: true,
    kcal: 440,
    basis: 'each: bread 30 g 80, butter 5 g 36, ham 20 g 25, cheese 20 g 80',
  ),
  (
    text: 'a glass of milk',
    latvian: false,
    kcal: 130,
    basis: '240 ml of 2% at 50 per 100 ml (unstated: a typical glass)',
  ),
  (text: 'alus 0.5 l', latvian: true, kcal: 215, basis: 'lager 43 per 100 ml'),
  (text: 'a Snickers bar', latvian: false, kcal: 245, basis: 'the 50 g bar'),
  (
    text: '3 pankūkas ar ievārījumu',
    latvian: true,
    kcal: 480,
    basis: 'pancakes 3×50 g 330; jam 3 tbsp 60 g 150 (unstated)',
  ),
  (
    text: 'a bowl of borscht with sour cream',
    latvian: false,
    kcal: 200,
    basis: 'borscht 300 g at 50; sour cream 15 g 30 (unstated)',
  ),
  (
    text: '150 g lasis, 200 g vārīti kartupeļi, gurķu salāti',
    latvian: true,
    kcal: 600,
    basis: 'cooked salmon 150 g 310; boiled potatoes 200 g 174; salad 100',
  ),
  (
    text: '400 g spaghetti bolognese',
    latvian: false,
    kcal: 560,
    basis: 'about 140 per 100 g',
  ),
  (
    text: 'latte',
    latvian: false,
    kcal: 190,
    basis: 'a 16 oz latte with whole milk (unstated)',
  ),
  (
    text: '2 cūkgaļas kotletes un 250 g kartupeļu biezeņa',
    latvian: true,
    kcal: 925,
    basis: "LIDO's 2 cutlets 659; mash 250 g at 106: 265",
  ),
  (
    text: 'pelēkie zirņi ar speķi, 300 g',
    latvian: true,
    kcal: 600,
    basis: 'grey peas with bacon, about 200 per 100 g',
  ),
  (
    text: '100 g ķiploku grauzdiņu',
    latvian: true,
    kcal: 480,
    basis: 'fried rye bread with garlic, about 480 per 100 g',
  ),
  (
    text: '1 big mac and medium fries',
    latvian: false,
    kcal: 880,
    basis: "McDonald's: 563 and 320",
  ),
];

void main() {
  final models = EvalModels();
  final runDir = evalRunDir('-typed');
  final out = StringBuffer();
  final summary = StringBuffer(KcalScore.header);

  late LocalFoodDataSource foods;
  late ResolveParsedMealsUseCase resolver;
  setUpAll(() async {
    foods = await loadFoodTable();
    resolver = ResolveParsedMealsUseCase(
      TableOnlySearch(ProductsRepository(OFFDataSource(), foods)),
    );
    FlutterSecureStorage.setMockInitialValues({
      'AiApiKeyTag.anthropic': 'replay',
      'AiAssistEnabledTag': 'true',
      'AiTermsAcceptedTag': 'true',
    });
  });

  tearDownAll(() {
    if (out.isEmpty) return;
    runDir.createSync(recursive: true);
    File('${runDir.path}/report.md').writeAsStringSync(
      '# Typed meal to logged kcal, ${DateTime.now()}\n\n'
      'Off: |logged / reference - 1|. The references are worked out in '
      'text_eval_test.dart. A guessed amount is a row the screen starts at '
      '100 g, or flags for the user to check.\n\n$summary$out',
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
        var waiting = 0;
        out
          ..writeln('\n## $spec\n')
          ..writeln('| Meal | Locale | Logged kcal | Reference | Rows |')
          ..writeln('|---|---|---|---|---|');
        final scores = {'en': KcalScore(), 'lv': KcalScore()};

        for (final meal in _meals) {
          for (final locale in ['en', if (meal.latvian) 'lv']) {
            final bloc = evalBulkAddBloc(api, resolver);
            bloc.add(
              ParseBulkTextEvent(
                text: meal.text,
                usesImperialUnits: false,
                localeCode: locale,
              ),
            );
            final state = await settled(bloc);
            await bloc.close();
            // A model read that failed falls back to upstream's parser; that
            // is a request still waiting for its answer here.
            if (state is! BulkAddLoadedState ||
                state.source != BulkAddReadSource.model) {
              waiting++;
              continue;
            }
            final logged = await loggedKcal(state, api, foods);
            if (logged == null) {
              waiting++;
              continue;
            }
            final (:kcal, :guessed, :cells) = logged;
            scores[locale]!.add(kcal, meal.kcal, guessed);
            out.writeln(
              '| ${meal.text} | $locale | ${kcal.round()} '
              '| ${meal.kcal.round()} | ${cells.join('; ')} |',
            );
          }
        }
        for (final MapEntry(key: locale, value: score) in scores.entries) {
          if (score.offs.isEmpty) continue;
          summary.writeln(score.row('$spec, $locale'));
        }
        client.close();
        models.reportWaiting(spec, waiting);
      },
      timeout: const Timeout(Duration(minutes: 30)),
      skip: models.skip,
    );
  }
}
