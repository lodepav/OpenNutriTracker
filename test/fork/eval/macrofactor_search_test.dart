// Phase 4: does a food the user logs often get the right title? The foods
// come from the user's own MacroFactor log, which stays out of the repo:
// the labels are built from it into build/fork-eval/macrofactor/labels.json
// (one entry per food as a person would type it, with the title words a
// right row holds and the words it must not). Branded products are left
// out; only titles are scored, not macros.
//
// Without a model, each single food goes through the Food tab's search
// (top row, and a right row among the first five) and the resolver
// alone. With FORK_EVAL_REPLAY or a key, every food and dish is typed into
// the bulk-add screen's text path, and its first row is scored; a dish the
// table lacks is broken down (D9), which is counted, not scored.
//
// The report is written to build/fork-eval/<time>-macrofactor/report.md.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:opennutritracker/features/add_meal/data/data_sources/off_data_source.dart';
import 'package:opennutritracker/features/add_meal/data/repository/products_repository.dart';
import 'package:opennutritracker/features/add_meal/domain/usecase/resolve_parsed_meals_usecase.dart';
import 'package:opennutritracker/features/add_meal/presentation/bloc/bulk_add_bloc.dart';
import 'package:opennutritracker/features/add_meal/util/meal_text_parser.dart';
import 'package:opennutritracker/fork/food/local_food_data_source.dart';

import 'eval_model.dart';
import 'logged_kcal.dart';

const _labels = 'build/fork-eval/macrofactor/labels.json';

typedef _Food = ({
  String typed,
  bool dish,
  List<List<String>> accept,
  List<String> reject,
  int logged,
});

/// Whether [name] is a right row for [food].
bool _right(_Food food, String? name) {
  final n = (name ?? '').toLowerCase();
  if (n.isEmpty || food.reject.any(n.contains)) return false;
  return food.accept.any((parts) => parts.every(n.contains));
}

