import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/fork/leftovers/group_leftovers.dart';
import 'package:opennutritracker/fork/leftovers/meal_groups.dart';

IntakeEntity _intake(String id, String name, double amount) => IntakeEntity(
  id: id,
  unit: 'g',
  amount: amount,
  type: IntakeTypeEntity.lunch,
  meal: MealEntity(
    code: id,
    name: name,
    url: null,
    mealQuantity: null,
    mealUnit: 'g',
    servingQuantity: null,
    servingUnit: 'g',
    servingSize: null,
    nutriments: MealNutrimentsEntity.empty(),
    source: MealSourceEntity.custom,
  ),
  dateTime: DateTime.utc(2026, 10, 22),
);

final _rice = _intake('rice', 'Rice', 200);
final _curry = _intake('curry', 'Curry', 300);
final _naan = _intake('naan', 'Naan', 90);

void main() {
  late Directory dir;
  late MealGroupStore store;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('meal_groups');
    Hive.init(dir.path);
    store = MealGroupStore();
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    await dir.delete(recursive: true);
  });

  group('MealGroupStore', () {
    test('every entry of a meal finds the whole group', () async {
      await store.record(['rice', 'curry', 'naan'], DateTime(2026, 10, 22));

      expect((await store.groupOf('curry'))!.intakeIds, [
        'rice',
        'curry',
        'naan',
      ]);
      expect(await store.groupOf('soup'), isNull);
    });

    test('a single entry is not recorded as a group', () async {
      await store.record(['rice'], DateTime(2026, 10, 22));

      expect(await store.groupOf('rice'), isNull);
    });
  });

  group('amountsAfterLeftovers', () {
    test('takes the same share off every entry', () {
      expect(amountsAfterLeftovers([_rice, _curry], fraction: 0.25), {
        'rice': 150,
        'curry': 225,
      });
    });

    test('an amount left of one entry overrides the share for it', () {
      expect(
        amountsAfterLeftovers(
          [_rice, _curry],
          fraction: 0.5,
          overrides: {'rice': 20},
        ),
        {'rice': 180, 'curry': 150},
      );
    });

    test('ignores more left than was logged', () {
      expect(amountsAfterLeftovers([_rice], overrides: {'rice': 250}), {
        'rice': 200,
      });
    });
  });

  group('editMealGroupLeftovers', () {
    final entries = {
      for (final i in [_rice, _curry, _naan]) i.id: i,
    };

    /// Taps an entry and returns whether the fork handled the edit, plus
    /// the updates it made.
    Future<(Future<bool>, Map<String, double>)> tap(
      WidgetTester tester,
      IntakeEntity intake,
    ) async {
      final updates = <String, double>{};
      late Future<bool> handled;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => handled = editMealGroupLeftovers(
                context,
                intake,
                store: store,
                intakeById: (id) async => entries[id],
                update: (id, amount) async => updates[id] = amount,
              ),
              child: const Text('tap'),
            ),
          ),
        ),
      );
      await tester.runAsync(
        () => store.record(['rice', 'curry', 'naan'], DateTime(2026, 10, 22)),
      );
      await tester.tap(find.text('tap'));
      // The store reads Hive's file, which fake time does not advance.
      await tester.runAsync(() => Future.delayed(Duration(milliseconds: 50)));
      await tester.pumpAndSettle();
      return (handled, updates);
    }

    testWidgets('half of the meal left, none of the naan', (tester) async {
      final (handled, updates) = await tap(tester, _curry);

      await tester.tap(find.text(LeftoverStrings.wholeMeal(3)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('½'));
      await tester.pump();
      await tester.enterText(find.byKey(const ValueKey('left-naan')), '0');
      await tester.pump();
      await tester.tap(find.text(LeftoverStrings.save));
      await tester.pumpAndSettle();

      expect(await handled, isTrue);
      // The naan was all eaten, so it is left as logged.
      expect(updates, {'rice': 100, 'curry': 150});
    });

    testWidgets('just this item leaves the edit to the usual dialog', (
      tester,
    ) async {
      final (handled, updates) = await tap(tester, _curry);

      await tester.tap(find.text(LeftoverStrings.justThis));
      await tester.pumpAndSettle();

      expect(await handled, isFalse);
      expect(updates, isEmpty);
    });

    testWidgets('cancelling changes nothing', (tester) async {
      final (handled, updates) = await tap(tester, _rice);

      await tester.tap(find.text(LeftoverStrings.wholeMeal(3)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('¼'));
      await tester.tap(find.text(LeftoverStrings.cancel));
      await tester.pumpAndSettle();

      expect(await handled, isTrue);
      expect(updates, isEmpty);
    });
  });
}
