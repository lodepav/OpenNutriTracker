// A photo set kept under build/ (D42: 51 Nutrition5k plates, weighed on a
// lab scale), read with or without its typed note.
//
//   FORK_EVAL_PHOTOS=build/n5k/set/photos.json \
//   FORK_EVAL_WITH_NOTE=1 FORK_EVAL_REPEAT=1 FORK_EVAL_IDS=a,b \
//   flutter test test/fork/eval/fresh_eval_test.dart
//
// Each photo in <dir>/photos/<id>.jpg; per_serving.kcal is the reference,
// "typed" the note. Writes build/fork-eval/<time>-fresh/kcal.json with every
// row's grams and kcal. The set is built by the scripts in
// fork/tools/exp_photo_grams/ on the branch exp/photo-grams.
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

final _env = Platform.environment;
final _set = _env['FORK_EVAL_PHOTOS'];
final _withNote = _env['FORK_EVAL_WITH_NOTE'] == '1';
final _repeat = int.tryParse(_env['FORK_EVAL_REPEAT'] ?? '') ?? 1;
final _ids = (_env['FORK_EVAL_IDS'] ?? '')
    .split(',')
    .where((s) => s.isNotEmpty)
    .toSet();

void main() {
  final models = EvalModels();
  if (_set == null) {
    test('fresh', () {}, skip: 'set FORK_EVAL_PHOTOS');
    return;
  }
  final set = _set!;
  final photoDir = '${File(set).parent.path}/photos';
  final manifest = jsonDecode(File(set).readAsStringSync()) as Map;
  final photos = [
    for (final photo
        in (manifest['photos'] as List).cast<Map<String, dynamic>>())
      if (_ids.isEmpty || _ids.contains(photo['id'])) photo,
  ];
  final runDir = evalRunDir('-fresh${_withNote ? '-note' : ''}');
  final out = StringBuffer();
  final summary = StringBuffer(KcalScore.header);
  final reads = KcalReads();

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
    File(
      '${runDir.path}/report.md',
    ).writeAsStringSync('# Fresh set, ${DateTime.now()}\n\n$summary$out');
    reads.write(runDir);
    models.addUsage(runDir);
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
          ..writeln('| Photo | Note | Logged kcal | Reference kcal | Rows |')
          ..writeln('|---|---|---|---|---|');
        final score = KcalScore();
        for (var pass = 0; pass < _repeat; pass++) {
          for (final photo in photos) {
            final file = File('$photoDir/${photo['id']}.jpg');
            if (!file.existsSync()) continue;
            final label = ((photo['per_serving'] as Map)['kcal'] as num)
                .toDouble();
            final note = _withNote ? photo['typed'] as String? : null;
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
            reads.add(spec, photo['id'] as String, note, kcal, label);
            out.writeln(
              '| ${photo['id']} | ${note ?? ''} | ${kcal.round()} '
              '| ${label.round()} | ${cells.join('; ')} |',
            );
          }
        }
        if (score.offs.isNotEmpty) summary.writeln(score.row(spec));
        client.close();
        models.reportWaiting(spec, waiting);
      },
      timeout: const Timeout(Duration(minutes: 60)),
      skip: models.skip,
    );
  }
}
