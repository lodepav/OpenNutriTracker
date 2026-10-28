import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:opennutritracker/core/utils/ai_model_catalogue.dart';
import 'package:opennutritracker/features/add_meal/data/anthropic_meal_items_api.dart';
import 'package:opennutritracker/features/add_meal/data/openai_compatible_meal_items_api.dart';
import 'package:opennutritracker/features/add_meal/data/data_sources/off_data_source.dart';
import 'package:opennutritracker/features/add_meal/data/repository/products_repository.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/meal_items_api.dart';
import 'package:opennutritracker/features/add_meal/domain/usecase/resolve_parsed_meals_usecase.dart';
import 'package:opennutritracker/features/add_meal/domain/usecase/search_products_usecase.dart';
import 'package:opennutritracker/features/add_meal/util/meal_text_parser.dart';
import 'package:opennutritracker/fork/dev/replay_ai.dart';
import 'package:opennutritracker/fork/food/local_food_data_source.dart';

/// The models the eval tests run, from the environment: replay folders,
/// comma-separated, one model each (fork/eval/REPLAY.md), or an OpenRouter
/// key with `model@provider` specs. `#auto` after a spec asks for the tool
/// call unforced, for a model whose endpoints take no forced one.
class EvalModels {
  static const _defaultModels =
      'anthropic/claude-haiku-5.5@anthropic,'
      'openai/gpt-5.6-luna@openai';

  /// `FORK_EVAL_MODELS=screen`: the latest cheap model from each Chinese
  /// vendor whose first-party endpoint the app could route to, against
  /// Haiku 5.5 (2026-10-28), and Qwen 3.7 Flash, the cheapest capable one.
  /// Below Haiku 5.5 is not recommended; above it is noted.
  static const _screenModels =
      'qwen/qwen3.8-flash@alibaba#auto,'
      'qwen/qwen3.7-flash@alibaba#auto,'
      'bytedance-seed/seed-2.0-mini@seed#auto,'
      'z-ai/glm-5.3-flash@z-ai#auto,'
      'xiaomi/mimo-v2.6-flash@xiaomi#auto';
  // Not deepseek/deepseek-v4.1-flash-1017: its first-party endpoint trains
  // on paid traffic, so the app's `data_collection: deny` gets a 404.

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
      : switch (Platform.environment['FORK_EVAL_MODELS']) {
          'screen' => _screenModels,
          final models? => models,
          null => _defaultModels,
        }.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();

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
    final [route, ...flags] = spec.split('#');
    final [model, ...rest] = route.split('@');
    final providers = rest.isEmpty || rest.first.isEmpty ? null : [rest.first];
    // The tool call the app asks this model for (S77); forced off the list.
    final listed = AiModelCatalogue.openrouter.where((m) => m.id == model);
    return OpenAiCompatibleMealItemsApi.openRouter(
      client,
      () => key,
      model: model,
      providers: providers,
      timeout: const Duration(seconds: 90),
      toolCall: flags.contains('auto')
          ? AiToolCall.auto
          : listed.isEmpty
          ? AiToolCall.forced
          : listed.first.toolCall,
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

/// The table row the app's resolver picks for [query], or null when none
/// clears its confidence floor: `ResolveParsedMealsUseCase` itself, over
/// the table with its portions as `ProductsRepository` serves it, without
/// Open Food Facts, which a breakdown passes over for a table row anyway
/// (`preferTableRow`).
Future<MealEntity?> tableMatch(LocalFoodDataSource foods, String query) async {
  final resolver = ResolveParsedMealsUseCase(
    TableOnlySearch(ProductsRepository(OFFDataSource(), foods)),
  );
  final resolved = await resolver.resolve([ParsedMealItem(query: query)]);
  return resolved.single.selected;
}

/// Upstream's search over the bundled table alone, as phase 1b's staple
/// check runs it (staple_foods_test.dart).
class TableOnlySearch implements SearchProductsUseCase {
  final ProductsRepository repository;

  TableOnlySearch(this.repository);

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

Directory evalRunDir(String suffix) => Directory(
  'build/fork-eval/'
  '${DateTime.now().toIso8601String().replaceAll(':', '-')}$suffix',
);
