// Phase 4's end-to-end check: what a photo logs, in kcal, against what the
// plate holds. The photo goes through the app's own bulk-add screen logic
// (BulkAddBloc, upstream's resolver over the bundled table), and every row is
// taken at the amount the screen starts it at, as a user who accepts the
// rows would log it. A dish the table does not have is broken down (D9), one
// serving, as the app does, whatever count the model gave the dish.
//
// Only the photos of one serving with known macros count: LIDO's packs at
// their label (exact) and the recipe pages' one-serving photos (the page's
// serving, which the photo may not match). A photo with a `user_note` runs
// with the note too.
//
//   FORK_EVAL_REPLAY=build/fork-eval/replay/opus flutter test test/fork/eval
//
// The report is written to build/fork-eval/<time>-kcal/report.md.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:opennutritracker/core/utils/ai_credential_storage.dart';
import 'package:opennutritracker/features/add_meal/data/data_sources/off_data_source.dart';
import 'package:opennutritracker/features/add_meal/data/model_meal_photo_interpreter.dart';
import 'package:opennutritracker/features/add_meal/data/model_meal_text_interpreter.dart';
import 'package:opennutritracker/features/add_meal/data/repository/products_repository.dart';
import 'package:opennutritracker/features/add_meal/domain/meal_items_api.dart';
import 'package:opennutritracker/features/add_meal/domain/meal_photo_interpreter.dart';
import 'package:opennutritracker/features/add_meal/domain/usecase/read_meal_photo_usecase.dart';
import 'package:opennutritracker/features/add_meal/domain/usecase/read_meal_text_usecase.dart';
import 'package:opennutritracker/features/add_meal/domain/usecase/resolve_parsed_meals_usecase.dart';
import 'package:opennutritracker/features/add_meal/domain/usecase/search_products_usecase.dart';
import 'package:opennutritracker/features/add_meal/presentation/bloc/bulk_add_bloc.dart';
import 'package:opennutritracker/features/meal_detail/util/meal_quantity_converter.dart';
import 'package:opennutritracker/fork/dish/break_down_dish_usecase.dart';
import 'package:opennutritracker/fork/food/local_food_data_source.dart';

import 'eval_model.dart';

const _photoDir = 'build/fork-eval/photos';

