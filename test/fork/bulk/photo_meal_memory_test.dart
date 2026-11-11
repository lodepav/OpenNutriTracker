import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:opennutritracker/core/data/dbo/profile_dbo.dart';
import 'package:opennutritracker/core/utils/hive_db_provider.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_portion_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/usecase/resolve_parsed_meals_usecase.dart';
import 'package:opennutritracker/features/add_meal/presentation/bloc/bulk_add_bloc.dart';
import 'package:opennutritracker/features/add_meal/util/meal_text_parser.dart';
import 'package:opennutritracker/features/add_meal/util/portion_unit.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_store.dart';
import 'package:opennutritracker/fork/backup/profile_wipe.dart';
import 'package:opennutritracker/fork/bulk/meal_scale.dart';
import 'package:opennutritracker/fork/bulk/photo_meal_memory.dart';
import 'package:opennutritracker/fork/bulk/photo_meal_memory_store.dart';
import 'package:opennutritracker/fork/dish/dish_breakdown_rows.dart';

import '../../helpers/fake_hive_db_provider.dart';
import '../../helpers/hive_test_setup.dart';

/// 100 kcal per 100 g, so a row's grams are its kcal.
MealEntity _food(
  String name, {
  String? code,
  double? serving,
  List<MealPortionEntity> portions = const [],
}) => MealEntity(
  code: code ?? name,
  name: name,
  url: null,
  mealQuantity: null,
  mealUnit: 'g',
  servingQuantity: serving,
  servingUnit: serving == null ? null : 'g',
  servingSize: serving == null ? null : '1 piece ($serving g)',
  portions: portions,
  source: MealSourceEntity.fdc,
  nutriments: const MealNutrimentsEntity(
    energyKcal100: 100,
    carbohydrates100: 0,
    fat100: 0,
    proteins100: 0,
    sugars100: null,
    saturatedFat100: null,
    fiber100: null,
  ),
);

/// A photo's row of [grams] g of [name].
BulkAddRow _row(
  String name,
  double grams, {
  bool skipped = false,
  ParsedMealItem? parsed,
  MealEntity? food,
  String unit = 'g',
  String? amount,
}) => BulkAddRow(
  resolved: ResolvedMealItem(
    parsed: parsed ?? ParsedMealItem(query: name, quantity: grams, unit: 'g'),
    candidates: [food ?? _food(name)],
    selectedIndex: 0,
    confidence: 1,
  ),
  selectedIndex: 0,
  amountText: amount ?? _text(grams),
  unit: unit,
  skipped: skipped,
  fromPhoto: true,
);

String _text(double value) =>
    value == value.roundToDouble() ? value.toInt().toString() : '$value';

final _now = DateTime(2026, 11, 11, 19);

/// A record of [foods] (name to grams; kcal the same), [daysAgo] days
/// before [_now].
PhotoMealRecord _record(
  Map<String, double> foods, {
  int daysAgo = 3,
  bool corrected = true,
  String? dish,
  int minute = 0,
}) {
  final day = DateTime(_now.year, _now.month, _now.day - daysAgo);
  return PhotoMealRecord(
    day: day,
    loggedAt: day.add(Duration(hours: 19, minutes: minute)),
    slot: 'dinner',
    dish: dish,
    foods: [
      for (final MapEntry(key: name, value: grams) in foods.entries)
        PhotoMealFood(key: name, name: name, amount: grams, kcal: grams),
    ],
    kcal: foods.values.fold(0.0, (a, b) => a + b),
    corrected: corrected,
  );
}

PhotoMealRecord? _match(
  Iterable<PhotoMealRecord> records,
  Set<String> keys, {
  String? dish,
}) => matchingRecord(records, keys: keys, dish: dish, now: _now)?.record;

/// [rows] with [amounts] set, as `ScaleRowsEvent` sets them.
List<BulkAddRow> _apply(
  List<BulkAddRow> rows,
  Map<ResolvedMealItem, String> amounts,
) => [
  for (final row in rows)
    switch (amounts[row.resolved]) {
      final text? => row.copyWith(amountText: text),
      null => row,
    },
];

