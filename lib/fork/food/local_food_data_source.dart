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
import 'package:opennutritracker/fork/food/served_with.dart';
import 'package:opennutritracker/fork/food/unasked_variant.dart';
import 'package:opennutritracker/fork/food/unspecified_row.dart';
import 'package:opennutritracker/fork/food/vegetables.dart';

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
    List<SpFoodDTO> search(String query) {
      final found = foods.search(
        query,
        isEnabled: (source) => toggles?[source] ?? true,
      );
      // A row that is another food served with the one named is no match
      // (S205), and the resolver would leave it out: the name goes on to
      // its shorter forms. "dark leafy greens" found only beef-and-rice
      // dishes "excluding ... dark-green leafy".
      if (!forResolution) return found;
      return [
        for (final row in found)
          if (!servedWithOnly(row.name, query)) row,
      ];
    }

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
    // A last qualifier that is a way of cooking, then what the food is made
    // with, drops the made-with first, so the way stays: "eggs, scrambled
    // with whole milk and butter" is scrambled eggs, not raw ones. Only for
    // rows that name the way as the food's own: "pasta, baked" found a
    // pasta "with baked pumpkin". A coating is not dropped: "carrots,
    // battered and fried" found raw carrots, a third of the energy, where
    // nothing named is better, to be broken down (D9).
    while (forResolution && rows.isEmpty && query.contains(',')) {
      final cut = query.lastIndexOf(',');
      final last = query.substring(cut + 1);
      final joint = _joiner.firstMatch(last);
      final ways = joint == null
          ? const <String>[]
          : nameWords(last.substring(0, joint.start));
      if (joint != null && ways.isNotEmpty) {
        // "carrots, fried in batter" keeps its batter too
        if (_coated.hasMatch(last.substring(joint.start))) break;
        if (ways.every(_cookedWays.contains)) {
          final made = query.substring(0, cut + 1 + joint.start);
          final found = [
            for (final row in search(made))
              if (ways.every(
                (w) => _coated.hasMatch(w) || holdsAsFood(row.name, w),
              ))
                row,
          ];
          if (found.isNotEmpty) {
            query = made;
            rows = found;
            continue;
          }
        }
      }
      if (_coated.hasMatch(last)) break;
      // A way of cooking the table has no row for is still cooked: "tomato,
      // roasted" found raw tomatoes, where cooked ones are the nearest, and
      // roasting is baking ("sweet potato, roasted" is a baked one, with its
      // fat, not a boiled one). Only rows of the food itself (see [_ofFood]):
      // "beetroot, roasted" is no cooked beetroot salad, "butter, sauteed"
      // no braised pork butt; rows titled as the food come first, in either
      // state, so "beets, roasted" is cooked beets before baked leaf beet.
      final way = nameWords(last);
      if (way.isNotEmpty && way.every(_heatedWays.contains)) {
        final food = query.substring(0, cut);
        // the table's cooked grains are boiled: "oat flakes, cooked" is
        // "Oat flakes, boiled", where dropping the word found the dry flakes
        final states = way.length == 1 && way.single == 'cooked'
            ? const ['boiled']
            : [if (way.contains('roasted')) 'baked', 'cooked'];
        final of = {
          for (final state in states)
            state: [
              for (final row in search('$food, $state'))
                if (_ofFood(row, food)) row,
            ],
        };
        var found = const <SpFoodDTO>[];
        for (final titledOnly in [true, false]) {
          for (final state in states) {
            found = [
              for (final row in of[state]!)
                if (!titledOnly || _titled(row, food)) row,
            ];
            if (found.isNotEmpty) {
              query = '$food, $state';
              break;
            }
          }
          if (found.isNotEmpty) break;
        }
        if (found.isNotEmpty) {
          rows = found;
          continue;
        }
      }
      query = query.substring(0, cut);
      rows = search(query);
    }
    // Then a dish name with words the table does not use ("blueberry
    // cheesecake", "rice with herbs"): the nearest food it names.
    if (forResolution && rows.isEmpty) {
      // a model's qualifiers after a comma were the food's, not its kind
      // and a dish ("spaghetti bolognese" is no sauce) or a food cooked a
      // way the plain row is not ("sautéed mushrooms" are not raw ones)
      // keeps its words, to be broken down (D9)
      // and a word the table does not know is a brand's ("zorblax
      // crisps"), whose product is the food, not plain crisps
      final lastAlone =
          !searchString.contains(',') &&
          !isMainDish(searchString) &&
          !_madeAWay.hasMatch(searchString) &&
          query
              .trim()
              .split(RegExp(r'\s+'))
              .every((word) => search(word).isNotEmpty);
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
    // A coated, fried vegetable the table has no row of ("bell pepper,
    // battered, fried") is the table's battered vegetables, not nothing:
    // a model's breakdown of one food finds no dish to split.
    if (forResolution &&
        rows.isEmpty &&
        _coated.hasMatch(searchString) &&
        namedVegetable(searchString) != null) {
      final tempura = foods.named(
        _coatedVegetables,
        isEnabled: (source) => toggles?[source] ?? true,
      );
      if (tempura != null) rows = [tempura];
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

/// Words for how a food was cooked, which a last qualifier may hold
/// before what it was made with.
const _cookedWays = {
  'scrambled',
  'fried',
  'stir',
  'pan',
  'deep',
  'baked',
  'roasted',
  'grilled',
  'boiled',
  'steamed',
  'poached',
  'sauteed',
  'sautéed',
  'braised',
  'stewed',
  'smoked',
  'toasted',
  'cooked',
  'battered',
  'breaded',
  'coated',
};

/// The [_cookedWays] that leave a food cooked through, as its cooked row
/// has it. Not toasted or smoked, which a food may be and still be raw
/// inside or cured, nor a coating.
const _heatedWays = {
  'cooked',
  'fried',
  'stir',
  'pan',
  'deep',
  'baked',
  'roasted',
  'grilled',
  'boiled',
  'steamed',
  'poached',
  'sauteed',
  'sautéed',
  'braised',
  'stewed',
};

/// The table's battered vegetables, fried: 239 kcal per 100 g, where its
/// battered carrots, broccoli and cauliflower are 231-246.
const _coatedVegetables = 'Vegetable tempura';

/// A coating, which a food's plain row does not have.
final _coated = RegExp(
  r'\b(batter|battered|breaded|tempura|crumbed|coated)\b',
  caseSensitive: false,
);

/// A bracketed part of a name: "(chilled borscht)".
final _bracketed = RegExp(r'\s*\([^)]*\)?');

/// Shorter forms of [query] to try, nearest first: without what follows
/// "with", "in", "and" or "on" (Latvian "ar"), then without its first
/// words one at a time. An English or Latvian dish name puts the food last
/// and its kind before it: "Caesar salad with bacon" is a Caesar salad,
/// "chicken rice pilaf" a rice pilaf. Each keeps two words at least: one
/// word alone is too broad to stand for the dish ("salad", "rice",
/// "chicken"), and a dish the table cannot name is broken down instead (D9).
/// Last, the last word alone when it is a food, not a dish ([_dishHeads]),
/// unless not [lastAlone].
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

/// How a food was made, which its plain row is not.
final _madeAWay = RegExp(
  r'\b(saut[eé]ed|fried|roasted|grilled|baked|braised|stewed|creamed|'
  r'mashed|pickled|smoked|glazed|candied|caramelized|breaded|stuffed)\b',
  caseSensitive: false,
);

/// The last words of a dish, too broad alone to stand for it: "chicken
/// salad" is no salad row, and a dish the table cannot name is broken
/// down (D9).
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
  // a way of cooking a food, not one: "vegetable fritters" found a corn
  // fritter at 404 kcal per 100 g, "zucchini fries" a fry sauce
  'fritter', 'fritters', 'fries',
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

/// Whether [row]'s title, its name before the first comma, is [food]'s
/// words, up to their endings: "Tomatoes, fresh, cooked" for "tomato".
bool _titled(SpFoodDTO row, String food) {
  final title = nameWords(deriveTitle(row.name ?? ''));
  final words = nameWords(food);
  if (title.length != words.length) return false;
  for (var i = 0; i < words.length; i++) {
    if (!wordsAgree(spelling(words[i]), spelling(title[i]))) return false;
  }
  return true;
}

/// Whether [row] is a row of [food] itself, not a dish holding it: no
/// part of its name adds "with" something other than salt ("Sweet peppers,
/// with minced meat filling"), and either its title is [food]'s words, its
/// title is the family [food] names ("Squash, winter, acorn" for "acorn
/// squash", "Summer squash, yellow" for "yellow squash"), or a part of its
/// name is [food] ("Squash, summer, zucchini" for "zucchini").
bool _ofFood(SpFoodDTO row, String food) {
  final parts = (row.name ?? '').split(',').map((p) => p.trim()).toList();
  for (final part in parts.skip(1)) {
    final lower = part.toLowerCase();
    if (lower.startsWith('with ') && !lower.startsWith('with salt')) {
      return false;
    }
  }
  final words = [for (final w in nameWords(food)) spelling(w)];
  if (words.isEmpty) return false;
  bool same(List<String> a) =>
      a.length == words.length &&
      [
        for (var i = 0; i < a.length; i++) wordsAgree(words[i], a[i]),
      ].every((ok) => ok);
  final name = [for (final w in nameWords(row.name)) spelling(w)];
  bool inName(String w) => name.any((n) => wordsAgree(w, n));
  final title = [for (final w in nameWords(parts.first)) spelling(w)];
  if (same(title)) return true;
  if (title.isNotEmpty &&
      words.every(inName) &&
      (title.every((t) => words.any((w) => wordsAgree(w, t))) ||
          wordsAgree(words.last, title.last))) {
    return true;
  }
  return parts
      .skip(1)
      .any((part) => same([for (final w in nameWords(part)) spelling(w)]));
}

final _stateWords = RegExp(
  r'\b(raw|dry|dried|uncooked|cooked|boiled|steamed|stewed|fried|baked)\b',
  caseSensitive: false,
);
final _cookedWords = RegExp(
  r'\b(cooked|boiled|steamed)\b',
  caseSensitive: false,
);

/// A grain named as flakes, the product a person weighs out dry: "oat
/// flakes" found "Oat flakes, boiled" at 66 kcal per 100 g, where the dry
/// flakes are 348. A porridge or a cooking word names the cooked food
/// ([_stateWords]). Groats are not: a plate's "buckwheat groats" is the
/// cooked buckwheat, at its cooked weight. By the name's last word, through
/// [spelling] ("auzu pārslas").
bool _soldDry(String asked) {
  final words = nameWords(asked);
  return words.isNotEmpty && spelling(words.last) == 'flakes';
}

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
/// keeps every row, even once that qualifier was dropped ([asked]). So does
/// a name of flakes ([_soldDry]).
List<SpFoodDTO> _servedNotDry(
  List<SpFoodDTO> rows,
  String query, {
  required String asked,
}) {
  if (_stateWords.hasMatch(asked)) return rows;
  if (_soldDry(asked)) return rows;
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
  // Counted BLS foods, which the table weighs by 100 g only, so a count of
  // 3 grilled sausages was 3 g. Typical German and EU weights, as eaten.
  // Not "Rye bread", which with a slice beat "Bread, rye" on "rye bread",
  // nor "Chicken breast, without skin, fried without fat (pan)", which beat
  // the fried breast, with its fat, on "chicken breast, fried".
  // A Thuringian-style Rostbratwurst is sold at 100-150 g raw.
  'Rostbratwurst sausage': ('1 sausage', 100),
  'Rostbratwurst sausage, grilled': ('1 sausage', 100),
  'Rostbratwurst sausage, fried without fat (pan)': ('1 sausage', 100),
  'Rostbratwurst sausage poached': ('1 sausage', 100),
  // Wiener Würstchen come in pairs of about 100 g.
  'Vienna sausage': ('1 sausage', 50),
  'Vegetarian Vienna sausages': ('1 sausage', 50),
  // a cornflake cluster, about 30 to a 150 g bag
  'Crispy praline, with milk chocolate, cornflakes and almond bits': (
    '1 piece',
    5,
  ),
  // a quarter of a 400 g Turkish loaf, or one Arabic flatbread
  'Wheat flatbread': ('1 piece', 100),
  // a 25 cm wrap, as EU supermarkets sell them
  'Wheat flour tortilla': ('1 tortilla', 60),
  // a 250 g baguette is about 60 cm: a 3 cm slice
  'Wheat baguette': ('1 slice', 12),
  // a 120-150 g raw skewer, grilled
  'Meat skewer (veal and pork), grilled': ('1 skewer', 100),
  'Beef skewer, grilled': ('1 skewer', 100),
  // a 125 g raw patty, cooked
  'Beef patty, grilled': ('1 patty', 90),
  'Beef patty, fried without fat (pan)': ('1 patty', 90),
  // a schnitzel of about 125 g raw, with its crumbs after frying
  'Pork schnitzel breaded, fried': ('1 schnitzel', 150),
  'Pork schnitzel, fried': ('1 schnitzel', 110),
  // a loin chop without the bone, crumbed
  'Pork chop breaded, fried': ('1 chop', 150),
  // a 170 g raw fillet, cooked
  'Chicken breast fillet, fried without fat (pan)': ('1 breast', 130),
  'Chicken breast fillet, fried': ('1 breast', 130),
  // a 125 g raw portion, as packs of two sell it
  'Salmon, grilled': ('1 fillet', 110),
  // frozen croquettes, about 30 to a 750 g bag
  'Potato croquettes': ('1 croquette', 25),
  'Potato croquettes deep-frozen, baked': ('1 croquette', 25),
  'Potato croquettes deep-frozen, deep-fried': ('1 croquette', 25),
  'Muesli bar': ('1 bar', 25),
  // a turkey breast steak of about 150 g raw, grilled
  'Turkey breast, without skin, grilled': ('1 steak', 110),
  // a chocolate-coated marzipan piece, as in a 100 g bar of eight
  'Bittersweet/semisweet chocolate, filled with marzipan': ('1 piece', 13),
  // a brine-cured olive with its stone
  'Olives blackened, in brine, drained': ('1 olive', 4),
  // Counted BLS foods by group (S213), so a count is that many of them.
  // Not the raw tomato, carrot, onion, chicken pieces, patties, duck and
  // quail eggs, the fried eggs, the chicken thigh or the rye breads: with a
  // piece each beat the row a name means, as "Rye bread" did above.
  // A German or EU bakery roll (Brötchen) of 55-60 g, a toast slice of
  // 25 g, a slice of a German loaf of about 45 g (1 cm of a 1 kg loaf), of
  // a white loaf 30 g.
  'Wheat roll': ('1 roll', 55),
  'Wheat-rye roll (> 50 % and, < 90 % wheat)': ('1 roll', 55),
  'Spelt roll': ('1 roll', 55),
  'Wholemeal roll': ('1 roll', 60),
  'Wholemeal wheat roll': ('1 roll', 60),
  'Wholemeal rye roll': ('1 roll', 60),
  'Wholemeal spelt roll': ('1 roll', 60),
  'Oat roll': ('1 roll', 60),
  'Rye roll': ('1 roll', 60),
  'Rye roll, with oilseeds': ('1 roll', 60),
  'Multigrain roll': ('1 roll', 60),
  'Roll gluten-free': ('1 roll', 60),
  'Wheat baguette roll': ('1 roll', 60),
  'Milk roll (yeast dough)': ('1 roll', 45),
  'Pretzel roll, with butter': ('1 roll', 80),
  'Wheat toast/butter toast': ('1 slice', 25),
  'Wheat toast/butter toast, toasted': ('1 slice', 22),
  'Wholemeal wheat toast': ('1 slice', 28),
  'Wholemeal wheat toast toasted': ('1 slice', 25),
  'Mixed wheat toast': ('1 slice', 25),
  'Mixed wheat toast toasted': ('1 slice', 22),
  'Toast gluten-free': ('1 slice', 25),
  'Toast gluten-free, toasted': ('1 slice', 22),
  'Rye-wheat bread (> 50 % and, < 90 % rye)': ('1 slice', 45),
  'Wheat-rye bread (> 50 % and, < 90 % wheat)': ('1 slice', 45),
  'Multigrain bread': ('1 slice', 45),
  'Oat bread': ('1 slice', 40),
  'Protein bread': ('1 slice', 25),
  'White bread/wheat bread': ('1 slice', 30),
  'Rye crispbread': ('1 crispbread', 10),
  'Crackers': ('1 cracker', 3),
  // A Bavarian lye pretzel, as bakeries sell it, and a croissant of 60 g.
  'Pretzel (visible salt removed)': ('1 pretzel', 85),
  'Pretzel, salted': ('1 pretzel', 85),
  'Danish pastry croissant': ('1 croissant', 60),
  'Wholemeal Danish pastry croissant': ('1 croissant', 60),
  'Danish pastry croissant, filled with nut nougat cream': ('1 croissant', 80),
  // A medium (M) egg without its shell.
  'Chicken egg, raw': ('1 egg', 55),
  'Goose egg, raw': ('1 egg', 145),
  'Quail egg, boiled': ('1 egg', 10),
  'Turkey egg, raw': ('1 egg', 80),
  'Turkey egg, boiled': ('1 egg', 80),
  // Fast food as EU chains sell it: a cheeseburger of 115 g, a hamburger of
  // 105 g, a double cheeseburger of 165 g, a hot dog in its bun of 120 g.
  'Cheeseburger': ('1 cheeseburger', 115),
  'Double cheeseburger': ('1 double cheeseburger', 165),
  'Hamburger': ('1 hamburger', 105),
  'Hot Dog': ('1 hot dog', 120),
  'Doner kebab, flatbread filled with grilled poultry, salad and sauce': (
    '1 doner',
    400,
  ),
  'Club sandwich, with mozzarella, tomatoes and boiled ham': (
    '1 sandwich',
    200,
  ),
  'Toast Hawaii (pineapple, boiled ham, cheese) baked': ('1 toast', 110),
  'Spring rolls filled, with vegetables and pork, deep-fried': (
    '1 spring roll',
    60,
  ),
  'Sushi, with salmon': ('1 piece', 30),
  // A bread or potato dumpling (Knödel) of about 90 g.
  'White bread dumplings': ('1 dumpling', 90),
  'White bread dumplings, raw': ('1 dumpling', 90),
  'White bread dumplings, dried, boiled': ('1 dumpling', 90),
  'Potato dumplings (made, from half raw and half boiled potatoes)': (
    '1 dumpling',
    90,
  ),
  'Potato dumplings, from boiled potatoes': ('1 dumpling', 90),
  'Thuringian dumplings (made, from raw and boiled potatoes)': (
    '1 dumpling',
    100,
  ),
  'Tyrolean bacon dumplings': ('1 dumpling', 90),
  'Spinach dumplings': ('1 dumpling', 80),
  '"Dampfnudeln" yeast dumplings, salted fried': ('1 dumpling', 110),
  '"Rohrnudeln" sweet yeast dumplings, baked': ('1 dumpling', 90),
  '"Buchteln", baked yeast buns': ('1 bun', 50),
  '"Königsberger Klopse" meatballs': ('1 meatball', 60),
  // A German pancake (Pfannkuchen) of about 60 g, thicker than a crêpe;
  // small quark or buckwheat ones of 30-45 g; a potato pancake of 70 g.
  'Pancakes unsweetened, with milk 3.5 % fat, fried': ('1 pancake', 60),
  'Pancakes unsweetened, with milk 1.5 % fat, fried': ('1 pancake', 60),
  'Pancakes unsweetened, with milk 1.5 % fat, fried without fat': (
    '1 pancake',
    60,
  ),
  'Pancakes unsweetened, with milk 3.5 % fat, fried in butter': (
    '1 pancake',
    60,
  ),
  'Wholemeal pancakes unsweetened, with milk 3.5 % fat, fried': (
    '1 pancake',
    60,
  ),
  'Pancakes made, from buckwheat flour, unsweetened, fried': ('1 pancake', 60),
  'Pancakes, with milk 3.5 % fat and apple, fried': ('1 pancake', 80),
  'Pancakes, with milk 3.5 % fat and blueberries, fried': ('1 pancake', 70),
  'Pancakes, with milk 3.5 % fat, fried, filled with jam': ('1 pancake', 80),
  'Pancakes, fried, filled with stewed mixed vegetables': ('1 pancake', 40),
  'Small quark pancakes, fried': ('1 pancake', 45),
  'Quark pancakes unsweetened, fried': ('1 pancake', 50),
  'Small quark-yeast pancakes, fried': ('1 pancake', 40),
  'Small buckwheat pancakes, fried': ('1 pancake', 30),
  'Potato pancakes, fried': ('1 pancake', 70),
  'Potato pancakes (with sour cream and semolina), fried': ('1 pancake', 70),
  'Potato pancakes deep-frozen': ('1 pancake', 60),
  'Potato pancakes deep-frozen, fried without fat (pan)': ('1 pancake', 60),
  'Potato pancakes deep-frozen, baked': ('1 pancake', 55),
  'Potato pancakes deep-frozen, deep-fried': ('1 pancake', 60),
  // A slice of a German cake: 110 g of a fruit cake or pie, 70 g of a loaf
  // cake (Rührkuchen), 130 g of strudel; a muffin of 85 g.
  'Apple cake (quark oil dough)': ('1 slice', 110),
  'Apple pie (cake batter)': ('1 slice', 110),
  'Apple pie (sand cake batter)': ('1 slice', 110),
  'Apple pie (shortcrust pastry)': ('1 slice', 110),
  'Apple pie (yeast dough)': ('1 slice', 110),
  'Apple strudel (puff pastry)': ('1 piece', 130),
  'Apple strudel (shortcrust pastry)': ('1 piece', 130),
  'Apple strudel (strudel dough)': ('1 piece', 130),
  'Cherry strudel (puff pastry)': ('1 piece', 130),
  'Cherry strudel (strudel dough)': ('1 piece', 130),
  'Chocolate cake (cake batter)': ('1 slice', 70),
  'Coconut cake (cake batter)': ('1 slice', 70),
  'Lemon cake (cake batter)': ('1 slice', 70),
  'Marble cake (cake batter)': ('1 slice', 70),
  'Pound cake (cake batter)': ('1 slice', 70),
  'Pumpkin cake (cake batter)': ('1 slice', 70),
  'Thuringian poppy seed cake (yeast dough)': ('1 slice', 100),
  'Sacher torte (cake batter)': ('1 slice', 90),
  'Brownies': ('1 brownie', 50),
  'Chocolate muffins (cake batter)': ('1 muffin', 85),
  'Danish pastry, with pudding and fruit': ('1 pastry', 100),
  'Danish pastry, with quark and fruit': ('1 pastry', 100),
  '"Franzbrötchen" Danish pastry, filled with cinnamon-sugar': ('1 piece', 80),
  '"Amerikaner" moist shortbread biscuit (cake batter), with sugar icing': (
    '1 piece',
    70,
  ),
  'Turnover (yeast dough) filled, with apples': ('1 turnover', 100),
  'Doughnut (yeast dough), deep-fried': ('1 doughnut', 70),
  'Gingerbread, with fruit filling and chocolate icing': ('1 piece', 25),
  'Orange sponge biscuits': ('1 biscuit', 12),
  // A boxed praline of 8-10 g (a truffle or coconut one 10 g), a boiled
  // sweet of 5 g, a chocolate-coated ice cream bar of 75 g.
  'Pralines': ('1 praline', 8),
  'Truffle pralines': ('1 praline', 10),
  'Truffle pralines (alcoholic)': ('1 praline', 10),
  'Coconut praline, with cream-filling and blanched almond': ('1 praline', 10),
  'Hard candy': ('1 piece', 5),
  'Ice cream bar filled, with ice cream and caramel, covered with chocolate': (
    '1 bar',
    75,
  ),
  // Sausages as German butchers sell them: a bratwurst of 100-120 g, a
  // Bockwurst of 90 g, a Weißwurst of 70 g, a Frankfurter of 50 g (a pair
  // of 100 g), a Kabanos of 30 g; a slice of Leberkäse of 100 g.
  'Rhenish bratwurst': ('1 sausage', 120),
  'Rhenish bratwurst, fried without fat (pan)': ('1 sausage', 110),
  'Curry-Bratwurst': ('1 sausage', 120),
  'Curry-Bratwurst, grilled': ('1 sausage', 110),
  'Poultry bratwurst': ('1 sausage', 100),
  'Beef-Bratwurst': ('1 sausage', 100),
  'Vegetarian bratwurst (made, from tofu and wheat protein)': ('1 sausage', 80),
  'Bockwurst': ('1 sausage', 90),
  'Bockwurst poached': ('1 sausage', 90),
  'Poultry bockwurst, with pork': ('1 sausage', 90),
  'Poultry bockwurst, with pork, poached': ('1 sausage', 90),
  'Bavarian white sausage': ('1 sausage', 70),
  'Knackwurst/Servela sausage, small': ('1 sausage', 100),
  'Knacker sausage simple': ('1 sausage', 100),
  'Regensburg sausage small': ('1 sausage', 75),
  'Debrecziner sausage, raw, small, firm': ('1 sausage', 50),
  'Landjäger sausage, raw, small, firm': ('1 sausage', 50),
  'Kabanossi/Peperoni, sausage, raw, small, firm': ('1 sausage', 30),
  'Frankfurt sausage small': ('1 sausage', 50),
  'Frankfurt small sausage, canned': ('1 sausage', 50),
  'Frankfurt beef sausage/red sausage': ('1 sausage', 100),
  'Frankfurt beef sausage/red sausage, canned': ('1 sausage', 100),
  'Poultry Vienna sausage': ('1 sausage', 50),
  'Poultry Vienna sausage poached': ('1 sausage', 50),
  'Vienna sausage, canned': ('1 sausage', 50),
  'Cocktail sausage small, canned': ('1 sausage', 12),
  'Soya bean small sausage': ('1 sausage', 50),
  'Leberkaese sausage, fried': ('1 slice', 100),
  'Leberkaese sausage, fried without fat (oven)': ('1 slice', 100),
  'Fleischkaese sausage, fried without fat (pan)': ('1 slice', 100),
  'Fleischkaese sausage, fried without fat (oven)': ('1 slice', 100),
  'Pork salami': ('1 slice', 8),
  // Cuts as EU butchers portion them: a steak of 180-200 g raw, 160 g
  // cooked; a pork or veal chop of 150 g without the bone, a lamb chop of
  // 80 g; a chicken breast of 130 g cooked; a drumstick as eaten, without
  // the bone; a slice of a roast of 60 g.
  'Beef steak (loin), raw': ('1 steak', 200),
  'Beef steak (loin), marinated, raw': ('1 steak', 200),
  'Beef tenderloin steak, raw': ('1 steak', 180),
  'Beef steak (loin), fried without fat (pan)': ('1 steak', 160),
  'Beef steak, fried (with fat and salt)': ('1 steak', 165),
  'Beef rump steak, fried': ('1 steak', 160),
  'Beef steak, grilled, with herb butter': ('1 steak', 170),
  'Pork steak (loin), raw': ('1 steak', 160),
  'Pork steak (neck), raw': ('1 steak', 160),
  'Pork chop (loin), raw': ('1 chop', 150),
  'Veal chop (loin), raw': ('1 chop', 150),
  'Lamb chop (loin), raw': ('1 chop', 80),
  'Chicken breast fillet, grilled': ('1 breast', 130),
  'Chicken breast, without skin, grilled': ('1 breast', 130),
  'Chicken drumstick, with skin, grilled': ('1 drumstick', 75),
  'Chicken drumstick, with skin, marinated, grilled': ('1 drumstick', 75),
  'Beef roast, with sauce': ('1 slice', 60),
  'Beef roast, without sauce': ('1 slice', 60),
  'Pork roast, without sauce': ('1 slice', 60),
  // A fish fillet of 125 g, a salmon steak of 140 g fried, a fish finger of
  // 28 g, a herring fillet of 50 g, a scallop of 15 g, a canned sprat of
  // 7 g and a smoked one of 10 g.
  'Fish fingers (with Alaska pollock), fried': ('1 fish finger', 28),
  'Cod fillet, stewed (with fat and salt)': ('1 fillet', 125),
  'Cod fillet breaded, fried': ('1 fillet', 130),
  'Salmon steaks, fried': ('1 steak', 140),
  'Mackerel, smoked': ('1 fillet', 125),
  'Matjes herring mild, salted': ('1 fillet', 50),
  'Herring, pickled, semi-preserved, drained': ('1 fillet', 50),
  'Scallop, fried without fat (pan)': ('1 scallop', 15),
  'Scallop, grilled': ('1 scallop', 15),
  'Sprat, in oil, canned, drained': ('1 sprat', 7),
  'Sprat, smoked': ('1 sprat', 10),
  // Fruit as EU shops sell it (class I), the part eaten: an apple of 150 g,
  // a banana of 120 g, a pear of 160 g, a peach of 140 g, a plum of 55 g,
  // an orange of 150 g, a mandarin of 70 g, a kiwi of 75 g.
  'Apple, raw': ('1 apple', 150),
  'Banana, raw': ('1 banana', 120),
  'Pear, raw': ('1 pear', 160),
  'Peach, raw': ('1 peach', 140),
  'Nectarine, raw': ('1 nectarine', 140),
  'Plum, raw': ('1 plum', 55),
  'Apricot, raw': ('1 apricot', 40),
  'Apricot, dried': ('1 apricot', 8),
  'Orange, raw': ('1 orange', 150),
  'Mandarin, raw': ('1 mandarin', 70),
  'Tangerine, raw': ('1 tangerine', 70),
  'Clementine, raw': ('1 clementine', 60),
  'Grapefruit, raw': ('1 grapefruit', 300),
  'Kiwi fruit, raw': ('1 kiwi', 75),
  'Avocado, raw': ('1 avocado', 140),
  'Mango, raw': ('1 mango', 300),
  'Fig, raw': ('1 fig', 50),
  'Fig, dried': ('1 fig', 20),
  'Lychee, raw': ('1 lychee', 10),
  'Passion fruit, raw': ('1 passion fruit', 18),
  'Persimmon, raw': ('1 persimmon', 180),
  'Pomegranate, raw': ('1 pomegranate', 180),
  'Pineapple, raw': ('1 slice', 56),
  'Watermelon, raw': ('1 slice', 280),
  'Strawberry, raw': ('1 strawberry', 15),
  'Sweet cherry, raw': ('1 cherry', 8),
  'Grape, raw': ('1 grape', 6),
  // Vegetables eaten or cooked whole: a bell pepper of 160 g, a cucumber
  // of 300 g, a radish of 8 g, a boiled potato of 80 g, a baked one of
  // 200 g.
  'Sweet pepper green, raw': ('1 pepper', 160),
  'Sweet pepper red, raw': ('1 pepper', 160),
  'Sweet pepper yellow, raw': ('1 pepper', 160),
  'Cucumber, raw': ('1 cucumber', 300),
  'Radish, raw': ('1 radish', 8),
  'Spring onion, raw': ('1 spring onion', 15),
  'Garlic, raw': ('1 clove', 4),
  'Stalk celery, raw': ('1 stalk', 40),
  'Potatoes, boiled with peel': ('1 potato', 80),
  'Potatoes, boiled with salt': ('1 potato', 80),
  'Jacket potatoes, baked': ('1 potato', 200),
  // A bowl of the Latvian sweet bread soup (maizes zupa), as served.
  'Bread soup (brown bread), with raisins, apple and sour cream': (
    '1 bowl',
    250,
  ),
};

/// A serving that replaces the table's, so a count is of the thing a
/// person counts: bacon's 16 g "serving" made a photo's 4 slices 64 g;
/// a medium slice cooked is 8 g. Its other portions stay, but one of the
/// same label gives way to it (S213).
const servingOverrides = <String, (String, double)>{
  'Bacon, NS as to type of meat, cooked': ('1 slice', 8),
  // European pieces where the table's US one is far off (S213): a naan of
  // 90 g, not the 177 g 10" one; a fast-food cheeseburger of 115 g.
  'Bread, naan': ('1 naan', 90),
  'Cheeseburger, NFS': ('1 cheeseburger', 115),
  // a thin crêpe of 22-24 cm
  'Crepe, NFS': ('1 crepe, any size', 50),
  'Crepe, plain': ('1 crepe, any size', 45),
  // a boiled potato of 90 g, a baked one of 200 g, as EU shops grade them
  'Potato, boiled, NFS': ('1 medium', 90),
  'Potatoes, boiled, cooked without skin, flesh, without salt': (
    '1 medium (2-1/4" to 3-1/4" dia.)',
    90,
  ),
  'Potatoes, boiled, cooked without skin, flesh, with salt': (
    '1 medium (2-1/4" to 2-1/4" dia.)',
    90,
  ),
  'Potato, baked, NFS': ('1 medium', 200),
  // a veal escalope of 125 g raw
  'Veal, leg, top round, cap off, cutlet, boneless, cooked, grilled': (
    '1 cutlet',
    100,
  ),
  'Veal, leg, top round, cap off, cutlet, boneless, raw': ('1 cutlet', 125),
  // a grilling sausage of 75 g, not a 35 g breakfast patty
  'Sausage, NFS': ('1 sausage', 75),
  'Pork sausage': ('1 sausage', 75),
  'Beef sausage': ('1 sausage', 75),
  // a plain bagel of 100 g
  'Bagel': ('1 bagel', 100),
  // a sandwich slice of ham of 25 g, of salami 10 g, of cheese 21 g
  'Ham': ('1 regular/thin slice', 25),
  'Salami, NFS': ('1 slice', 10),
  'Cheese, NFS': ('1 slice', 21),
  // one pot pie, not the 1,260 g family dish
  'Pot pie, chicken': ('1 pie', 250),
  // a Frankfurter of 50 g, sold in pairs
  'Frankfurter, pork': ('1 link', 50),
  // a potato pancake of 70 g, as for draniki or Reibekuchen
  'Potato pancakes': ('1 pancake', 70),
  // a strudel piece of 125 g, an eighth of a 1 kg strudel
  'Strudel, apple': ('1 piece', 125),
  // a boxed chocolate of 8 g, not a miniature bar
  'Chocolate candy': ('1 piece', 8),
  // a baklava piece of 35 g, a brioche bun of 50 g
  'Baklava': ('1 piece', 35),
  'Brioche': ('1 piece', 50),
};

/// Ladders whose middle piece is a US size, rescaled to a European one
/// (S213), by name, label and the table's weight: a muffin of 85 g, a
/// slice of cake of 110 g, a cookie of 18-22 g, a pancake of 33 g, a slice
/// of pie of 115 g. A serving that was that piece moves with it.
final pieceRescales = <(RegExp, Set<String>, double, double)>[
  (RegExp(r'^Muffin'), {'1 medium'}, 130, 85),
  (RegExp(r'^(Cake|Cheesecake)'), {'1 piece/slice, any size'}, 175, 110),
  (RegExp(r'^(Cake|Cheesecake)'), {'1 piece/slice, any size'}, 200, 110),
  (RegExp(r'^Cookie'), {'1 medium', '1 medium cookie'}, 30, 18),
  (RegExp(r'^Cookie'), {'1 medium', '1 medium cookie'}, 42, 22),
  (RegExp(r'^Pancakes'), {'1 medium pancake'}, 50, 33),
  (RegExp(r'^Pie, '), {'1 regular slice'}, 150, 115),
];

/// The rescale of [name]'s [label] at [grams], or null.
double? _rescaled(String? name, String label, double grams) {
  if (name == null) return null;
  for (final (pattern, labels, from, to) in pieceRescales) {
    if (grams == from && labels.contains(label) && pattern.hasMatch(name)) {
      return to;
    }
  }
  return null;
}

/// A whole pie read as the middle of a pie's ladder, so "1 apple pie" was
/// 1,200 g (S213). Named without the word, a count of pies is a slice of
/// one, and "1 whole apple pie" still finds it.
const _wholePieLabels = {
  '1 regular pie (8-9" dia)': '1 whole (8-9" dia)',
  '1 large pie (10" dia plus)': '1 whole, large (10" dia plus)',
};

/// [row] with its [servingOverrides] serving, or its [addedPieces] one
/// where the table gives it none.
Map<String, Object?> _withAddedPiece(Map<String, Object?> row) {
  if (servingOverrides[row['name']] case (final size, final grams)) {
    return {...row, 'serving_size': size, 'serving_gram_weight': grams};
  }
  if (row['serving_gram_weight'] case final num grams) {
    final name = row['name'] as String?;
    for (final (pattern, _, from, to) in pieceRescales) {
      if (grams == from && name != null && pattern.hasMatch(name)) {
        return {...row, 'serving_gram_weight': to};
      }
    }
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
              label:
                  _wholePieLabels[portion[0] as String] ?? portion[0] as String,
              gramWeight: (portion[1] as num).toDouble(),
              localized: false,
            ),
        ],
    };
    for (final food in foods) {
      final list = portions[food.foodId];
      if (list == null) continue;
      for (var i = 0; i < list.length; i++) {
        final to = _rescaled(food.name, list[i].label, list[i].gramWeight);
        if (to == null) continue;
        list[i] = MealPortionEntity(
          label: list[i].label,
          gramWeight: to,
          localized: false,
        );
      }
      // An override's own label gives way to it, which leads the list.
      if (servingOverrides[food.name] case (final size, _)) {
        list.removeWhere((p) => p.label.toLowerCase() == size.toLowerCase());
      }
    }
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
      if (list.isNotEmpty && (list.first.gramWeight - grams).abs() < 0.5) {
        continue;
      }
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
/// Both sides folded to plain letters ([foldLetters]): "sasliks" typed on
/// an English keyboard finds "Shashlik, chicken (vistas šašliks, ...)".
List<String> nameWords(String? text) => foldLetters(text ?? '')
    .split(RegExp(r'[^\p{L}\p{N}]+', unicode: true))
    .where((w) => w.isNotEmpty)
    .toList();

/// [text] lower-cased, its Latvian, Lithuanian, Estonian, Polish, German
/// and common Latin letters with marks made plain.
String foldLetters(String text) {
  final lower = text.toLowerCase();
  if (!_marked.hasMatch(lower)) return lower;
  return lower.split('').map((c) => _plainLetters[c] ?? c).join();
}

final _marked = RegExp(r'[^\x00-\x7f]');

const _plainLetters = {
  'ā': 'a',
  'ä': 'a',
  'á': 'a',
  'à': 'a',
  'â': 'a',
  'ã': 'a',
  'å': 'a',
  'ą': 'a',
  'č': 'c',
  'ç': 'c',
  'ć': 'c',
  'ē': 'e',
  'é': 'e',
  'è': 'e',
  'ê': 'e',
  'ë': 'e',
  'ę': 'e',
  'ė': 'e',
  'ģ': 'g',
  'ī': 'i',
  'í': 'i',
  'ì': 'i',
  'î': 'i',
  'ï': 'i',
  'į': 'i',
  'ķ': 'k',
  'ļ': 'l',
  'ł': 'l',
  'ņ': 'n',
  'ñ': 'n',
  'ń': 'n',
  'ō': 'o',
  'ö': 'o',
  'ó': 'o',
  'ò': 'o',
  'ô': 'o',
  'õ': 'o',
  'ø': 'o',
  'š': 's',
  'ś': 's',
  'ß': 'ss',
  'ū': 'u',
  'ü': 'u',
  'ú': 'u',
  'ù': 'u',
  'û': 'u',
  'ų': 'u',
  'ž': 'z',
  'ź': 'z',
  'ż': 'z',
};

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
