import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:opennutritracker/core/data/data_source/config_data_source.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/add_meal/data/data_sources/sp_food_data_source.dart';
import 'package:opennutritracker/features/add_meal/data/dto/sp/sp_const.dart';
import 'package:opennutritracker/features/add_meal/data/dto/sp/sp_food_dto.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_portion_entity.dart';
import 'package:opennutritracker/features/add_meal/util/backend_title.dart';
import 'package:opennutritracker/features/add_meal/util/soft_text_score.dart';

/// The fork's offline food table (D11): the open USDA and BLS tables bundled
/// as an asset, answering the three questions upstream asks its Supabase
/// backend. Rows have the backend's `food_summary` shape, so everything
/// downstream — [SpFoodDTO], `MealEntity.fromSpFood`, the ranking cut and
/// the AI resolver — runs unchanged. Built by `fork/tools/build_food_db.py`.
class LocalFoodDataSource extends SpFoodDataSource {
  static const assetPath = 'assets/fork/foods.json.gz';

  /// Rows handed to the ranking cut, as the backend hands it a hundred.
  static const candidatePoolSize = SPConst.maxNumberOfItems * 5;

  final Future<LocalFoodTable> Function() _loadTable;
  final Future<Map<String, bool>?> Function() _readToggles;
  Future<LocalFoodTable>? _table;

  LocalFoodDataSource({
    Future<LocalFoodTable> Function()? loadTable,
    Future<Map<String, bool>?> Function()? readToggles,
  }) : _loadTable = loadTable ?? _loadAsset,
       _readToggles =
           readToggles ??
           (() => locator<ConfigDataSource>().getFoodSourceToggles());

  /// Loaded on the first search and kept: about 20,000 rows, a few MB.
  Future<LocalFoodTable> get table => _table ??= _loadTable();

  static Future<LocalFoodTable> _loadAsset() async {
    final bytes = await rootBundle.load(assetPath);
    return compute(
      LocalFoodTable.fromGzip,
      bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
    );
  }

  @override
  Future<List<SpFoodDTO>> fetchSearchWordResults(
    String searchString, {
    bool forResolution = false,
  }) async {
    final toggles = await _readToggles();
    final foods = await table;
    List<SpFoodDTO> search(String query) =>
        foods.search(query, isEnabled: (source) => toggles?[source] ?? true);
    var query = searchString;
    var rows = search(query);
    // A model names foods the table's way, then adds a qualifier the table
    // may not use ("buckwheat groats, raw" against "Buckwheat groats"):
    // when nothing has every word, drop the qualifiers from the end. Only
    // for resolution; a person searching sees exactly what they typed.
    while (forResolution && rows.isEmpty && query.contains(',')) {
      query = query.substring(0, query.lastIndexOf(','));
      rows = search(query);
    }
    if (forResolution) rows = _servedNotDry(rows, query, asked: searchString);
    // The backend's own cut, reused so the resolver sees the twenty rows it
    // would see from the backend. Upstream exposes it for its tests only;
    // calling it beats a copy that drifts.
    // ignore: invalid_use_of_visible_for_testing_member
    return rankAndTruncateFoodsByName(
      rows,
      query,
      forResolution: forResolution,
    );
  }

  /// Every name in the table is English, so there is no label to localize.
  @override
  Future<Map<int, String>> fetchPortionLabels(List<int> foodIds) async =>
      const {};

  @override
  Future<Map<int, List<MealPortionEntity>>?> fetchPortions(
    List<int> foodIds,
  ) async {
    final portions = (await table).portions;
    return {for (final id in foodIds) id: ?portions[id]};
  }
}

final _stateWords = RegExp(
  r'\b(raw|dry|dried|uncooked|cooked|boiled|steamed|stewed|fried|baked)\b',
  caseSensitive: false,
);
final _cookedWords = RegExp(
  r'\b(cooked|boiled|steamed)\b',
  caseSensitive: false,
);

/// [rows] without the dry grains and pulses when [query] names the food
/// with no state and the table also has it cooked. A plate holds the
/// cooked food, but the bare name finds the dry one first: "buckwheat"
/// was 343 kcal per 100 g against 92 boiled, and "lentils", "spaghetti",
/// "bulgur" and "couscous" did the same (phase 4, a LIDO photo of boiled
/// buckwheat). A row is dry by what it holds, more than twice the energy
/// of the leanest cooked row and mostly starch, because the table does not
/// always say so ("Buckwheat"); the starch keeps raw bacon and egg yolk,
/// dense for fat. Only a cooked row named for the food itself counts
/// ("Buckwheat, boiled"), not one that holds it ("Cereals, oats, ...
/// cooked" left "oats" on a yogurt). A query that says "dry" or "raw"
/// keeps every row, even once that qualifier was dropped ([asked]).
List<SpFoodDTO> _servedNotDry(
  List<SpFoodDTO> rows,
  String query, {
  required String asked,
}) {
  if (_stateWords.hasMatch(asked)) return rows;
  final food = query.trim().toLowerCase();
  double? leanest;
  for (final row in rows) {
    final name = row.name ?? '';
    final kcal = row.energyKcal100;
    if (kcal == null ||
        !name.toLowerCase().startsWith(food) ||
        !_cookedWords.hasMatch(name)) {
      continue;
    }
    if (leanest == null || kcal < leanest) leanest = kcal;
  }
  if (leanest == null) return rows;
  final limit = 2 * leanest;
  bool dry(SpFoodDTO row) =>
      (row.energyKcal100 ?? 0) > limit && (row.carbohydrates100 ?? 0) > 50;
  return [
    for (final row in rows)
      if (!dry(row)) row,
  ];
}

