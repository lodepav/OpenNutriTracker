import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:opennutritracker/core/data/data_source/remote_search_cache_data_source.dart';
import 'package:opennutritracker/core/data/dbo/meal_dbo.dart';
import 'package:opennutritracker/core/utils/ai_model_catalogue.dart';
import 'package:opennutritracker/features/meal_detail/util/hydrate_off_meal.dart';
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
  /// The app's OpenRouter list (AiModelCatalogue.openrouter).
  static const _defaultModels =
      'anthropic/claude-haiku-5.5@anthropic,'
      'anthropic/claude-sonnet-5.5@anthropic,'
      'openai/gpt-6-luna@openai,'
      'openai/gpt-6.1-terra@openai';

  /// `FORK_EVAL_MODELS=screen`: the latest cheap model from each Chinese
  /// vendor whose first-party endpoint the app could route to, against
  /// Haiku 5.5 (2026-10-28); then Mistral's four cheap vision models.
  /// Below Haiku 5.5 is not recommended; above it is noted.
  // Not Qwen 3.8 or 3.7 Flash: disqualified 2026-10-28, most reads failed
  // within the app's 20 s (3.8: 64 of 134, 3.7: 104).
  static const _screenModels =
      'bytedance-seed/seed-2.0-mini@seed#auto,'
      'z-ai/glm-5.3-flash@z-ai#auto,'
      'xiaomi/mimo-v2.6-flash@xiaomi#auto,'
      'minimax/minimax-m3.1-flash@minimax#auto,'
      // Mistral, pinned to its zero-data-retention endpoint, which settles
      // whether OpenRouter's Mistral account trains on the traffic.
      'mistralai/ministral-14b-2512@mistral/zdr,'
      'mistralai/ministral-8b-2512@mistral/zdr,'
      'mistralai/mistral-small-2603@mistral/zdr,'
      // No ZDR endpoint; Mistral serves it only from the EU one.
      'mistralai/mistral-small-3.2-24b-instruct@mistral/eu';
  // Not deepseek/deepseek-v4.1-flash-1017: its first-party endpoint trains
  // on paid traffic, so the app's `data_collection: deny` gets a 404.

  /// `FORK_EVAL_MODELS=mid`: dearer models from vendors the app could route
  /// to, against Haiku 5.5 (2026-10-28), with Sonnet 5.5, the app's
  /// OpenRouter default, as the top of the scale. Not Gemini: Google's Cloud
  /// terms §20(d) bar an app likely to be used by under-18s.
  static const _midModels =
      'openai/gpt-6-luna@openai,'
      'openai/gpt-6.1-terra@openai,'
      'x-ai/grok-4.3@xai/zdr,'
      'mistralai/mistral-medium-3-5@mistral/zdr,'
      'mistralai/mistral-large-2512@mistral/zdr,'
      'anthropic/claude-sonnet-5.5@anthropic';

  final String key = Platform.environment['FORK_EVAL_OPENROUTER_KEY'] ?? '';

  /// An Anthropic API key for `direct:<model>` specs, which call Anthropic
  /// with the app's own client (AnthropicMealItemsApi), as the app's
  /// Anthropic provider does: `direct:claude-haiku-5-5`.
  final String anthropicKey =
      Platform.environment['FORK_EVAL_ANTHROPIC_KEY'] ?? '';
  final List<String> replays = (Platform.environment['FORK_EVAL_REPLAY'] ?? '')
      .split(',')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();

  /// `FORK_EVAL_ONLY=<file>`: a retry pass, as `{spec: [read, ...]}` from
  /// fork/tools/eval_failed.py. Only those specs run, and each only the
  /// reads listed (a photo's id, `id+note`, or a typed meal's `locale|text`).
  final Map<String, Set<String>>? _only =
      switch (Platform.environment['FORK_EVAL_ONLY']) {
        final path? when path.isNotEmpty => {
          for (final MapEntry(:key, :value)
              in (jsonDecode(File(path).readAsStringSync()) as Map).entries)
            key as String: {for (final read in value as List) read as String},
        },
        _ => null,
      };

  /// Rate-limited answers each spec waited out, by [BackoffClient].
  final Map<String, int> limited = {};

  /// The tokens each live spec's answers used, from their `usage`.
  final Map<String, EvalUsage> usage = {};

  /// `FORK_EVAL_SPLIT=tune|held`: only that half of the photos (split.json),
  /// so a prompt tuned on one half is checked on the other.
  final EvalSplit? split = EvalSplit.fromEnvironment();

  /// Whether the photo [id] runs: always, without a split.
  bool inSplit(String id) => split?.has(id) ?? true;

  /// Whether [spec] runs [read]: always, outside a retry pass.
  bool runs(String spec, String read) => _only?[spec]?.contains(read) ?? true;

  /// Why the tests are skipped, or false when they run.
  Object get skip => key.isEmpty && anthropicKey.isEmpty && replays.isEmpty
      ? 'set FORK_EVAL_OPENROUTER_KEY, FORK_EVAL_ANTHROPIC_KEY (or '
            'FORK_EVAL_REPLAY) to run the model comparison'
      : false;

  List<String> get specs => replays.isNotEmpty
      ? [for (final dir in replays) 'replay:${dir.split('/').last}']
      : _only != null
      ? _only.keys.toList()
      : switch (Platform.environment['FORK_EVAL_MODELS']) {
          'screen' => _screenModels,
          'mid' => _midModels,
          final models? => models,
          // an Anthropic key alone runs the app's Anthropic default
          null when key.isEmpty && anthropicKey.isNotEmpty =>
            'direct:${AiModelCatalogue.anthropic.first.id}',
          null => _defaultModels,
        }.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();

  /// [specs] by the vendor that serves them (the pin before any `/`), in
  /// order. A live run takes the groups side by side, one call in flight per
  /// vendor, so no vendor is sent more at once than a one-model run sends it.
  List<List<String>> get groups {
    final byVendor = <String, List<String>>{};
    for (final spec in specs) {
      final pin = spec.split('#').first.split('@').skip(1).firstOrNull;
      byVendor.putIfAbsent(pin?.split('/').first ?? spec, () => []).add(spec);
    }
    return byVendor.values.toList();
  }

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
    if (spec.startsWith('direct:')) {
      final model = spec.substring('direct:'.length);
      // The app's tool call for a model it lists; unforced for one it does
      // not, as Sonnet 5.5 refuses a forced one.
      final listed = AiModelCatalogue.anthropic.where((m) => m.id == model);
      return AnthropicMealItemsApi(
        BackoffClient(
          client,
          onLimited: () => limited[spec] = (limited[spec] ?? 0) + 1,
          onAnswer: (body) => usageOf(spec).addAnswer(body),
        ),
        () => anthropicKey,
        model: model,
        timeout: BackoffClient.budget,
        toolCall: listed.isEmpty ? AiToolCall.auto : listed.first.toolCall,
      );
    }
    final [route, ...flags] = spec.split('#');
    final [model, ...rest] = route.split('@');
    final providers = rest.isEmpty || rest.first.isEmpty ? null : [rest.first];
    // The tool call the app asks this model for (S77); forced off the list.
    final listed = AiModelCatalogue.openrouter.where((m) => m.id == model);
    return OpenAiCompatibleMealItemsApi.openRouter(
      BackoffClient(
        client,
        onLimited: () => limited[spec] = (limited[spec] ?? 0) + 1,
        onAnswer: (body) => usageOf(spec).addAnswer(body),
      ),
      () => key,
      model: model,
      providers: providers,
      // BackoffClient holds each attempt to the app's limit; this one only
      // has to outlast its waits.
      timeout: BackoffClient.budget,
      toolCall: flags.contains('auto')
          ? AiToolCall.auto
          : listed.isEmpty
          ? AiToolCall.forced
          : listed.first.toolCall,
    );
  }

  EvalUsage usageOf(String spec) =>
      usage.putIfAbsent(spec, () => EvalUsage(EvalUsage.pricesOf(spec)));

  /// After a live run's report: a Usage section at the end of report.md,
  /// and usage.json beside it, which fork/tools/eval_merge.dart adds up.
  void addUsage(Directory runDir) {
    final used = {
      for (final MapEntry(:key, :value) in usage.entries)
        if (value.calls > 0) key: value,
    };
    if (used.isEmpty) return;
    runDir.createSync(recursive: true);
    final table = StringBuffer(
      '\n## Usage\n\n'
      '| Model | Answers | Input tokens | Output tokens | Cost |\n'
      '|---|---|---|---|---|\n',
    );
    for (final MapEntry(:key, :value) in used.entries) {
      final usd = value.usd;
      table.writeln(
        '| $key | ${value.calls} | ${value.input} | ${value.output} '
        '| ${usd == null ? 'price not known' : '\$${usd.toStringAsFixed(4)}'} |',
      );
    }
    File(
      '${runDir.path}/report.md',
    ).writeAsStringSync('$table', mode: FileMode.append);
    File('${runDir.path}/usage.json').writeAsStringSync(
      const JsonEncoder.withIndent(
        '  ',
      ).convert({for (final e in used.entries) e.key: e.value.toJson()}),
    );
  }

  /// Says how many requests still wait for the subagent in replay mode, or
  /// how many reads failed in a live run.
  void reportWaiting(String spec, int waiting) {
    if (limited[spec] case final n?) {
      // ignore: avoid_print
      print('$spec: waited out $n rate-limited answers');
    }
    if (usage[spec] case final used? when used.calls > 0) {
      // ignore: avoid_print
      print('$spec: ${used.summary}');
    }
    if (waiting == 0) return;
    // ignore: avoid_print
    print(
      spec.startsWith('replay:')
          ? '$spec: $waiting requests have no answer yet'
          : '$spec: $waiting reads failed (error, timeout or no model read)',
    );
  }
}

