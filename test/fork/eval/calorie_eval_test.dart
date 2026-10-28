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
import 'package:opennutritracker/features/add_meal/data/data_sources/off_data_source.dart';
import 'package:opennutritracker/features/add_meal/data/repository/products_repository.dart';
import 'package:opennutritracker/features/add_meal/domain/meal_photo_interpreter.dart';
import 'package:opennutritracker/features/add_meal/domain/usecase/resolve_parsed_meals_usecase.dart';
import 'package:opennutritracker/features/add_meal/presentation/bloc/bulk_add_bloc.dart';
import 'package:opennutritracker/fork/food/local_food_data_source.dart';

import 'eval_model.dart';
import 'logged_kcal.dart';

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
        var waiting = 0;
        out
          ..writeln('\n## $spec\n')
          ..writeln('| Photo | Note | Logged kcal | Label kcal | Rows |')
          ..writeln('|---|---|---|---|---|');
        final scores = {'': KcalScore(), ' + note': KcalScore()};

        for (final photo in photos) {
          final file = File('$_photoDir/${photo['id']}.jpg');
          if (!file.existsSync()) continue;
          final label = ((photo['per_serving'] as Map)['kcal'] as num)
              .toDouble();
          for (final note in [null, ?photo['user_note'] as String?]) {
            final mealPhoto = MealPhoto(
              bytes: file.readAsBytesSync(),
              mediaType: 'image/jpeg',
            );
            final bloc = evalBulkAddBloc(api, resolver);
            bloc.add(
              ReadMealPhotoEvent(
                photo: mealPhoto,
                usesImperialUnits: false,
                localeCode: 'en',
                note: note,
              ),
            );
            final state = await settled(bloc);
            if (state is BulkAddPhotoErrorState &&
                state.error != BulkAddPhotoError.transient) {
              fail('${photo['id']}: ${state.error}');
            }
            await bloc.close();
            if (state is! BulkAddLoadedState || state.rows.isEmpty) {
              waiting++;
              continue;
            }
            final logged = await loggedKcal(
              state,
              api,
              foods,
              resolver,
              photo: mealPhoto,
            );
            if (logged == null) {
              waiting++;
              continue;
            }
            final (:kcal, :guessed, :cells) = logged;
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
