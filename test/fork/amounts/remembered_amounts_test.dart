import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:opennutritracker/core/data/dbo/intake_dbo.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/fork/amounts/remembered_amounts.dart';

import '../../fixture/meal_entity_fixtures.dart';

MealEntity _food(String? code, String name) => MealEntity(
  code: code,
  name: name,
  url: null,
  mealQuantity: '100',
  mealUnit: 'g',
  servingQuantity: null,
  servingUnit: null,
  servingSize: null,
  nutriments: MealEntityFixtures.mealOne.nutriments,
  source: MealSourceEntity.custom,
);

IntakeDBO _entry(MealEntity food, double amount, String unit, int day) =>
    IntakeDBO.fromIntakeEntity(
      IntakeEntity(
        id: '${food.name}-$day-$unit',
        unit: unit,
        amount: amount,
        type: IntakeTypeEntity.dinner,
        meal: food,
        dateTime: DateTime(2026, 10, day, 19),
      ),
    );

void main() {
  late Directory dir;
  late RememberedAmounts amounts;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('amounts');
    Hive.init(dir.path);
    amounts = RememberedAmounts(() => Hive.openBox<dynamic>('amounts'));
  });

  tearDown(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  test('the last amount logged is kept per food', () async {
    final oats = _food('123', 'Oats');
    expect(await amounts.of(oats), isNull);

    await amounts.remember(oats, 'g', '40');
    await amounts.remember(oats, 'serving', '1.5');
    await amounts.remember(_food('456', 'Milk'), 'ml', '200');

    expect(await amounts.of(oats), (unit: 'serving', quantity: '1.5'));
  });

  test('a food without a barcode is known by its name', () async {
    await amounts.remember(_food(null, 'Soup'), 'g', '300');
    expect(await amounts.of(_food('', 'Soup')), (unit: 'g', quantity: '300'));
    expect(await amounts.of(_food(null, 'Stew')), isNull);
  });

  test('past the limit the least recently logged food goes', () async {
    for (var i = 0; i < RememberedAmounts.limit; i++) {
      await amounts.remember(_food('$i', 'Food $i'), 'g', '$i');
    }
    // Logged again, so the second food is now the oldest.
    await amounts.remember(_food('0', 'Food 0'), 'g', '7');
    await amounts.remember(_food('new', 'New'), 'g', '1');

    expect(await amounts.of(_food('0', '')), (unit: 'g', quantity: '7'));
    expect(await amounts.of(_food('1', '')), isNull);
    expect(await amounts.of(_food('new', '')), isNotNull);
  });

  test('an unreadable box reads as nothing remembered', () async {
    final broken = RememberedAmounts(() => throw StateError('no box'));
    expect(await broken.of(_food('1', 'x')), isNull);
    await broken.remember(_food('1', 'x'), 'g', '1');
  });

  group('with nothing remembered', () {
    final rice = _food(null, 'Brown rice');
    RememberedAmounts withDiary(List<IntakeDBO> diary) => RememberedAmounts(
      () => Hive.openBox<dynamic>('amounts'),
      () async => diary,
    );

    test('the latest entry in grams is the amount', () async {
      final diary = [
        _entry(rice, 200, 'g', 20),
        _entry(rice, 640, 'g', 23),
        _entry(_food(null, 'Oats'), 40, 'g', 24),
      ];
      expect(await withDiary(diary).of(rice), (unit: 'g', quantity: '640'));
    });

    test('an entry in servings or ounces is passed over', () async {
      final diary = [
        _entry(rice, 150.5, 'g', 20),
        _entry(rice, 2, 'serving', 23),
        _entry(rice, 3, 'oz', 24),
      ];
      expect(await withDiary(diary).of(rice), (unit: 'g', quantity: '150.5'));
    });

    test('a remembered amount wins over the diary', () async {
      final amounts = withDiary([_entry(rice, 640, 'g', 23)]);
      await amounts.remember(rice, 'g', '120');
      expect(await amounts.of(rice), (unit: 'g', quantity: '120'));
    });

    test('an unreadable diary reads as nothing', () async {
      final amounts = RememberedAmounts(
        () => Hive.openBox<dynamic>('amounts'),
        () => throw StateError('no diary'),
      );
      expect(await amounts.of(rice), isNull);
    });
  });
}