/// Waits out a 429 and asks again, so a vendor's rate limit is not scored
/// as the model's failure: 5, 15 and 45 s, or the `retry-after` asked for
/// (up to a minute). Each attempt gets the app's own 20 s, so a model too
/// slow for the app still fails here as there. Only this client's caller
/// waits: each vendor has its own and runs beside the others.
class BackoffClient extends http.BaseClient {
  static const _waits = [5, 15, 45];

  /// The longest a call through this client can take.
  static final budget =
      OpenAiCompatibleMealItemsApi.defaultTimeout * (_waits.length + 1) +
      Duration(seconds: 60 * _waits.length + 5);

  final http.Client _inner;
  final void Function() onLimited;

  /// Each answer's body, for its token usage.
  final void Function(String body)? onAnswer;

  BackoffClient(this._inner, {required this.onLimited, this.onAnswer});

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body = await request.finalize().toBytes();
    for (var attempt = 0; ; attempt++) {
      final copy = http.Request(request.method, request.url)
        ..headers.addAll(request.headers)
        ..bodyBytes = body;
      // The whole answer within the limit, as the app's post reads it.
      final response = await _inner
          .send(copy)
          .then(http.Response.fromStream)
          .timeout(OpenAiCompatibleMealItemsApi.defaultTimeout);
      if (response.statusCode != 429 || attempt == _waits.length) {
        if (response.statusCode == 200) onAnswer?.call(response.body);
        return http.StreamedResponse(
          Stream.value(response.bodyBytes),
          response.statusCode,
          headers: response.headers,
          request: request,
        );
      }
      onLimited();
      final asked = int.tryParse(response.headers['retry-after'] ?? '');
      await Future<void>.delayed(
        Duration(seconds: (asked ?? _waits[attempt]).clamp(1, 60)),
      );
    }
  }

  @override
  void close() => _inner.close();
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
/// check runs it (staple_foods_test.dart). With `FORK_EVAL_ONLINE=1` it
/// also searches Open Food Facts as the app does, and fetches a counted
/// hit's full record, so a branded product can win a row as it does on a
/// phone. No search cache: each run asks Open Food Facts afresh.
class TableOnlySearch implements SearchProductsUseCase {
  final ProductsRepository repository;
  final bool online;