/// The decoded asset: rows and their portions by food id.
class LocalFoodTable {
  final List<SpFoodDTO> foods;
  final Map<int, List<MealPortionEntity>> portions;
  final List<Set<String>> _tokens;

  LocalFoodTable(this.foods, this.portions)
    : _tokens = [for (final food in foods) tokenize(food.name)];

  static LocalFoodTable fromGzip(Uint8List bytes) =>
      fromJson(jsonDecode(utf8.decode(gzip.decode(bytes))) as Map);

  static LocalFoodTable fromJson(Map<dynamic, dynamic> json) {
    final columns = (json['columns'] as List).cast<String>();
    final foods = [
      for (final row in json['foods'] as List)
        SpFoodDTO.fromJson({
          for (var i = 0; i < columns.length; i++) columns[i]: (row as List)[i],
        }),
    ];
    final portions = {
      for (final MapEntry(:key, :value) in (json['portions'] as Map).entries)
        int.parse(key as String): [
          for (final portion in value as List)
            MealPortionEntity(
              label: portion[0] as String,
              gramWeight: (portion[1] as num).toDouble(),
              localized: false,
            ),
        ],
    };
    return LocalFoodTable(foods, portions);
  }

  /// The backend's candidate pool for [searchString]: rows whose name holds
  /// every query word, allowing for inflection (`eggs` finds "Egg"), in the
  /// backend's order — a portion first, then the title equal to the term,
  /// then the shorter name, then the id — cut to
  /// [LocalFoodDataSource.candidatePoolSize]. The backend's full-text match
  /// (`search_food_summary`) is also every word, stemmed.
  List<SpFoodDTO> search(
    String searchString, {
    required bool Function(String? source) isEnabled,
  }) {
    final query = tokenize(searchString);
    if (query.isEmpty) return const [];
    final term = searchString.trim().toLowerCase();
    final matches = <SpFoodDTO>[];
    for (var i = 0; i < foods.length; i++) {
      final food = foods[i];
      if (!isEnabled(food.source)) continue;
      if (query.every((q) => _tokens[i].any((t) => wordsAgree(q, t)))) {
        matches.add(food);
      }
    }
    int key(bool flag) => flag ? 0 : 1;
    matches.sort((a, b) {
      final byPortion = key(
        a.hasPortion == true,
      ).compareTo(key(b.hasPortion == true));
      if (byPortion != 0) return byPortion;
      final byTitle = key(_titleIs(a, term)).compareTo(key(_titleIs(b, term)));
      if (byTitle != 0) return byTitle;
      final byLength = (a.name?.length ?? 0).compareTo(b.name?.length ?? 0);
      if (byLength != 0) return byLength;
      return (a.foodId ?? 0).compareTo(b.foodId ?? 0);
    });
    return matches.take(LocalFoodDataSource.candidatePoolSize).toList();
  }

  static bool _titleIs(SpFoodDTO food, String term) =>
      deriveTitle(food.name ?? '').toLowerCase() == term;
}

/// Whether query word [q] and name word [t] are the same word up to an
/// ending: one is the other plus at most two letters (`egg`/`eggs`,
/// `potato`/`potatoes`), or both share a stem of four letters or more and
/// differ in at most two letters after it (`cheese`/`cheesy`), or `y` and
/// `ies` (`berry`/`berries`). Three shared letters are not a stem:
/// `grey` is not `green`. Recipe search uses it too (`recipe_search.dart`).
bool wordsAgree(String q, String t) {
  if (q == t) return true;
  final (shorter, longer) = q.length <= t.length ? (q, t) : (t, q);
  var shared = 0;
  while (shared < shorter.length &&
      shorter.codeUnitAt(shared) == longer.codeUnitAt(shared)) {
    shared++;
  }
  if (shared == shorter.length) {
    return shorter.length >= 3 && longer.length - shorter.length <= 2;
  }
  if (shorter.endsWith('y') &&
      longer == '${shorter.substring(0, shorter.length - 1)}ies') {
    return true;
  }
  return shared >= 4 && longer.length - shared <= 2;
}