void main() {
  final models = EvalModels();
  final manifest =
      jsonDecode(File('fork/eval/photos.json').readAsStringSync()) as Map;
  final photos = [
    for (final photo
        in (manifest['photos'] as List).cast<Map<String, dynamic>>())
      if (photo['servings_shown'] == 1 && photo['per_serving'] != null) photo,
  ];
  final runDir = evalRunDir('-kcal');
  final out = StringBuffer();
  final summary = StringBuffer(
    '| Model | Photos | Within 25% | Median off | Logged / label, total '
    '| Rows at a guessed amount |\n'
    '|---|---|---|---|---|---|\n',
  );

  late LocalFoodDataSource foods;
  late ResolveParsedMealsUseCase resolver;
  setUpAll(() async {
    foods = await loadFoodTable();
    resolver = ResolveParsedMealsUseCase(
      _TableOnlySearch(ProductsRepository(OFFDataSource(), foods)),
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
      '# Photo to logged kcal, ${DateTime.now()}\n\n'
      'Off: |logged / label - 1|. A guessed amount is a row the screen '
      'starts at 100 g, or flags for the user to check.\n\n$summary$out',
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
        final credentials = AiCredentialStorage();
        // A bloc per photo: one that loaded the same rows twice would not
        // emit the second time.
        BulkAddBloc newBloc() => BulkAddBloc(
          resolver,
          ReadMealTextUseCase(
            credentials,
            (_) => ModelMealTextInterpreter(api),
          ),
          ReadMealPhotoUseCase(
            credentials,
            (_) => ModelMealPhotoInterpreter(api),
          ),
        );
        var waiting = 0;
        out
          ..writeln('\n## $spec\n')
          ..writeln('| Photo | Note | Logged kcal | Label kcal | Rows |')
          ..writeln('|---|---|---|---|---|');
        final scores = <String, _Score>{'': _Score(), ' + note': _Score()};

        for (final photo in photos) {
          final file = File('$_photoDir/${photo['id']}.jpg');
          if (!file.existsSync()) continue;
          final label = ((photo['per_serving'] as Map)['kcal'] as num)
              .toDouble();
          for (final note in [null, ?photo['user_note'] as String?]) {
            final bloc = newBloc();
            bloc.add(
              ReadMealPhotoEvent(
                photo: MealPhoto(
                  bytes: file.readAsBytesSync(),
                  mediaType: 'image/jpeg',
                ),
                usesImperialUnits: false,
                localeCode: 'en',
                note: note,
              ),
            );
            final state = await bloc.stream
                .firstWhere(
                  (s) =>
                      s is BulkAddLoadedState ||
                      s is BulkAddErrorState ||
                      s is BulkAddPhotoErrorState,
                )
                .timeout(const Duration(seconds: 30));
            if (state is BulkAddPhotoErrorState &&
                state.error != BulkAddPhotoError.transient) {
              fail('${photo['id']}: ${state.error}');
            }
            await bloc.close();
            if (state is! BulkAddLoadedState || state.rows.isEmpty) {
              waiting++;
              continue;
            }
            var kcal = 0.0;
            var guessed = 0;
            final cells = <String>[];
            var breakdownWaiting = false;
            for (final row in state.rows) {
              final meal = row.meal;
              if (meal == null) {
                final dish = row.resolved.parsed;
                final broken = await _breakDown(api, foods, dish.query);
                if (broken == null) {
                  breakdownWaiting = true;
                  break;
                }
                kcal += broken;
                cells.add(
                  '${dish.quantity == null ? '' : '${_n(dish.quantity!)}× '}'
                  '${dish.query} → breakdown ${broken.round()}',
                );
                continue;
              }
              final amount =
                  double.tryParse(row.amountText.replaceAll(',', '.')) ?? 0;
              final rowKcal =
                  kcalForQuantity(amount, row.effectiveUnit, meal) ?? 0;
              final isGuess =
                  row.amountNeedsCheck ||
                  (row.resolved.parsed.quantity == null &&
                      meal.servingQuantity == null);
              if (isGuess) guessed++;
              kcal += rowKcal;
              cells.add(
                '${row.resolved.parsed.query} → ${meal.name} '
                '${_n(amount)} ${_unitName(row.effectiveUnit)}'
                '${isGuess ? ' (guess)' : ''} ${rowKcal.round()}',
              );
            }
            if (breakdownWaiting) {
              waiting++;
              continue;
            }
            scores[note == null ? '' : ' + note']!.add(kcal, label, guessed);
            out.writeln(
              '| ${photo['id']} | ${note ?? ''} | ${kcal.round()} '
              '| ${label.round()} | ${cells.join('; ')} |',
            );
          }
        }
        for (final MapEntry(key: suffix, value: score) in scores.entries) {
          if (score.offs.isEmpty) continue;
          summary.writeln(score.row('$spec$suffix'));
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

/// One serving of [dish] broken down by the fork's prompt, in kcal, or null
/// while the answer is not in yet.
Future<double?> _breakDown(
  MealItemsApi api,
  LocalFoodDataSource foods,
  String dish,
) async {
  try {
    final reply = await api.requestItems(
      content: MealTextContent(BreakDownDishUseCase.contentFor(dish)),
      system: BreakDownDishUseCase.systemPrompt,
    );
    var kcal = 0.0;
    for (final item in reply.items) {
      final row = await tableMatch(foods, item.query);
      final per100 = row?.nutriments.energyKcal100;
      if (per100 == null || item.quantity == null) continue;
      kcal += per100 * item.quantity! / 100;
    }
    return kcal;
  } on MealInterpreterException {
    return null;
  }
}

String _n(double v) =>
    v == v.roundToDouble() ? '${v.round()}' : v.toStringAsFixed(1);

String _unitName(String unit) => unit.split('.').last;

class _Score {
  final offs = <double>[];
  var logged = 0.0, label = 0.0;
  var guessed = 0;

  void add(double kcal, double labelKcal, int guessedRows) {
    offs.add((kcal / labelKcal - 1).abs());
    logged += kcal;
    label += labelKcal;
    guessed += guessedRows;
  }

  String row(String name) {
    final sorted = [...offs]..sort();
    return '| $name | ${offs.length} '
        '| ${offs.where((o) => o <= 0.25).length}/${offs.length} '
        '| ${(sorted[sorted.length ~/ 2] * 100).round()}% '
        '| ${(logged / label * 100).round()}% | $guessed |';
  }
}

/// Upstream's search over the bundled table alone, as phase 1b's staple
/// check runs it (staple_foods_test.dart).
class _TableOnlySearch implements SearchProductsUseCase {
  final ProductsRepository repository;

  _TableOnlySearch(this.repository);

  @override
  Future<SearchProductsResult> searchOFFProductsByString(
    String searchString, {
    bool skipRemote = false,
  }) async => SearchProductsResult(meals: const [], remoteSourceEmpty: true);

  @override
  Future<SearchProductsResult> searchFDCFoodByString(
    String searchString, {
    bool skipRemote = false,
    bool forResolution = false,
  }) async => SearchProductsResult(
    meals: await repository.getSupabaseFoodsByString(
      searchString,
      forResolution: forResolution,
    ),
    remoteSourceEmpty: false,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