  TableOnlySearch(this.repository, {bool? online})
    : online = online ?? evalSearchesOnline {
    if (this.online) _allowOffSearch();
  }

  @override
  Future<SearchProductsResult> searchOFFProductsByString(
    String searchString, {
    bool skipRemote = false,
  }) async {
    if (!online || skipRemote) {
      return SearchProductsResult(meals: const [], remoteSourceEmpty: true);
    }
    final meals = await repository.getOFFProductsByString(searchString);
    return SearchProductsResult(meals: meals, remoteSourceEmpty: meals.isEmpty);
  }

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
  Future<MealEntity?> fetchFullOffRecord(MealEntity meal) =>
      fetchDetailedOffMeal(meal, _NoSearchCache(), repository);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// What Open Food Facts' client needs in a test: a binding for the
/// locale, the app's version for its User-Agent, and the real network,
/// which the test binding stubs out.
void _allowOffSearch() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  PackageInfo.setMockInitialValues(
    appName: 'OpenBite',
    packageName: 'eval',
    version: 'eval',
    buildNumber: '0',
    buildSignature: '',
  );
}

/// `FORK_EVAL_ONLINE=1`: the evals search Open Food Facts too.
final evalSearchesOnline = Platform.environment['FORK_EVAL_ONLINE'] == '1';

