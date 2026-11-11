// What v0.9.0 to v0.10.1 saved for chicken cutlets, pork cutlets and
// chłodnik, on the ids Caesar wrap, rassolnik and Olivier salad keep, moves
// to the dishes' own ids once (lib/fork/food/moved_dish_ids.dart).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:opennutritracker/core/data/dbo/favourite_meal_dbo.dart';
import 'package:opennutritracker/core/data/dbo/intake_dbo.dart';
import 'package:opennutritracker/core/data/dbo/intake_type_dbo.dart';
import 'package:opennutritracker/core/data/dbo/meal_dbo.dart';
import 'package:opennutritracker/core/data/dbo/meal_nutriments_dbo.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/fork/food/moved_dish_ids.dart';
import 'package:opennutritracker/fork/plan/plan_store.dart';

import '../../helpers/hive_test_setup.dart';

// The names the released tables stored (openbite-v0.9.0 to v0.10.1).
const _chickenCutlets =
    'Chicken cutlets, fried (cāļa kotletes, minced chicken patties, '
    'chicken kotlety)';
const _porkCutlets =
    'Pork cutlets, fried (cūkgaļas kotletes, minced pork patties, '
    'pork kotlety, meat patties)';
const _chlodnik =
    'Chłodnik, cold beet soup with kefir (chlodnik, cold beetroot soup, '
    'chilled borscht, cold borscht, aukstā zupa, šaltibarščiai, holodnik)';
const _caesarWrap = 'Caesar wrap, chicken (chicken caesar wrap)';
const _rassolnik = 'Rassolnik, pickle soup with barley (rasolnik, rasoļņiks)';
const _olivier = 'Olivier salad (Russian salad, salat olivye, rasols)';

MealDBO _meal(
  String code,
  String name, {
  MealSourceDBO source = MealSourceDBO.fdc,
  String? backendSource = 'fork_dishes',
}) => MealDBO(
  code: code,
  name: name,
  brands: null,
  thumbnailImageUrl: null,
  mainImageUrl: null,
  url: null,
  mealQuantity: null,
  mealUnit: 'g',
  servingQuantity: 90,
  servingUnit: 'g',
  servingSize: '1 cutlet',
  nutriments: MealNutrimentsDBO(
    energyKcal100: 215,
    carbohydrates100: 9,
    fat100: 13,
    proteins100: 16,
    sugars100: 1,
    saturatedFat100: 3,
    fiber100: 0.5,
  ),
  source: source,
  backendSource: backendSource,
  dataVersion: MealDBO.currentDataVersion,
);

IntakeDBO _intake(String id, MealDBO meal) => IntakeDBO(
  id: id,
  unit: 'g',
  amount: 180,
  type: IntakeTypeDBO.lunch,
  meal: meal,
  dateTime: DateTime(2026, 9, 14, 13, 5),
);