void main() {
  group('matching on foods', () {
    test('2 shared of 3 foods match, either side holding the third', () {
      final record = _record({'rice': 200, 'chicken': 150});
      expect(_match([record], {'rice', 'chicken', 'salad'}), same(record));
      final wider = _record({'rice': 200, 'chicken': 150, 'salad': 50});
      expect(_match([wider], {'rice', 'chicken'}), same(wider));
    });

    test('an overlap of exactly 0.6 matches; under it does not', () {
      // 3 shared of 5
      final record = _record({'a': 100, 'b': 100, 'c': 100, 'd': 100});
      expect(_match([record], {'a', 'b', 'c', 'e'}), same(record));
      // 2 shared of 4: 0.5
      final half = _record({'a': 100, 'b': 100, 'c': 100});
      expect(_match([half], {'a', 'b', 'd'}), isNull);
    });

    test('one shared food is not enough, however alike', () {
      expect(
        _match(
          [
            _record({'rice': 200}),
          ],
          {'rice'},
        ),
        isNull,
      );
    });
  });

  group('matching on a dish name', () {
    test('a one-food dish matches on its name and that food', () {
      final record = _record({'plov': 400}, dish: 'Plov');
      expect(_match([record], {'plov'}, dish: ' plov '), same(record));
      expect(_match([record], {'plov'}, dish: 'pilaf'), isNull);
      expect(_match([record], {'plov'}), isNull);
    });

    test('half the foods shared is enough, under half is not', () {
      final record = _record({'rice': 200, 'lamb': 100}, dish: 'plov');
      expect(_match([record], {'rice'}, dish: 'PLOV'), same(record));
      expect(_match([record], {'rice', 'carrot'}, dish: 'plov'), isNull);
    });
  });

  test('only corrected records of the last 120 days; the most recent wins', () {
    final keys = {'rice', 'chicken'};
    final foods = {'rice': 200.0, 'chicken': 150.0};
    expect(_match([_record(foods, corrected: false)], keys), isNull);
    expect(_match([_record(foods, daysAgo: 121)], keys), isNull);
    final last = _record(foods, daysAgo: 120);
    expect(_match([last], keys), same(last));

    final older = _record(foods, daysAgo: 10);
    final newer = _record(foods, daysAgo: 2);
    final newest = _record(foods, daysAgo: 1, corrected: false);
    expect(_match([newer, older, newest], keys), same(newer));
    final later = _record(foods, daysAgo: 2, minute: 30);
    expect(_match([later, newer], keys), same(later));
    expect(_match([newer, later], keys), same(later));
  });

  group('an offer for a read', () {
    final rows = [_row('rice', 150), _row('chicken', 100), _row('salad', 80)];

    PhotoMealMatch? offer(
      List<BulkAddRow> rows,
      List<PhotoMealRecord> records, {
      String? note,
    }) => photoMealMatchFor(rows, records, note: note, now: _now);

    test('when the shared foods then differ by 10% or more', () {
      // 270 then against 250: 8%
      expect(
        offer(rows, [
          _record({'rice': 150, 'chicken': 120}),
        ]),
        isNull,
      );
      // 225 against 250: 10%
      final record = _record({'rice': 125, 'chicken': 100});
      expect(offer(rows, [record])?.record, same(record));
      final match = offer(rows, [
        _record({'rice': 300, 'chicken': 200}),
      ])!;
      expect(match.kind, PhotoMealMatchKind.foods);
      expect(match.sharedAtArrival, 2);
    });

    test('not on a weighed plate', () {
      expect(
        offer(rows, [
          _record({'rice': 300, 'chicken': 200}),
        ], note: '200g rice'),
        isNull,
      );
    });

    test('not when the note states every count', () {
      final rows = [
        _row(
          'egg',
          2,
          parsed: const ParsedMealItem(query: 'egg', quantity: 2),
          food: _food('egg', serving: 50),
          unit: 'serving',
        ),
        _row('rice', 150),
      ];
      final record = _record({'egg': 150, 'rice': 250});
      expect(offer(rows, [record]), isNotNull);
      expect(offer(rows, [record], note: 'with 2 eggs'), isNull);
    });

    test('not when no shared food may be scaled', () {
      final left = [
        _row('rice', 150, skipped: true),
        _row('chicken', 100, skipped: true),
        _row('salad', 80),
      ];
      expect(
        offer(left, [
          _record({'rice': 300, 'chicken': 200}),
        ]),
        isNull,
      );
      // the app's 100 g default is no amount to correct
      final defaulted = [
        _row('rice', 100, parsed: const ParsedMealItem(query: 'rice')),
        _row('chicken', 100, parsed: const ParsedMealItem(query: 'chicken')),
      ];
      expect(
        offer(defaulted, [
          _record({'rice': 300, 'chicken': 200}),
        ]),
        isNull,
      );
    });

    test('by the dish the read arrived as', () {
      final group = Object();
      final plov = [
        _row(
          'plov',
          400,
          parsed: DishIngredientItem(
            query: 'plov',
            quantity: 400,
            unit: 'g',
            dish: 'Plov',
            group: group,
          ),
        ),
      ];
      final record = _record({'plov': 550}, dish: 'plov');
      final match = offer(plov, [record])!;
      expect(match.kind, PhotoMealMatchKind.dish);
      expect(photoMealMatchStands(plov, match), isTrue);
      expect(
        photoMealMatchStands([
          _row('plov', 400, skipped: true, parsed: plov.single.resolved.parsed),
        ], match),
        isFalse,
      );
    });

    test('stands while 2 shared foods are there', () {
      final match = offer(rows, [
        _record({'rice': 300, 'chicken': 200}),
      ])!;
      expect(photoMealMatchStands(rows, match), isTrue);
      expect(
        photoMealMatchStands([
          rows[0],
          _row('chicken', 100, skipped: true),
          rows[2],
        ], match),
        isFalse,
      );
      expect(photoMealMatchStands([rows[0], rows[2]], match), isFalse);
    });
  });

  group('the amounts taken', () {
    test('in the row\'s own unit, to the half piece; others left', () {
      final bread = _food(
        'bread',
        portions: const [
          MealPortionEntity(label: '1 slice', gramWeight: 30, localized: true),
        ],
      );
      final rows = [
        _row('rice', 150),
        _row('bread', 60, food: bread, unit: portionUnit(0), amount: '2'),
        _row('salad', 80),
      ];
      final amounts = photoMealAmounts(
        rows,
        _record({'rice': 212.4, 'bread': 100, 'tea': 250}),
        canTake: (_) => true,
      );
      expect(amounts[rows[0].resolved], '212');
      expect(amounts[rows[1].resolved], '3.5');
      expect(amounts.containsKey(rows[2].resolved), isFalse);
      expect(amounts.length, 2);
    });

    test('a quarter piece then comes back as a quarter', () {
      final bread = _food(
        'bread',
        portions: const [
          MealPortionEntity(label: '1 slice', gramWeight: 30, localized: true),
        ],
      );
      final rows = [
        _row('bread', 30, food: bread, unit: portionUnit(0), amount: '1'),
        _row('rice', 150),
      ];
      final amounts = photoMealAmounts(
        rows,
        _record({'bread': 7.5, 'rice': 200}),
        canTake: (_) => true,
      );
      expect(amounts[rows[0].resolved], '0.25');
    });

    test('two rows of one food share it as they shared the photo\'s', () {
      final rows = [_row('rice', 100), _row('rice', 300)];
      final amounts = photoMealAmounts(
        rows,
        _record({'rice': 200, 'chicken': 100}),
        canTake: (_) => true,
      );
      expect(amounts[rows[0].resolved], '50');
      expect(amounts[rows[1].resolved], '150');
    });

    test('only rows [canTake] allows', () {
      final rows = [_row('rice', 150), _row('chicken', 100)];
      final amounts = photoMealAmounts(
        rows,
        _record({'rice': 200, 'chicken': 150}),
        canTake: (row) => !identical(row, rows[1]),
      );
      expect(amounts.keys, [same(rows[0].resolved)]);
    });
  });

  group('the meal\'s Size from the amounts taken', () {
    test('they are its bases, unpinned, at "As shown", the other rows back '
        'at the photo\'s; restore puts the photo\'s back at the size '
        'before', () {
      var rows = [_row('rice', 150), _row('chicken', 100), _row('salad', 80)];
      final scale = MealScale()..follow(rows);
      scale.factor = 0.8;
      rows = _apply(rows, scale.follow(rows));
      expect(rows.map((r) => r.amountText), ['120', '80', '64']);

      final before = scale.snapshot();
      final set = scale.rebase(rows, {
        rows[0].resolved: '250',
        rows[1].resolved: '200',
      });
      expect(scale.factor, 1);
      rows = _apply(rows, set);
      expect(rows.map((r) => r.amountText), ['250', '200', '80']);
      // arriving is not taken for the user's edit
      expect(scale.follow(rows), isEmpty);
      expect(rows.any(scale.isPinned), isFalse);

      scale.factor = 1.2;
      rows = _apply(rows, scale.retarget(rows));
      expect(rows.map((r) => r.amountText), ['300', '240', '96']);

      rows = _apply(rows, scale.restore(rows, before));
      expect(scale.factor, 0.8);
      expect(rows.map((r) => r.amountText), ['120', '80', '64']);
      expect(scale.follow(rows), isEmpty);
      expect(rows.any(scale.isPinned), isFalse);
    });

    test('a row the user set keeps its amount', () {
      var rows = [_row('rice', 150), _row('chicken', 100)];
      final scale = MealScale()..follow(rows);
      rows = [rows[0], rows[1].copyWith(amountText: '120')];
      scale.follow(rows);
      expect(scale.isPinned(rows[1]), isTrue);
      final set = scale.rebase(rows, {
        rows[0].resolved: '250',
        rows[1].resolved: '200',
      });
      expect(set.keys, [same(rows[0].resolved)]);
    });
  });

  group('a record of a logged meal', () {
    test('holds each food logged in grams, its energy, and the total', () {
      final rows = [
        _row('rice', 150),
        _row('chicken', 100, skipped: true),
        _row('salad', 80, food: _food('salad', code: '')),
      ];
      final record = photoMealRecordOf(
        rows,
        day: DateTime(2026, 11, 4, 20),
        loggedAt: DateTime(2026, 11, 4, 20, 5),
        slot: 'dinner',
        corrected: true,
      )!;
      expect(record.day, DateTime(2026, 11, 4));
      expect(record.foods.map((f) => f.key), ['rice', 'name:salad']);
      expect(record.foods.map((f) => f.amount), [150, 80]);
      expect(record.foods.map((f) => f.kcal), [150, 80]);
      expect(record.kcal, 230);

      final back = PhotoMealRecord.fromJson(record.toJson());
      expect(back.toJson(), record.toJson());
      expect(back.dish, isNull);
    });

    test('holds the photo\'s own amounts and the meal\'s size, and reads '
        'back with and without them', () {
      final rows = [_row('rice', 120), _row('chicken', 100)];
      final record = photoMealRecordOf(
        rows,
        day: _now,
        loggedAt: _now,
        slot: 'dinner',
        corrected: false,
        photoAmountOf: (row) => row.meal!.name == 'rice' ? 150 : null,
        size: 0.8,
      )!;
      expect(record.foods.map((f) => f.photoAmount), [150, null]);
      expect(record.size, 0.8);
      final json = record.toJson();
      expect((json['foods'] as List).first, containsPair('photoAmount', 150));
      expect((json['foods'] as List).last, isNot(contains('photoAmount')));
      final back = PhotoMealRecord.fromJson(json);
      expect(back.toJson(), json);
      expect(back.size, 0.8);
      expect(back.foods.first.photoAmount, 150);

      // a record kept before them reads with none
      final old = Map<String, Object>.of(json)
        ..remove('size')
        ..['foods'] = [
          for (final food in json['foods'] as List)
            Map<String, Object>.of(food as Map<String, Object>)
              ..remove('photoAmount'),
        ];
      final older = PhotoMealRecord.fromJson(old);
      expect(older.size, isNull);
      expect(older.foods.map((f) => f.photoAmount), [null, null]);
      expect(older.toJson(), old);
    });

    test('none when nothing is logged', () {
      expect(
        photoMealRecordOf(
          [_row('rice', 150, skipped: true)],
          day: _now,
          loggedAt: _now,
          slot: 'lunch',
          corrected: false,
        ),
        isNull,
      );
    });

    test('a read\'s dish is the one dish its foods are under', () {
      final group = Object();
      DishIngredientItem item(String name, String dish, Object group) =>
          DishIngredientItem(
            query: name,
            quantity: 100,
            unit: 'g',
            dish: dish,
            group: group,
          );
      final rice = _row('rice', 100, parsed: item('rice', 'plov', group));
      final lamb = _row('lamb', 100, parsed: item('lamb', 'plov', group));
      expect(readDishName([rice, lamb, _row('salad', 50)]), 'plov');
      expect(
        readDishName([
          rice,
          _row('soup', 100, parsed: item('soup', 'borscht', Object())),
        ]),
        isNull,
      );
      expect(readDishName([_row('salad', 50)]), isNull);
    });
  });

  group('the store', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('photo_meal_memory');
      Hive.init(dir.path);
    });

    tearDown(() async {
      await Hive.deleteFromDisk();
      await dir.delete(recursive: true);
    });

    test(
      'keeps records, and lets go of those past 120 days on a write',
      () async {
        final box = await Hive.openBox<dynamic>('memory');
        final store = PhotoMealMemoryStore(() async => box);
        final old = _record({'rice': 1}, daysAgo: 121, minute: 1);
        final kept = _record({'rice': 2}, daysAgo: 120, minute: 2);
        await box.put('unreadable', '${old.toJson()}');
        await store.add(old, now: _now.subtract(const Duration(days: 30)));
        await store.add(kept, now: _now.subtract(const Duration(days: 30)));
        expect(box.length, 2, reason: 'one that does not read goes');
        expect((await store.records(now: _now)).map((r) => r.kcal), [2]);

        final fresh = _record({'rice': 3}, daysAgo: 0, minute: 3);
        await store.add(fresh, now: _now);
        expect(box.length, 2);
        expect((await store.records(now: _now)).map((r) => r.kcal).toSet(), {
          2,
          3,
        });
      },
    );

    test('holds nothing without the app\'s database', () async {
      final store = PhotoMealMemoryStore();
      await store.add(_record({'rice': 1}));
      expect(await store.records(), isEmpty);
    });

    group('with profiles', () {
      setUp(() async {
        registerHiveAdaptersOnce();
        final profiles = await Hive.openBox<ProfileDBO>('profiles');
        for (final id in ['a', 'b']) {
          await profiles.put(
            id,
            ProfileDBO(
              id: id,
              name: id,
              createdAt: DateTime(2026),
              boxSuffix: '_$id',
            ),
          );
        }
        locator.registerSingleton<HiveDBProvider>(
          _Provider(profileBox: profiles),
        );
      });

      tearDown(() async {
        await locator.unregister<HiveDBProvider>();
        AdaptiveStore.settings.value = const AdaptiveSettings();
      });

      test('the active profile\'s, emptied with its data; another '
          'profile\'s stays, and each goes with its profile', () async {
        final db = locator<HiveDBProvider>();
        await PhotoMealMemoryStore().add(_record({'rice': 1}), now: _now);
        final other = await db.openScopedBox<dynamic>(
          PhotoMealMemoryStore.boxName,
          '_b',
        );
        await other.put('k', 'v');
        expect(await PhotoMealMemoryStore().records(now: _now), hasLength(1));
        expect(
          (await db.openScopedBox<dynamic>(
            PhotoMealMemoryStore.boxName,
            '_a',
          )).length,
          1,
        );

        await clearForkProfileData();

        expect(await PhotoMealMemoryStore().records(now: _now), isEmpty);
        expect(other.get('k'), 'v');
        expect(forkProfileBoxes, contains(PhotoMealMemoryStore.boxName));
        expect(
          HiveDBProvider.perProfileBoxNames,
          contains(PhotoMealMemoryStore.boxName),
        );
      });
    });
  });
}

/// Profiles' scoped boxes as plain boxes on disk.
class _Provider extends FakeHiveDBProvider {
  _Provider({required super.profileBox}) : super(activeProfileId: 'a');

  @override
  Future<Box<E>> openScopedBox<E>(String baseName, String boxSuffix) =>
      Hive.openBox<E>(HiveDBProvider.boxNameFor(baseName, boxSuffix));
}
