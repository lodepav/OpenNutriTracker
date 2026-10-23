import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:opennutritracker/features/add_meal/data/anthropic_meal_items_api.dart';
import 'package:opennutritracker/features/add_meal/data/openai_compatible_meal_items_api.dart';
import 'package:opennutritracker/features/add_meal/domain/meal_items_api.dart';
import 'package:opennutritracker/fork/dev/replay_ai.dart';
import 'package:opennutritracker/fork/food/local_food_data_source.dart';

/// The models the eval tests run, from the environment: a replay folder
/// (fork/eval/REPLAY.md) or an OpenRouter key with `model@provider` specs.
class EvalModels {
  static const _defaultModels =
      'anthropic/claude-haiku-5.5@anthropic,'
      'anthropic/claude-haiku-4.5@anthropic,'
      'openai/gpt-5.6-luna@openai';

  final String key = Platform.environment['FORK_EVAL_OPENROUTER_KEY'] ?? '';
  final String replay = Platform.environment['FORK_EVAL_REPLAY'] ?? '';

  /// Why the tests are skipped, or false when they run.
  Object get skip => key.isEmpty && replay.isEmpty
      ? 'set FORK_EVAL_OPENROUTER_KEY (or FORK_EVAL_REPLAY) to run the '
            'model comparison'
      : false;

  List<String> get specs => replay.isNotEmpty
      ? ['replay:${replay.split('/').last}']
      : (Platform.environment['FORK_EVAL_MODELS'] ?? _defaultModels)
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList();

  MealItemsApi api(String spec, http.Client client) {
    if (replay.isNotEmpty) {
      return AnthropicMealItemsApi(
        ReplayAiClient(client, () async => Directory(replay)),
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
  void reportWaiting(int waiting) {
    if (replay.isEmpty || waiting == 0) return;
    // ignore: avoid_print
    print('$waiting requests have no answer: see $replay/requests');
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
