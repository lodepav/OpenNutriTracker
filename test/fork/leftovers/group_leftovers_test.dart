import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/core/utils/ai_credential_storage.dart';
import 'package:opennutritracker/features/add_meal/domain/meal_photo_interpreter.dart';
import 'package:opennutritracker/features/add_meal/util/meal_text_parser.dart';
import 'package:opennutritracker/fork/leftovers/ai_leftovers.dart';
import 'package:opennutritracker/fork/leftovers/group_leftovers.dart';
import 'package:opennutritracker/fork/leftovers/meal_groups.dart';
import 'package:opennutritracker/fork/leftovers/meal_photo_cache.dart';

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

final _photo = MealPhoto(
  bytes: Uint8List.fromList([1, 2, 3]),
  mediaType: 'image/webp',
);

/// A model that answers [answer], or none set up when [selected] is null.
class _Reader implements ReadLeftoversUseCase {
  final AiSelection? selected;
  final Map<String, double>? answer;
  MealPhoto? sawMeal;

  _Reader({this.selected, this.answer});

  @override
  Future<AiSelection?> get selection async => selected;

  @override
  Future<Map<String, double>?> read(
    List<IntakeEntity> entries,
    MealPhoto leftovers, {
    MealPhoto? meal,
  }) async {
    sawMeal = meal;
    return answer;
  }
}

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
      IntakeEntity intake, {
      _Reader? reader,
    }) async {
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
                leftovers: reader ?? _Reader(),
                photoCache: MealPhotoCache(dir: () async => dir),
                takePhoto: (_) async => _photo,
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

    testWidgets('a photo of the leftovers fills in what is left', (
      tester,
    ) async {
      final reader = _Reader(
        selected: const AiSelection(provider: AiProvider.anthropic),
        // The model left the naan out: all of it was eaten.
        answer: {'rice': 50, 'curry': 100},
      );
      final (handled, updates) = await tap(tester, _rice, reader: reader);

      await tester.tap(find.text(LeftoverStrings.wholeMeal(3)));
      await tester.pumpAndSettle();
      await tester.tap(find.text(LeftoverStrings.readPhoto));
      await tester.runAsync(() => Future.delayed(Duration(milliseconds: 50)));
      await tester.pumpAndSettle();

      expect(find.text(LeftoverStrings.aiEstimate), findsOneWidget);
      await tester.tap(find.text(LeftoverStrings.save));
      await tester.pumpAndSettle();
      expect(await handled, isTrue);
      expect(updates, {'rice': 150, 'curry': 200});
      // No photo was kept for this meal.
      expect(reader.sawMeal, isNull);
    });

    testWidgets('without a model there is no photo button', (tester) async {
      await tap(tester, _rice);

      await tester.tap(find.text(LeftoverStrings.wholeMeal(3)));
      await tester.pumpAndSettle();

      expect(find.text(LeftoverStrings.readPhoto), findsNothing);
    });
  });

  group('MealPhotoCache', () {
    var now = DateTime(2026, 10, 22, 12);
    MealPhotoCache cache() => MealPhotoCache(
      dir: () async => Directory('${dir.path}/photos'),
      now: () => now,
    );

    test('keeps a photo for 24 hours', () async {
      now = DateTime(2026, 10, 22, 12);
      final path = await cache().save(_photo);

      now = DateTime(2026, 10, 23, 11);
      expect((await cache().read(path))!.bytes, _photo.bytes);
      now = DateTime(2026, 10, 23, 12);
      expect(await cache().read(path), isNull);
      await cache().prune();
      expect(File(path!).existsSync(), isFalse);
    });

    test('turned off, keeps nothing and deletes what it kept', () async {
      now = DateTime(2026, 10, 22, 12);
      final kept = await cache().save(_photo);

      await cache().setEnabled(false);

      expect(File(kept!).existsSync(), isFalse);
      expect(await cache().save(_photo), isNull);
    });

    test('a meal group keeps the path of its photo', () async {
      await recordMealGroup(
        ['rice', 'curry'],
        photo: _photo,
        store: store,
        cache: cache(),
      );

      final group = await store.groupOf('rice');
      expect(await cache().read(group!.photoPath), isNotNull);
    });
  });

  group('AI leftovers', () {
    test('the prompt lists every entry with its amount and unit', () {
      final prompt = leftoversSystemPrompt([_rice, _naan], withMealPhoto: true);

      expect(prompt, startsWith(leftoversPromptStart));
      expect(prompt, contains('1. Rice: 200 g\n2. Naan: 90 g'));
      expect(prompt, contains('on the left the meal as served'));
    });

    test('maps items to entries by name, in their own unit', () {
      final left = leftoversFromItems(
        [_rice, _curry, _naan],
        const [
          ParsedMealItem(query: 'rice', quantity: 40, unit: 'g'),
          // More than was logged is all of it.
          ParsedMealItem(query: 'Curry', quantity: 900),
          // Another unit cannot be compared, a new food is not an entry.
          ParsedMealItem(query: 'Naan', quantity: 1, unit: 'serving'),
          ParsedMealItem(query: 'Chutney', quantity: 20, unit: 'g'),
        ],
      );

      expect(left, {'rice': 40, 'curry': 300});
    });

    test('two entries of one food each take one item', () {
      final left = leftoversFromItems(
        [_intake('bread1', 'Bread', 60), _intake('bread2', 'Bread', 30)],
        const [
          ParsedMealItem(query: 'Bread', quantity: 20, unit: 'g'),
          ParsedMealItem(query: 'Bread', quantity: 10, unit: 'g'),
        ],
      );

      expect(left, {'bread1': 20, 'bread2': 10});
    });
  });
}
