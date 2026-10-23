import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:opennutritracker/features/add_meal/data/anthropic_meal_items_api.dart';
import 'package:opennutritracker/features/add_meal/data/openai_compatible_meal_items_api.dart';
import 'package:opennutritracker/features/add_meal/domain/meal_items_api.dart';
import 'package:opennutritracker/fork/dev/replay_ai.dart';
import 'package:opennutritracker/fork/food/local_food_data_source.dart';

/// The models the eval tests run, from the environment: replay folders,
/// comma-separated, one model each (fork/eval/REPLAY.md), or an OpenRouter
/// key with `model@provider` specs.
class EvalModels {
  static const _defaultModels =
      'anthropic/claude-haiku-5.5@anthropic,'
      'anthropic/claude-haiku-4.5@anthropic,'
      'openai/gpt-5.6-luna@openai';

  final String key = Platform.environment['FORK_EVAL_OPENROUTER_KEY'] ?? '';
  final List<String> replays = (Platform.environment['FORK_EVAL_REPLAY'] ?? '')
      .split(',')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();

  /// Why the tests are skipped, or false when they run.
  Object get skip => key.isEmpty && replays.isEmpty
      ? 'set FORK_EVAL_OPENROUTER_KEY (or FORK_EVAL_REPLAY) to run the '
            'model comparison'
      : false;

  List<String> get specs => replays.isNotEmpty
      ? [for (final dir in replays) 'replay:${dir.split('/').last}']
      : (Platform.environment['FORK_EVAL_MODELS'] ?? _defaultModels)
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList();

  MealItemsApi api(String spec, http.Client client) {
    if (spec.startsWith('replay:')) {
      final dir = replays.firstWhere(
        (d) => spec == 'replay:${d.split('/').last}',
      );
      return AnthropicMealItemsApi(
        ReplayAiClient(client, () async => Directory(dir)),
        () => 'replay',
      );
    }
    final [model, ...rest] = spec.split('@');
    final providers = rest.isEmpty || rest.first.isEmpty ? null : [rest.first];
    return OpenAiCompatibleMealItemsApi.openRouter(
      client,
      () => key,
      model: model,
      providers: providers,
      timeout: const Duration(seconds: 90),
    );
  }

  /// Says how many requests still wait for the subagent, in replay mode.
  void reportWaiting(String spec, int waiting) {
    if (!spec.startsWith('replay:') || waiting == 0) return;
    // ignore: avoid_print
    print('$spec: $waiting requests have no answer yet');
  }
}

/// The bundled food table, as the app searches it.
Future<LocalFoodDataSource> loadFoodTable() async {
  final table = LocalFoodTable.fromGzip(
    await File(LocalFoodDataSource.assetPath).readAsBytes(),
  );
  return LocalFoodDataSource(
    loadTable: () async => table,
    readToggles: () async => null,
  );
}

Directory evalRunDir(String suffix) => Directory(
  'build/fork-eval/'
  '${DateTime.now().toIso8601String().replaceAll(':', '-')}$suffix',
);
