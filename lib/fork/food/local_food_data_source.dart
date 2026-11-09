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
import 'package:opennutritracker/fork/food/dish_serving.dart';
import 'package:opennutritracker/fork/food/everyday_row.dart';
import 'package:opennutritracker/fork/food/unasked_variant.dart';
import 'package:opennutritracker/fork/food/unspecified_row.dart';

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
    // A model explains a name in brackets with words the row need not hold
    // ("cold beet soup (chilled borscht with kefir or yogurt)"): when
    // nothing has every word, the name before them.
    if (forResolution && rows.isEmpty && _bracketed.hasMatch(query)) {
      final plain = query.replaceAll(_bracketed, ' ').trim();
      if (plain.isNotEmpty) {
        final found = search(plain);
        if (found.isNotEmpty) {
          query = plain;
          rows = found;
        }
      }
    }
    // A model names foods the table's way, then adds a qualifier the table
    // may not use ("buckwheat groats, raw" against "Buckwheat groats"):
    // when nothing has every word, drop the qualifiers from the end. Only
    // for resolution; a person searching sees exactly what they typed.
    while (forResolution && rows.isEmpty && query.contains(',')) {
      query = query.substring(0, query.lastIndexOf(','));
      rows = search(query);
    }
    // Then a dish name with words the table does not use ("blueberry
    // cheesecake", "rice with herbs"): the nearest food it names.
    if (forResolution && rows.isEmpty) {
      // a model's qualifiers after a comma were the food's, not its kind
      // and a dish ("spaghetti bolognese" is no sauce) or a food cooked a
      // way the plain row is not ("sautéed mushrooms" are not raw ones)
      // keeps its words, to be broken down (D9)
      final lastAlone =
          !searchString.contains(',') &&
          !isMainDish(searchString) &&
          !_madeAWay.hasMatch(searchString);
      for (final shorter in fewerWords(query, lastAlone: lastAlone)) {
        rows = [
          for (final row in search(shorter))
            if (_namedFor(row, shorter)) row,
        ];
        if (rows.isNotEmpty) {
          query = shorter;
          break;
        }
      }
    }
    // A person's search names the food the way MacroFactor or a label
    // does, with words no row uses: "peach, fresh", "bulgur, home cooked",
    // "basmati rice, cooked in salted water". Without them first, before
    // the most-words match, which took "fresh" for the food and listed
    // queso fresco, basil and thyme on "peach, fresh".
    if (!forResolution && rows.isEmpty) {
      final plain = withoutDescribing(query);
      if (plain.isNotEmpty && plain != query) {
        rows = search(plain);
        if (rows.isNotEmpty) query = plain;
      }
    }
    // A person's search with a word no row has ("cherry tomatoes", "uht
    // milk") showed nothing; it shows the rows with the most of its words.
    if (!forResolution && rows.isEmpty) {
      rows = foods.searchMostWords(
        query,
        isEnabled: (source) => toggles?[source] ?? true,
      );
    }
    if (forResolution) rows = _servedNotDry(rows, query, asked: searchString);
    // The backend's own cut, reused so the resolver sees the twenty rows it
    // would see from the backend. Upstream exposes it for its tests only;
    // calling it beats a copy that drifts.
    // ignore: invalid_use_of_visible_for_testing_member
    final ranked = rankAndTruncateFoodsByName(
      rows,
      query,
      forResolution: forResolution,
    );
    // The row the name means, whether or not the search found it (S75).
    final everydayName = everydayRowName(searchString);
    final everyday = everydayName == null
        ? null
        : foods.named(
            everydayName,
            isEnabled: (source) => toggles?[source] ?? true,
          );
    if (forResolution) {
      return [
        ...ranked,
        ..._unspecifiedCut(rows, ranked, query),
        if (everyday != null && !ranked.any((row) => identical(row, everyday)))
          everyday,
      ];
    }
    // The Food tab lists a row the person did not mean after the plain
    // rows (see [listedAfter]), and the row the name means first.
    final after = listedAfter(ranked, query);
    return [
      ?everyday,
      for (final row in ranked)
        if (!after.contains(row) && !identical(row, everyday)) row,
      for (final row in ranked)
        if (after.contains(row) && !identical(row, everyday)) row,
    ];
  }

  /// The unspecified rows (NFS, "NS as to") the cut left out, most
  /// unspecified first, for the resolver to weigh (S73). The cut keeps the
  /// shortest twenty of a tie, and on "chicken" all twenty are short
  /// parts: "Chicken, back", "Chicken, tail".
  static Iterable<SpFoodDTO> _unspecifiedCut(
    List<SpFoodDTO> rows,
    List<SpFoodDTO> ranked,
    String query,
  ) {
    final kept = Set<SpFoodDTO>.identity()..addAll(ranked);
    final left = [
      for (final row in rows)
        if (unspecifiedMarks(row.name, query) > 0 && !kept.contains(row)) row,
    ];
    mergeSort(
      left,
      compare: (a, b) => unspecifiedMarks(
        b.name,
        query,
      ).compareTo(unspecifiedMarks(a.name, query)),
    );
    return left.take(5);
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

/// Words that say how a food was had or bought rather than which food it
/// is. MacroFactor and labels add them ("Plum, fresh", "Bulgur, home
/// cooked"); the table's rows seldom do, or for another food ("Cheese,
/// fresh").
const describingWords = {
  'fresh',
  'raw',
  'plain',
  'whole',
  'organic',
  'natural',
  'home',
  'homemade',
};

final _inWater = RegExp(r'\bin\s+(un)?salted\s+water\b', caseSensitive: false);

/// [query] without its [describingWords] and a cooking water ("cooked in
/// salted water"), its words joined by spaces.
String withoutDescribing(String query) => nameWords(
  query.replaceAll(_inWater, ' '),
).where((w) => !describingWords.contains(w)).join(' ');

/// Foods a plate holds cooked, whose dry row a bare name lists after the
/// cooked one ("egg noodles" listed "Noodles, egg, dry" at 384 kcal first,
/// against 138 cooked). Not oats, weighed dry for porridge; porridge itself
/// is the cooked dish, and its dry mixes are 350 kcal per 100 g.
const eatenCooked = {
  'porridge',
  'rice',
  'longgrain',
  'mediumgrain',
  'pasta',
  'noodle',
  'noodles',
  'spaghetti',
  'macaroni',
  'buckwheat',
  'bulgur',
  'couscous',
  'quinoa',
  'lentil',
  'lentils',
  'barley',
  'millet',
};

/// A form of a food the name did not ask for: "carrot" listed "Carrot,
/// dehydrated" first, "white rice" the glutinous rice. Not "dry roasted",
/// a way of roasting nuts.
final _unaskedForm = RegExp(
  r'\b(dried|dehydrated|glutinous|dry(?!\s+roasted))\b',
  caseSensitive: false,
);

/// Words after which a row's words are what it is made with: "Rice
/// pudding ..., raisins and pistachios", "Sole, fried in butter".
const _madeWith = {'with', 'in', 'and'};

/// The rows of [rows] the Food tab lists after the others for a person's
/// [query]: a variant not named (S70, [unaskedVariant]); a form not named
/// ([_unaskedForm]); a food eaten cooked, dry, when the name says no
/// state; and a row holding [query]'s words only as what it is made with,
/// as "pistachios" listed a rice pudding first. One before is enough:
/// "salted pumpkin seeds" are the seeds "with salt added".
Set<SpFoodDTO> listedAfter(List<SpFoodDTO> rows, String query) {
  final asked = query.toLowerCase();
  final content = [
    for (final w in nameWords(query))
      if (!describingWords.contains(w) && !_madeWith.contains(w)) spelling(w),
  ];
  double? leanestCooked;
  if (!_stateWords.hasMatch(asked) &&
      content.isNotEmpty &&
      eatenCooked.contains(content.last)) {
    for (final row in rows) {
      final kcal = row.energyKcal100;
      if (kcal != null &&
          _cookedWords.hasMatch(row.name ?? '') &&
          (leanestCooked == null || kcal < leanestCooked)) {
        leanestCooked = kcal;
      }
    }
  }
  bool unaskedForm(String name) {
    final form = _unaskedForm.firstMatch(name);
    return form != null && !asked.contains(form[1]!.toLowerCase());
  }

  bool dry(SpFoodDTO row) =>
      leanestCooked != null &&
      (row.energyKcal100 ?? 0) > 2 * leanestCooked &&
      (row.carbohydrates100 ?? 0) > 50;
  // A query that names what the food is made with ("potatoes boiled
  // without skin with salt") means the rows that say so.
  final namesMadeWith = nameWords(query).any(_madeWith.contains);
  bool onlyMadeWith(String name) {
    if (namesMadeWith || content.isEmpty) return false;
    final words = nameWords(name);
    final joint = words.indexWhere(_madeWith.contains);
    if (joint < 0) return false;
    return content.every(
      (q) => words.indexWhere((w) => wordsAgree(q, w)) > joint,
    );
  }

  return Set.identity()..addAll([
    for (final row in rows)
      if (unaskedVariant(row.name, query) > 0 ||
          unaskedForm(row.name ?? '') ||
          dry(row) ||
          onlyMadeWith(row.name ?? ''))
        row,
  ]);
}

final _joiner = RegExp(r'\s+(with|in|and|on|ar)\s+', caseSensitive: false);

/// Shorter forms of [query] to try, nearest first: without what follows
/// "with", "in", "and" or "on" (Latvian "ar"), then without its first
/// words one at a time. An English or Latvian dish name puts the food last
/// and its kind before it: "Caesar salad with bacon" is a Caesar salad,
/// "chicken rice pilaf" a rice pilaf. Each keeps two words at least: one
/// word alone is too broad to stand for the dish ("salad", "rice",
/// "chicken"), and a dish the table cannot name is broken down instead (D9).
/// Last, the last word alone when it is a food, not a dish ([_dishHeads]),
/// unless not [lastAlone].
/// A bracketed part of a name: "(chilled borscht)".
final _bracketed = RegExp(r'\s*\([^)]*\)?');

List<String> fewerWords(String query, {bool lastAlone = true}) {
  final shorter = <String>[];
  var words = query.trim().split(RegExp(r'\s+'));
  final joined = _joiner.firstMatch(query.trim());
  if (joined != null) {
    words = query.trim().substring(0, joined.start).split(RegExp(r'\s+'));
    if (words.length >= 2) shorter.add(words.join(' '));
  }
  for (var i = 1; i < words.length - 1; i++) {
    shorter.add(words.sublist(i).join(' '));
  }
  // A single food named with its kind, not a dish: "cherry tomatoes",
  // "kalamata olives", "red pesto" found nothing, though the Food tab's
  // search lists "Tomatoes, raw" first. The user's MacroFactor foods missed
  // eight such (2026-11-09).
  if (lastAlone && joined == null && words.length >= 2) {
    final last = words.last.toLowerCase();
    if (!_dishHeads.contains(last)) shorter.add(last);
  }
  return shorter;
}

/// The last words of a dish, too broad alone to stand for it: "chicken
/// salad" is no salad row, and a dish the table cannot name is broken
/// down (D9).
/// How a food was made, which its plain row is not.
final _madeAWay = RegExp(
  r'\b(saut[eé]ed|fried|roasted|grilled|baked|braised|stewed|creamed|'
  r'mashed|pickled|smoked|glazed|candied|caramelized|breaded|stuffed)\b',
  caseSensitive: false,
);

const _dishHeads = {
  'salad',
  'salads',
  'soup',
  'soups',
  'rice',
  'chicken',
  'beef',
  'pork',
  'bowl',
  'sandwich',
  'sandwiches',
  'pie',
  'pies',
  'cake',
  'cakes',
  'pasta',
  'stew',
  'curry',
  'burger',
  'burgers',
  'wrap',
  'wraps',
  'plate',
  'casserole',
  'pilaf',
  'pizza',
  'dish',
  'roll',
  'rolls',
  'mix',
  'balls',
  'bake',
  'noodles',
  'platter',
  'skewers',
  'meat',
  'fish',
  'sauce',
  'dumplings',
  'pancakes',
  // a kind of sweet or snack, not one: "fruit jelly sweets" found sweet
  // potato, "curd snack" a berry bar
  'snack', 'snacks', 'sweets', 'sweet', 'candy', 'candies', 'bar', 'bars',
  'treat', 'treats', 'dessert', 'delight', 'cookies', 'biscuits', 'drink',
};

/// Whether [row] is named for [food] itself, its name starting with the
/// words of [food] ("Cheesecake, plain" for "cheesecake"), rather than
/// merely holding them ("Melon balls" for "balls").
bool _namedFor(SpFoodDTO row, String food) {
  final name = (row.name ?? '').toLowerCase().split(RegExp(r'[^a-z]+'));
  final words = food.toLowerCase().split(RegExp(r'\s+'));
  if (name.length < words.length) return false;
  for (var i = 0; i < words.length; i++) {
    if (!wordsAgree(words[i], name[i])) return false;
  }
  return true;
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

/// A piece for rows the table gives no portion, so a count is that many
/// pieces: a photo's 8 meatballs found "Meatballs, fried" (BLS, by weight
/// only) at the 100 g default, and a frozen row's "3 oz" serving made them
/// 8 × 85 g. A home or canteen meatball of about 3.5 cm weighs about 30 g.
const addedPieces = <String, (String, double)>{
  'Meatballs, fried': ('1 meatball', 30),
  'Pork meatballs, fried': ('1 meatball', 30),
  'Beef meatballs, fried': ('1 meatball', 30),
  'Veal meatballs, fried': ('1 meatball', 30),
  'Game meatballs, fried': ('1 meatball', 30),
  'Meatballs of turkey, fried': ('1 meatball', 30),
  'Chicken meatballs, with button mushrooms, fried': ('1 meatball', 30),
  // Bite-sized, as for soup or a buffet: about 2.5 cm.
  'Small meatballs': ('1 meatball', 12),
  'Small meatballs (pork/veal mince), fried': ('1 meatball', 12),
  'Small veal meatballs, fried in oven': ('1 meatball', 12),
  'Small lamb meatballs, cooked': ('1 meatball', 12),
  'Small game meatballs': ('1 meatball', 12),
  'Small sausage meatballs': ('1 meatball', 12),
};

/// A serving that replaces the table's, so a count is of the thing a
/// person counts: bacon's 16 g "serving" made a photo's 4 slices 64 g;
/// a medium slice cooked is 8 g. Its other portions stay.
const servingOverrides = <String, (String, double)>{
  'Bacon, NS as to type of meat, cooked': ('1 slice', 8),
};

/// [row] with its [servingOverrides] serving, or its [addedPieces] one
/// where the table gives it none.
Map<String, Object?> _withAddedPiece(Map<String, Object?> row) {
  if (servingOverrides[row['name']] case (final size, final grams)) {
    return {...row, 'serving_size': size, 'serving_gram_weight': grams};
  }
  final piece = addedPieces[row['name']];
  if (piece == null || row['serving_gram_weight'] != null) return row;
  return {
    ...row,
    'serving_size': piece.$1,
    'serving_gram_weight': piece.$2,
    'has_portion': true,
  };
}

/// The decoded asset: rows and their portions by food id.
class LocalFoodTable {
  final List<SpFoodDTO> foods;
  final Map<int, List<MealPortionEntity>> portions;
  final List<Set<String>> _tokens;

  /// A fork dish's names in its brackets, by row index: the words that
  /// match only there.
  final Map<int, _Aliases> _aliases;

  LocalFoodTable(this.foods, this.portions)
    : _tokens = [for (final food in foods) _nameTokens(food.name)],
      _aliases = {
        for (var i = 0; i < foods.length; i++) i: ?_Aliases.of(foods[i]),
      };

  /// Whether query word [q] (through [spelling]) holds in row [i]'s name,
  /// for a search for [query]. A fork dish's bracketed names count for a
  /// query that shares a word with the name outside them ("fried pork
  /// patties" is "Pork cutlets, fried (..., minced pork patties)"), and
  /// otherwise only as a whole, up to what one is made with: "pelēkie
  /// zirņi" is "Grey peas with bacon (pelēkie zirņi ar speķi)", but
  /// "speķis" is not, nor "pankūkas" "Liver patties (aknu pankūkas, ...)",
  /// nor "lasis" a salmon soup made "ar lasi". A single Latvian word found
  /// the dish it is a word of.
  bool _has(int i, Iterable<String> query, String q) {
    final aliases = _aliases[i];
    if (aliases == null) return _agrees(q, _tokens[i]);
    if (_agrees(q, aliases.outside)) return true;
    final anchored = query.any((w) => _agrees(w, aliases.outside));
    return (anchored ? aliases.names.map((n) => n.$1) : aliases.named(query))
        .any((alias) => _agrees(q, alias));
  }

  static bool _agrees(String q, Set<String> tokens) =>
      tokens.any((t) => wordsAgree(q, t));

  /// [name]'s words, and each pair of neighbours run together: "KIT KAT"
  /// is found by `kitkat`, as a person types it.
  static Set<String> _nameTokens(String? name) {
    final words = nameWords(name);
    return {
      ...words,
      for (var i = 0; i + 1 < words.length; i++) '${words[i]}${words[i + 1]}',
    };
  }

  /// The first enabled row named exactly [name].
  SpFoodDTO? named(
    String name, {
    required bool Function(String? source) isEnabled,
  }) {
    for (final food in foods) {
      if (food.name == name && isEnabled(food.source)) return food;
    }
    return null;
  }

  static LocalFoodTable fromGzip(Uint8List bytes) =>
      fromJson(jsonDecode(utf8.decode(gzip.decode(bytes))) as Map);

  static LocalFoodTable fromJson(Map<dynamic, dynamic> json) {
    final columns = (json['columns'] as List).cast<String>();
    final foods = [
      for (final row in json['foods'] as List)
        SpFoodDTO.fromJson(
          _withAddedPiece({
            for (var i = 0; i < columns.length; i++)
              columns[i]: (row as List)[i],
          }),
        ),
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
    for (final food in foods) {
      final (id, piece) = (food.foodId, addedPieces[food.name]);
      if (id == null || piece == null || portions.containsKey(id)) continue;
      portions[id] = [
        MealPortionEntity(
          label: piece.$1,
          gramWeight: piece.$2,
          localized: false,
        ),
      ];
    }
    // "1 serving" scales by the first portion, so a food's own serving
    // leads its list: oats' 10 g serving logged an 80 g cup.
    for (final food in foods) {
      final list = portions[food.foodId];
      final size = food.servingSize, grams = food.servingGramWeight;
      if (list == null || size == null || grams == null || grams <= 0) {
        continue;
      }
      if ((list.first.gramWeight - grams).abs() < 0.5) continue;
      list.insert(
        0,
        MealPortionEntity(label: size, gramWeight: grams, localized: false),
      );
    }
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
    final query = nameWords(searchString).map(spelling).toSet();
    if (query.isEmpty) return const [];
    final matches = <SpFoodDTO>[];
    for (var i = 0; i < foods.length; i++) {
      final food = foods[i];
      if (!isEnabled(food.source)) continue;
      if (query.every((q) => _has(i, query, q))) {
        matches.add(food);
      }
    }
    _sort(matches, searchString.trim().toLowerCase());
    return matches.take(LocalFoodDataSource.candidatePoolSize).toList();
  }

  /// The pool for [searchString] when no row has every word: the rows with
  /// the most of them, and among those the ones with its last word, the
  /// food a name puts last ("cherry tomatoes" are tomatoes). One word that
  /// is not the last is no match: "turkish delight" is no Turkish coffee.
  /// Nothing for a one-word search, which [search] answered already.
  List<SpFoodDTO> searchMostWords(
    String searchString, {
    required bool Function(String? source) isEnabled,
  }) {
    final words = nameWords(searchString).map(spelling).toList();
    if (words.toSet().length < 2) return const [];
    final last = words.last;
    var best = (0, false);
    var matches = <SpFoodDTO>[];
    for (var i = 0; i < foods.length; i++) {
      final food = foods[i];
      if (!isEnabled(food.source)) continue;
      bool has(String q) => _has(i, words, q);
      final count = words.toSet().where(has).length;
      if (count == 0) continue;
      final score = (count, has(last));
      final cmp = score.$1 != best.$1
          ? score.$1.compareTo(best.$1)
          : (score.$2 ? 1 : 0) - (best.$2 ? 1 : 0);
      if (cmp > 0) {
        best = score;
        matches = [food];
      } else if (cmp == 0) {
        matches.add(food);
      }
    }
    if (best.$1 < 2 && !best.$2) return const [];
    _sort(matches, searchString.trim().toLowerCase());
    const size = LocalFoodDataSource.candidatePoolSize;
    return [
      ...matches.take(size),
      // The row a bare name means (S75), long enough to sort past the cut.
      for (final food in matches.skip(size))
        if (isEverydayRow(food.name, searchString)) food,
    ];
  }

  /// The backend's order: a portion first, then the title equal to [term],
  /// then the shorter name, then the id.
  static void _sort(List<SpFoodDTO> matches, String term) {
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
  }

  static bool _titleIs(SpFoodDTO food, String term) =>
      deriveTitle(food.name ?? '').toLowerCase() == term;
}

/// A fork dish's other names, from the brackets of its row's name:
/// "Salmon soup, creamy (lohikeitto, laša zupa, zivju zupa ar lasi)".
class _Aliases {
  /// The tokens of the name outside the brackets.
  final Set<String> outside;

  /// Each bracketed name's tokens, with the words of its head: the part
  /// before what it is made with ("zivju zupa" of "zivju zupa ar lasi").
  final List<(Set<String>, List<String>)> names;

  _Aliases(this.outside, this.names);

  /// What joins a dish to what it is made with, in the languages the
  /// dishes' names are in.
  static const _joints = {'with', 'and', 'in', 'ar', 'un', 'su', 'mit', 'z'};

  static _Aliases? of(SpFoodDTO food) {
    final name = food.name;
    if (food.source != 'fork_dishes' || name == null) return null;
    final open = name.indexOf('(');
    if (open < 0) return null;
    final close = name.indexOf(')', open);
    final inside = name.substring(open + 1, close < 0 ? name.length : close);
    return _Aliases(
      LocalFoodTable._nameTokens(
        name.substring(0, open) + (close < 0 ? '' : name.substring(close + 1)),
      ),
      [
        for (final alias in inside.split(','))
          if (nameWords(alias) case final words when words.isNotEmpty)
            (
              LocalFoodTable._nameTokens(alias),
              words.takeWhile((w) => !_joints.contains(w)).toList(),
            ),
      ],
    );
  }

  /// The tokens of each bracketed name whose head [query] gives whole.
  Iterable<Set<String>> named(Iterable<String> query) => [
    for (final (tokens, head) in names)
      if (head.every((h) => query.any((q) => wordsAgree(q, spelling(h)))))
        tokens,
  ];
}

/// [text]'s words in order, lower-cased, as [tokenize] splits them.
List<String> nameWords(String? text) => (text ?? '')
    .toLowerCase()
    .split(RegExp(r'[^\p{L}\p{N}]+', unicode: true))
    .where((w) => w.isNotEmpty)
    .toList();

/// The table's word for a query word people spell another way. Recipe
/// search folds both sides through it too (`recipe_search.dart`): a model
/// names the Georgian boat "adjaruli" or "acharuli", a recipe saved from a
/// web page "Adjarian".
String spelling(String word) => switch (word) {
  'bbq' || 'barbeque' => 'barbecue',
  'tater' => 'potato',
  'adjaruli' || 'acharuli' || 'adjaran' || 'ajarian' || 'ajaruli' => 'adjarian',
  // Rice by its variety, which no row names: the table's rows go by the
  // grain ("Rice, white, long-grain, ..."), run together as one token.
  'basmati' || 'jasmine' => 'longgrain',
  'arborio' => 'mediumgrain',
  // Pasta by its shape, which no row names: the table has "Pasta, cooked".
  'penne' || 'fusilli' || 'rigatoni' || 'farfalle' || 'tagliatelle' => 'pasta',
  // Latvian, as the user logs them: auzu pārslas, oat flakes; siers, cheese.
  'auzu' => 'oat',
  'pārslas' || 'parslas' => 'flakes',
  'siers' || 'sieru' => 'cheese',
  _ => word,
};

/// Whether query word [q] and name word [t] are the same word up to an
/// ending: one is the other plus at most two letters (`egg`/`eggs`,
/// `potato`/`potatoes`; one letter for a three-letter word, so `fan` is not
/// `fanta`), or both share a stem of five letters or more and differ in at
/// most two letters after it, one for the shorter (`cheese`/`cheesy`), or
/// `y` and `ies` (`berry`/`berries`). Four shared letters are not a stem:
/// `pasta` is not `paste`. Recipe search uses it too (`recipe_search.dart`).
bool wordsAgree(String q, String t) {
  if (q == t) return true;
  final (shorter, longer) = q.length <= t.length ? (q, t) : (t, q);
  var shared = 0;
  while (shared < shorter.length &&
      shorter.codeUnitAt(shared) == longer.codeUnitAt(shared)) {
    shared++;
  }
  if (shared == shorter.length) {
    // A three-letter word takes one letter (`egg`/`eggs`), not two: `fan`
    // is not `fanta`.
    final ending = shorter.length == 3 ? 1 : 2;
    return shorter.length >= 3 && longer.length - shorter.length <= ending;
  }
  if (shorter.endsWith('y') &&
      longer == '${shorter.substring(0, shorter.length - 1)}ies') {
    return true;
  }
  // Both differ after the stem, the shorter by one letter, past five
  // shared: `casein` is not `casero` (a pound cake for "micellar casein"),
  // `pasta` not `paste` (guava paste for "penne"), `fried` not `fries`.
  return shared >= 5 &&
      longer.length - shared <= 2 &&
      shorter.length - shared <= 1;
}
