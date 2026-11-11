// The fork's dishes in the bundled table (fork/data/dishes.json, built by
// fork/tools/build_food_db.py): every dish has an id of its own and its own
// serving as its portion. Diary entries and recents keep a food's id, so a
// dish's id never changes; two dishes on one id gave each the other's
// serving (Caesar wrap's "1 serving" logged a 90 g cutlet).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/fork/food/local_food_data_source.dart';

/// Every dish's id, by its code: the ids the released tables gave them.
/// Chicken cutlets, pork cutlets and chłodnik took ids Caesar wrap,
/// rassolnik and Olivier salad had held since the first release, so they
/// moved to ids of their own above the highest.
const _ids = {
  'solyanka': 30000000,
  'cepelinai': 30000001,
  'salmon-soup': 30000002,
  'grey-peas': 30000003,
  'potato-balls': 30000004,
  'green-salad': 30000005,
  'chicken-plov': 30000006,
  'khachapuri': 30000007,
  'syrniki': 30000008,
  'kharcho': 30000009,
  'beef-kofta': 30000010,
  'odzhakhuri': 30000011,
  'chicken-poke-bowl': 30000012,
  'beet-salad': 30000013,
  'chicken-schnitzel': 30000014,
  'pork-chop-cheese': 30000015,
  'chicken-teriyaki': 30000016,
  'chicken-shawarma': 30000017,
  'pork-shashlik': 30000018,
  'butter-chicken': 30000019,
  'thai-green-curry': 30000020,
  'liver-patties': 30000021,
  'kimchi-pancake': 30000022,
  'fish-cutlets': 30000023,
  'caesar-wrap': 30000024,
  'rassolnik': 30000025,
  'olivier-salad': 30000026,
  'japchae': 30000027,
  'chicken-saganaki': 30000028,
  'okroshka': 30000029,
  'lamb-biryani': 30000030,
  'honey-cake': 30000031,
  'pork-bulgogi': 30000032,
  'korean-fried-chicken': 30000033,
  'chili-con-carne': 30000034,
  'beef-lasagna': 30000035,
  'kvass': 30000036,
  'borscht-beef': 30000037,
  'chicken-shashlik': 30000038,
  'lula-kebab': 30000039,
  'chicken_rice_soup': 30000043,
  'makarony_po_flotski': 30000044,
  'millet_pumpkin_porridge': 30000045,
  'braised_cabbage_meat': 30000046,
  'chicken-cutlets': 30000047,
  'pork-cutlets': 30000048,
  'chlodnik': 30000049,
};

void main() {
  late List<List<dynamic>> rows;
  late Map<String, dynamic> portions;
  late List<Map<String, dynamic>> dishes;
  late LocalFoodTable table;

  setUpAll(() async {
    final bytes = await File(LocalFoodDataSource.assetPath).readAsBytes();
    final json =
        jsonDecode(utf8.decode(gzip.decode(bytes))) as Map<String, dynamic>;
    rows = (json['foods'] as List).cast<List<dynamic>>();
    portions = json['portions'] as Map<String, dynamic>;
    dishes =
        ((jsonDecode(await File('fork/data/dishes.json').readAsString())
                    as Map)['dishes']
                as List)
            .cast<Map<String, dynamic>>();
    table = LocalFoodTable.fromGzip(bytes);
  });

  test('no two rows of the table share a food id', () {
    final seen = <int>{};
    final twice = [
      for (final row in rows)
        if (!seen.add(row[0] as int)) row[0],
    ];
    expect(twice, isEmpty);
  });

  test('every dish of dishes.json is one row, on its own id', () {
    final dishRows = [
      for (final row in rows)
        if (row[1] == 'fork_dishes') row,
    ];
    expect(dishRows, hasLength(dishes.length));
    for (final dish in dishes) {
      final found = dishRows.where((row) => row[2] == dish['code']).toList();
      expect(found, hasLength(1), reason: dish['code'] as String);
      expect(found.single[0], dish['id'], reason: dish['code'] as String);
    }
  });

  test('a dish keeps the id the released tables gave it', () {
    final idOf = {
      for (final row in rows)
        if (row[1] == 'fork_dishes') row[2] as String: row[0] as int,
    };
    for (final MapEntry(key: code, value: id) in _ids.entries) {
      expect(idOf[code], id, reason: code);
    }
    // a dish added later takes an id above every one before it
    final pinnedTop = _ids.values.reduce((a, b) => a > b ? a : b);
    for (final MapEntry(key: code, value: id) in idOf.entries) {
      if (!_ids.containsKey(code)) {
        expect(id, greaterThan(pinnedTop), reason: code);
      }
    }
  });

  test('a dish\'s portions are its own serving alone', () {
    for (final dish in dishes) {
      final serving = dish['serving'] as List;
      expect(portions['${dish['id']}'], [
        [serving[0], serving[1]],
      ], reason: dish['code'] as String);
    }
  });

  test('the app loads each dish with its own serving first', () {
    for (final dish in dishes) {
      final id = dish['id'] as int;
      final serving = dish['serving'] as List;
      final food = table.foods.singleWhere((f) => f.foodId == id);
      expect(food.sourceCode, dish['code']);
      expect(food.servingSize, serving[0], reason: dish['code'] as String);
      expect(food.servingGramWeight, (serving[1] as num).toDouble());
      final first = table.portions[id]!.first;
      expect(
        (first.label, first.gramWeight),
        (serving[0], (serving[1] as num).toDouble()),
        reason: dish['code'] as String,
      );
    }
  });

  test('the dishes that shared an id log their own servings', () async {
    final source = LocalFoodDataSource(
      loadTable: () async => table,
      readToggles: () async => null,
    );
    final expected = {
      30000024: ('Caesar wrap', '1 wrap', 255.0),
      30000025: ('Rassolnik', '1 bowl', 350.0),
      30000026: ('Olivier salad', '1 bowl', 150.0),
      30000047: ('Chicken cutlets', '1 cutlet', 90.0),
      30000048: ('Pork cutlets', '1 cutlet', 90.0),
      30000049: ('Chłodnik', '1 bowl', 300.0),
    };
    final loaded = (await source.fetchPortions(expected.keys.toList()))!;
    for (final MapEntry(key: id, value: (name, label, grams))
        in expected.entries) {
      final food = table.foods.singleWhere((f) => f.foodId == id);
      expect(food.name, startsWith(name));
      expect(food.servingGramWeight, grams, reason: name);
      expect(
        [for (final p in loaded[id]!) (p.label, p.gramWeight)],
        [(label, grams)],
        reason: name,
      );
    }
  });
}