class _NoSearchCache implements RemoteSearchCacheDataSource {
  @override
  MealDBO? getDetailedByBarcode(String barcode) => null;

  @override
  Future<void> cache(MealDBO meal) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Directory evalRunDir(String suffix) => Directory(
  'build/fork-eval/'
  '${DateTime.now().toIso8601String().replaceAll(':', '-')}$suffix',
);

/// The tokens a model's answers used, from each answer's `usage`: the
/// Messages API's `input_tokens` (with its cache reads and writes) and
/// `output_tokens`, or OpenRouter's `prompt_tokens` and `completion_tokens`.
class EvalUsage {
  /// Dollars per million input and output tokens, for the `direct:` models
  /// the credits plan runs (fork/eval/CREDITS_PLAN.md); others go without.
  static const _prices = {
    'claude-haiku-5-5': (input: 0.10, output: 0.50),
    'claude-sonnet-5-5': (input: 2.0, output: 10.0),
  };

  static ({double input, double output})? pricesOf(String spec) =>
      spec.startsWith('direct:') ? _prices[spec.substring(7)] : null;

  final ({double input, double output})? prices;
  int calls = 0;
  int input = 0;
  int output = 0;

  EvalUsage([this.prices]);

  /// Adds one answer; one without a readable `usage` is left out.
  void addAnswer(String body) {
    Object? usage;
    try {
      final answer = jsonDecode(body);
      if (answer is Map) usage = answer['usage'];
    } on FormatException {
      return;
    }
    if (usage is! Map) return;
    int n(String key) =>
        (usage as Map)[key] is num ? (usage[key] as num).toInt() : 0;
    calls++;
    if (usage.containsKey('input_tokens')) {
      input +=
          n('input_tokens') +
          n('cache_creation_input_tokens') +
          n('cache_read_input_tokens');
      output += n('output_tokens');
    } else {
      input += n('prompt_tokens');
      output += n('completion_tokens');
    }
  }

  /// What the tokens cost, or null for a model with no price here. Cache
  /// reads are counted at the full input price, so this is an upper bound.
  double? get usd => switch (prices) {
    final p? => (input * p.input + output * p.output) / 1e6,
    null => null,
  };

  String get summary {
    final cost = usd;
    return '$calls answers, $input tokens in, $output out'
        '${cost == null ? '' : ', \$${cost.toStringAsFixed(4)}'}';
  }

  Map<String, Object?> toJson() => {
    'calls': calls,
    'input_tokens': input,
    'output_tokens': output,
    'usd': usd,
  };
}

/// The photo test sets split in two halves (fork/eval/split.json): `tune`
/// to change a prompt against, `held` to check it on. A photo in neither
/// runs in neither.
class EvalSplit {
  static const path = 'fork/eval/split.json';

  final String half;
  final Set<String> ids;

  EvalSplit(this.half, this.ids);

  /// The half `FORK_EVAL_SPLIT` names, or null when it names none.
  static EvalSplit? fromEnvironment() {
    final half = Platform.environment['FORK_EVAL_SPLIT'];
    return half == null || half.isEmpty ? null : read(half);
  }

  static EvalSplit read(String half, [String file = path]) {
    final ids = (jsonDecode(File(file).readAsStringSync()) as Map)[half];
    if (half == 'about' || ids is! List) {
      throw ArgumentError.value(half, 'FORK_EVAL_SPLIT', 'use tune or held');
    }
    return EvalSplit(half, {for (final id in ids) id as String});
  }

  bool has(String id) => ids.contains(id);
}