void main() {
  final file = File(_labels);
  final foods = !file.existsSync()
      ? <_Food>[]
      : [
          for (final e
              in (jsonDecode(file.readAsStringSync()) as Map)['foods'] as List)
            (
              typed: e['typed'] as String,
              dish: e['kind'] == 'dish',
              accept: [
                for (final a in e['accept'] as List) (a as List).cast<String>(),
              ],
              reject: (e['reject'] as List).cast<String>(),
              logged: e['logged'] as int,
            ),
        ];
  final skip = foods.isEmpty
      ? 'needs $_labels, built from the user\'s MacroFactor export'
      : null;
  final models = EvalModels();
  final runDir = evalRunDir('-macrofactor');
  final summary = StringBuffer();
  final rows = StringBuffer();

  late LocalFoodDataSource table;
  late ProductsRepository repository;
  late ResolveParsedMealsUseCase resolver;
  setUpAll(() async {
    if (skip != null) return;
    table = await loadFoodTable();
    repository = ProductsRepository(OFFDataSource(), table);
    resolver = ResolveParsedMealsUseCase(TableOnlySearch(repository));
    FlutterSecureStorage.setMockInitialValues({
      'AiApiKeyTag.anthropic': 'replay',
      'AiAssistEnabledTag': 'true',
      'AiTermsAcceptedTag': 'true',
    });
  });

  tearDownAll(() {
    if (rows.isEmpty) return;
    runDir.createSync(recursive: true);
    File('${runDir.path}/report.md').writeAsStringSync(
      '# MacroFactor foods to titles, ${DateTime.now()}\n\n'
      'Weighted: by how often the food is in the log.\n\n$summary\n$rows',
    );
    // ignore: avoid_print
    print('report: ${runDir.path}/report.md');
  });

  test('search and resolver, no model', () async {
    final singles = foods.where((f) => !f.dish).toList();
    var top = 0, five = 0, resolved = 0;
    var wTop = 0, wFive = 0, wResolved = 0, wAll = 0;
    rows
      ..writeln('## Search and resolver, no model\n')
      ..writeln('| Food | Logged | Search top | Right in 5 | Resolver |')
      ..writeln('|---|---|---|---|---|');
    for (final food in singles) {
      final found = await repository.getSupabaseFoodsByString(food.typed);
      final firstRight = found
          .take(5)
          .toList()
          .indexWhere((m) => _right(food, m.name));
      final pick = (await resolver.resolve([
        ParsedMealItem(query: food.typed),
      ])).single.selected;
      final isTop = firstRight == 0, inFive = firstRight >= 0;
      final isResolved = _right(food, pick?.name);
      wAll += food.logged;
      if (isTop) (top++, wTop += food.logged);
      if (inFive) (five++, wFive += food.logged);
      if (isResolved) (resolved++, wResolved += food.logged);
      rows.writeln(
        '| ${food.typed} | ${food.logged} '
        '| ${isTop ? '✓' : '✗'} ${found.firstOrNull?.name ?? '*none*'} '
        '| ${inFive ? '#${firstRight + 1}' : '✗'} '
        '| ${isResolved ? '✓' : '✗'} ${pick?.name ?? '*none*'} |',
      );
    }
    rows.writeln();
    String pct(int w) => '${(100 * w / wAll).round()}%';
    summary
      ..writeln('| Single foods (${singles.length}) | Right | Weighted |')
      ..writeln('|---|---|---|')
      ..writeln('| Search, top row | $top | ${pct(wTop)} |')
      ..writeln('| Search, in the first 5 | $five | ${pct(wFive)} |')
      ..writeln(
        '| Resolver on the typed name | $resolved | ${pct(wResolved)} |',
      )
      ..writeln();
  }, skip: skip);

  for (final spec in models.specs) {
    test(
      spec,
      () async {
        final client = http.Client();
        final api = models.api(spec, client);
        var waiting = 0;
        final right = {false: 0, true: 0}, total = {false: 0, true: 0};
        var brokenDown = 0;
        rows
          ..writeln('## AI describe, $spec\n')
          ..writeln('| Typed | Kind | Right | Rows |')
          ..writeln('|---|---|---|---|');
        for (final food in foods) {
          final bloc = evalBulkAddBloc(api, resolver);
          bloc.add(
            ParseBulkTextEvent(
              text: food.typed,
              usesImperialUnits: false,
              localeCode: 'en',
            ),
          );
          final state = await settled(bloc);
          await bloc.close();
          if (state is! BulkAddLoadedState ||
              state.source != BulkAddReadSource.model) {
            waiting++;
            continue;
          }
          final first = state.rows.firstOrNull;
          final broken = first != null && first.meal == null;
          final ok = !broken && _right(food, first?.meal?.name);
          total[food.dish] = total[food.dish]! + 1;
          if (ok) right[food.dish] = right[food.dish]! + 1;
          if (broken) brokenDown++;
          final cells = [
            for (final row in state.rows)
              '${row.resolved.parsed.query} → '
                  '${row.meal?.name ?? '*breakdown*'}',
          ];
          rows.writeln(
            '| ${food.typed} | ${food.dish ? 'dish' : 'food'} '
            '| ${broken
                ? '–'
                : ok
                ? '✓'
                : '✗'} | ${cells.join('; ')} |',
          );
        }
        rows.writeln();
        if (total.values.any((n) => n > 0)) {
          if (!summary.toString().contains('| Model |')) {
            summary
              ..writeln('| Model | AI describe, single foods | Dishes |')
              ..writeln('|---|---|---|');
          }
          summary.writeln(
            '| $spec | foods ${right[false]}/${total[false]} '
            '| dishes ${right[true]}/${total[true]}, '
            '$brokenDown broken down |',
          );
        }
        client.close();
        models.reportWaiting(spec, waiting);
      },
      timeout: const Timeout(Duration(minutes: 30)),
      skip: skip ?? models.skip,
    );
  }
}