void main() {
  group('movedDishCode', () {
    test('each moved dish, by its stored name, gets its own id', () {
      expect(movedDishCode('30000024', _chickenCutlets), '30000047');
      expect(movedDishCode('30000025', _porkCutlets), '30000048');
      expect(movedDishCode('30000026', _chlodnik), '30000049');
    });

    test('the title decides, in any case, whatever the brackets say', () {
      expect(movedDishCode('30000024', 'CHICKEN CUTLETS'), '30000047');
      expect(movedDishCode('30000025', 'pork cutlets (my way)'), '30000048');
      expect(movedDishCode('30000026', 'Chlodnik, cold soup'), '30000049');
    });

    test("today's table has these dishes on these ids", () {
      final dishes =
          (jsonDecode(File('fork/data/dishes.json').readAsStringSync())
                  as Map)['dishes']
              as List;
      final byCode = {for (final d in dishes) d['code']: d};
      for (final (code, old) in [
        ('chicken-cutlets', '30000024'),
        ('pork-cutlets', '30000025'),
        ('chlodnik', '30000026'),
      ]) {
        final dish = byCode[code] as Map;
        expect(movedDishCode(old, dish['name'] as String), '${dish['id']}');
      }
      for (final (code, id) in [
        ('caesar-wrap', 30000024),
        ('rassolnik', 30000025),
        ('olivier-salad', 30000026),
      ]) {
        expect(byCode[code]['id'], id);
      }
    });

    test('the dishes that kept the ids stay', () {
      expect(movedDishCode('30000024', _caesarWrap), isNull);
      expect(movedDishCode('30000025', _rassolnik), isNull);
      expect(movedDishCode('30000026', _olivier), isNull);
    });

    test('any other name, or a moved name on another id, stays', () {
      expect(movedDishCode('30000024', 'Chicken cutlet sandwich'), isNull);
      expect(movedDishCode('30000024', 'My lunch'), isNull);
      expect(movedDishCode('30000024', null), isNull);
      expect(movedDishCode('30000025', _chickenCutlets), isNull);
      expect(movedDishCode('30000023', _chickenCutlets), isNull);
      expect(movedDishCode('30000047', _chickenCutlets), isNull);
      expect(movedDishCode(null, _chickenCutlets), isNull);
    });
  });

  group('movedDishMeal', () {
    test('only the id changes', () {
      final before = _meal('30000024', _chickenCutlets);
      final after = movedDishMeal(before);
      expect(after.code, '30000047');
      expect(after.name, before.name);
      expect(identical(after.nutriments, before.nutriments), isTrue);
      expect(after.servingQuantity, 90);
      expect(after.servingSize, '1 cutlet');
      expect(after.backendSource, 'fork_dishes');
      expect(after.dataVersion, before.dataVersion);
    });

    test('a row of the table with no source recorded moves too', () {
      final meal = _meal('30000024', _chickenCutlets, backendSource: null);
      expect(movedDishMeal(meal).code, '30000047');
    });

    test("the user's own food, or another table's row, is never touched", () {
      for (final meal in [
        _meal('30000024', _chickenCutlets, source: MealSourceDBO.custom),
        _meal('30000024', _chickenCutlets, source: MealSourceDBO.off),
        _meal('30000024', _chickenCutlets, backendSource: 'bls'),
        _meal('30000024', _caesarWrap),
      ]) {
        expect(identical(movedDishMeal(meal), meal), isTrue);
      }
    });

    test('an intake keeps its amount, unit, meal and date', () {
      final before = _intake('a', _meal('30000026', _chlodnik));
      final after = movedDishIntake(before);
      expect(after.meal.code, '30000049');
      expect(after.id, 'a');
      expect(after.amount, 180);
      expect(after.unit, 'g');
      expect(after.type, IntakeTypeDBO.lunch);
      expect(after.dateTime, DateTime(2026, 9, 14, 13, 5));
      final kept = _intake('b', _meal('30000026', _olivier));
      expect(identical(movedDishIntake(kept), kept), isTrue);
    });
  });

  group('MovedDishIds.run', () {
    late Directory dir;
    late Box<bool> installFlags;
    late Box<dynamic> profileBox;
    late Box<IntakeDBO> intakes;
    late Box<FavouriteMealDBO> favourites;
    late Box<MealDBO> cache;
    late Box<int> cacheTimes;
    var tag = 0;

    MovedDishIds fixup({Box<IntakeDBO> Function()? intakesBox}) => MovedDishIds(
      installFlags: () async => installFlags,
      profileBox: () async => profileBox,
      intakes: intakesBox ?? () => intakes,
      favourites: () => favourites,
      searchCache: () => cache,
      searchCacheTimestamps: () => cacheTimes,
    );

    setUpAll(() {
      dir = Directory.systemTemp.createTempSync('moved_dish_ids');
      Hive.init(dir.path);
      registerHiveAdaptersOnce();
    });

    setUp(() async {
      tag++;
      installFlags = await Hive.openBox<bool>('flags_$tag');
      profileBox = await Hive.openBox<dynamic>('profile_$tag');
      intakes = await Hive.openBox<IntakeDBO>('intakes_$tag');
      favourites = await Hive.openBox<FavouriteMealDBO>('favourites_$tag');
      cache = await Hive.openBox<MealDBO>('cache_$tag');
      cacheTimes = await Hive.openBox<int>('cache_times_$tag');
    });

    tearDownAll(() async {
      await Hive.close();
      await dir.delete(recursive: true).catchError((_) => dir);
    });

    Future<void> seed() async {
      await intakes.putAll({
        'cutlets': _intake('cutlets', _meal('30000024', _chickenCutlets)),
        'wrap': _intake('wrap', _meal('30000024', _caesarWrap)),
        'pork': _intake('pork', _meal('30000025', _porkCutlets)),
        'soup': _intake('soup', _meal('30000025', _rassolnik)),
        'chlodnik': _intake('chlodnik', _meal('30000026', _chlodnik)),
        'salad': _intake('salad', _meal('30000026', _olivier)),
        'own': _intake(
          'own',
          _meal('30000024', _chickenCutlets, source: MealSourceDBO.custom),
        ),
      });
      final favourite = _meal('30000025', _porkCutlets);
      await favourites.put(
        FavouriteMealDBO.keyFor(
          favourite.source,
          favourite.code,
          favourite.name,
        ),
        FavouriteMealDBO(meal: favourite, addedAt: DateTime(2026, 8, 1)),
      );
      final kept = _meal('30000026', _olivier);
      await favourites.put(
        FavouriteMealDBO.keyFor(kept.source, kept.code, kept.name),
        FavouriteMealDBO(meal: kept, addedAt: DateTime(2026, 8, 2)),
      );
      await PlanStore(() async => profileBox).add(
        [
          (
            meal: MealEntity.fromMealDBO(_meal('30000026', _chlodnik)),
            unit: 'g',
            amountText: '300',
            kcal: 150,
          ),
          (
            meal: MealEntity.fromMealDBO(_meal('30000024', _caesarWrap)),
            unit: 'g',
            amountText: '255',
            kcal: 500,
          ),
        ],
        IntakeTypeEntity.dinner,
        DateTime(2026, 11, 12),
      );
      await cache.add(_meal('30000024', _chickenCutlets));
      await cache.add(_meal('30000025', _rassolnik));
      await cacheTimes.put('30000024', 1000);
      await cacheTimes.put('30000025', 2000);
    }

    test('the diary: the moved three get their ids, the rest stay', () async {
      await seed();
      await fixup().run();
      final codes = {for (final i in intakes.values) i.id: i.meal.code};
      expect(codes, {
        'cutlets': '30000047',
        'wrap': '30000024',
        'pork': '30000048',
        'soup': '30000025',
        'chlodnik': '30000049',
        'salad': '30000026',
        'own': '30000024',
      });
      for (final i in intakes.values) {
        expect(i.amount, 180);
        expect(i.dateTime, DateTime(2026, 9, 14, 13, 5));
        expect(i.meal.nutriments.energyKcal100, 215);
      }
    });

    test('a favourite goes under its new key; the other stays', () async {
      await seed();
      await fixup().run();
      expect(
        favourites.keys,
        unorderedEquals(['fdc:30000048', 'fdc:30000026']),
      );
      final moved = favourites.get('fdc:30000048')!;
      expect(moved.meal.code, '30000048');
      expect(moved.meal.name, _porkCutlets);
      expect(moved.addedAt, DateTime(2026, 8, 1));
    });

    test('the meal plan logs the moved dish under its id', () async {
      await seed();
      await fixup().run();
      final planned = await PlanStore(() async => profileBox).all();
      expect([for (final p in planned) p.meal.code], ['30000049', '30000024']);
      expect(planned.first.meal.name, _chlodnik);
      expect(planned.first.amountText, '300');
    });

    test('the search cache entry and its time move', () async {
      await seed();
      await fixup().run();
      expect([for (final m in cache.values) m.code], ['30000047', '30000025']);
      expect(cacheTimes.get('30000047'), 1000);
      expect(cacheTimes.containsKey('30000024'), isFalse);
      expect(cacheTimes.get('30000025'), 2000);
    });

    test('sets both flags, and a second run changes nothing', () async {
      await seed();
      await fixup().run();
      expect(installFlags.get(MovedDishIds.installFlag), isTrue);
      expect(profileBox.get(MovedDishIds.profileFlag), isTrue);
      final before = {for (final i in intakes.values) i.id: i.meal.code};
      // As if a restore brought an old entry back: the flag keeps it as is.
      await intakes.put(
        'late',
        _intake('late', _meal('30000024', _chickenCutlets)),
      );
      await fixup().run();
      expect(
        {for (final i in intakes.values) i.id: i.meal.code},
        {...before, 'late': '30000024'},
      );
    });

    test('a pass without its flags finds nothing left to move', () async {
      await seed();
      await profileBox.put(MovedDishIds.profileFlag, false);
      await fixup().run();
      await installFlags.delete(MovedDishIds.installFlag);
      await profileBox.delete(MovedDishIds.profileFlag);
      // Already moved: a second pass finds nothing and writes nothing.
      await fixup().run();
      expect(intakes.get('cutlets')!.meal.code, '30000047');
      expect(favourites.length, 2);
      expect(cacheTimes.get('30000047'), 1000);
    });

    test('a failure is logged, not thrown, and leaves the flag off', () async {
      await seed();
      await expectLater(
        fixup(intakesBox: () => throw StateError('box closed')).run(),
        completes,
      );
      expect(profileBox.get(MovedDishIds.profileFlag), isNull);
      // The install's part does not depend on the profile's.
      expect(installFlags.get(MovedDishIds.installFlag), isTrue);
      await fixup().run();
      expect(intakes.get('cutlets')!.meal.code, '30000047');
      expect(profileBox.get(MovedDishIds.profileFlag), isTrue);
    });
  });
}
