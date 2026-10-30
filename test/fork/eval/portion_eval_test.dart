// A photo with a short name and no weight, the way most meals are logged:
// how close the logged kcal comes to the plate's. Same photos and scoring as
// calorie_eval_test.dart (one serving with known macros), each with the note
// a user would type: the dish's name, no amount.
//
//   FORK_EVAL_REPLAY=build/fork-eval/replay/portion flutter test test/fork/eval/portion_eval_test.dart
//
// The report is written to build/fork-eval/<time>-portion/report.md.
//
// FORK_EVAL_PHOTOS=<dir>/photos.json runs another set instead: its photos in
// <dir>/photos, each with the note in its "typed" field. A set made from a
// user's own log stays under build/, out of the repo.
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

final _set = Platform.environment['FORK_EVAL_PHOTOS'];
final _photoDir = _set == null
    ? 'build/fork-eval/photos'
    : '${File(_set!).parent.path}/photos';

/// What a user would type under each photo: the name, nothing more.
const _notes = {
  'bal-cold-beet-soup': 'cold beet soup',
  'bal-chlodnik': 'chłodnik',
  'sl-buckwheat-mushrooms': 'buckwheat with mushrooms',
  'sl-stuffed-peppers': 'stuffed pepper',
  'sl-borscht': 'borscht',
  'ge-khachapuri-adjaruli': 'khachapuri',
  'ev-bolognese': 'spaghetti bolognese',
  'lv-lido-karbonade': 'pork chop',
  'ru-solyanka': 'solyanka',
  'ru-plov': 'chicken plov',
  'ru-bread-soup': 'bread soup with apples',
  'ru-mash': 'mashed potatoes',
  'ru-french-pork': 'french-style pork',
  'lv-lido-pork-cutlets': 'pork cutlets',
  'lv-lido-chicken-cutlets': 'chicken cutlets',
  'lv-lido-dill-sauce': 'dill sauce',
  'lv-lido-garlic-sauce': 'garlic sauce',
};

void main() {
  final models = EvalModels();
  final manifest =
      jsonDecode(File(_set ?? 'fork/eval/photos.json').readAsStringSync())
          as Map;
  final notes = {
    ..._notes,
    for (final photo in manifest['photos'] as List)
      if (photo['typed'] != null)
        photo['id'] as String: photo['typed'] as String,
  };
  final photos = [
    for (final photo
        in (manifest['photos'] as List).cast<Map<String, dynamic>>())
      if (notes.containsKey(photo['id'])) photo,
  ];
  final runDir = evalRunDir('-portion');
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
      '# Photo and name, no weight, to logged kcal, ${DateTime.now()}\n\n'
      'Off: |logged / label - 1|.\n\n$summary$out',
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
        final score = KcalScore();

        for (final photo in photos) {
          final file = File('$_photoDir/${photo['id']}.jpg');
          if (!file.existsSync()) continue;
          final label = ((photo['per_serving'] as Map)['kcal'] as num)
              .toDouble();
          final note = notes[photo['id']]!;
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
          score.add(kcal, label, guessed);
          out.writeln(
            '| ${photo['id']} | $note | ${kcal.round()} '
            '| ${label.round()} | ${cells.join('; ')} |',
          );
        }
        if (score.offs.isNotEmpty) summary.writeln(score.row(spec));
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
