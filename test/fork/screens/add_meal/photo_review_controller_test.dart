// Which amount a photo's review row carries, without the screen: the
// expected amounts are those the widget tests of the screen pin
// (usual_sizes_test.dart, history_offer_test.dart, meal_size_test.dart).
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/meal_photo_interpreter.dart';
import 'package:opennutritracker/features/add_meal/domain/usecase/read_meal_photo_usecase.dart';
import 'package:opennutritracker/features/add_meal/domain/usecase/read_meal_text_usecase.dart';
import 'package:opennutritracker/features/add_meal/domain/usecase/resolve_parsed_meals_usecase.dart';
import 'package:opennutritracker/features/add_meal/presentation/bloc/bulk_add_bloc.dart';
import 'package:opennutritracker/features/add_meal/util/meal_text_parser.dart';
import 'package:opennutritracker/fork/bulk/photo_meal_memory.dart';
import 'package:opennutritracker/fork/screens/add_meal/photo_review_controller.dart';

/// Foods named otherwise than the model's words, as the fork's own dishes.
final _dishNames = <String, String>{};

/// 100 kcal per 100 g, so a row's grams are its kcal.
MealEntity _meal(String name) => MealEntity(
  code: name,
  name: _dishNames[name] ?? name,
  backendSource: _dishNames.containsKey(name) ? 'fork_dishes' : null,
  url: null,
  mealQuantity: null,
  mealUnit: 'g',
  servingQuantity: null,
  servingUnit: null,
  servingSize: null,
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

class _Resolver implements ResolveParsedMealsUseCase {
  @override
  Future<List<ResolvedMealItem>> resolve(
    List<ParsedMealItem> items, {
    bool fromPhoto = false,
  }) async => [
    for (final item in items)
      ResolvedMealItem(
        parsed: item,
        candidates: [_meal(item.query)],
        selectedIndex: 0,
        confidence: 1,
      ),
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PhotoReader implements ReadMealPhotoUseCase {
  List<ParsedMealItem> items = const [];

  @override
  Future<MealPhotoReadResult> read(
    MealPhoto photo, {
    String? localeCode,
    String? note,
  }) async =>
      MealPhotoRead(MealTextParseResult(items: items, errors: const []));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TextReader implements ReadMealTextUseCase {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _rice = ParsedMealItem(query: 'rice', quantity: 150, unit: 'g');
const _chicken = ParsedMealItem(query: 'chicken', quantity: 100, unit: 'g');
const _salad = ParsedMealItem(query: 'salad', quantity: 80, unit: 'g');
const _pasta = ParsedMealItem(query: 'pasta', quantity: 200, unit: 'g');

final _today = DateUtils.dateOnly(DateTime.now());

/// The dinner the user corrected a week ago: more rice and chicken than
/// the photo shows, and no salad.
PhotoMealRecord _dinner() {
  final day = DateTime(_today.year, _today.month, _today.day - 7);
  PhotoMealFood food(String name, double grams) =>
      PhotoMealFood(key: name, name: name, amount: grams, kcal: grams);
  return PhotoMealRecord(
    day: day,
    loggedAt: day.add(const Duration(hours: 19)),
    slot: 'dinner',
    foods: [food('rice', 300), food('chicken', 200)],
    kcal: 500,
    corrected: true,
  );
}

/// A dinner logged [daysAgo] days ago, the photo's rice at ×0.7, chicken
/// at ×0.8 and salad at ×0.75; not corrected.
PhotoMealRecord _sized(int daysAgo) {
  final day = DateTime(_today.year, _today.month, _today.day - daysAgo);
  PhotoMealFood food(String name, double grams, double photo) => PhotoMealFood(
    key: name,
    name: name,
    amount: grams,
    kcal: grams,
    photoAmount: photo,
  );
  return PhotoMealRecord(
    day: day,
    loggedAt: day.add(const Duration(hours: 19)),
    slot: 'dinner',
    foods: [
      food('rice', 105, 150),
      food('chicken', 80, 100),
      food('salad', 60, 80),
    ],
    kcal: 0,
    corrected: false,
  );
}

void main() {
  late BulkAddBloc bloc;
  late _PhotoReader reader;
  late List<PhotoMealRecord> kept;
  // while set, holds the memory's reading back
  Completer<void>? gate;
  late PhotoReviewController review;

  setUp(() {
    _dishNames.clear();
    reader = _PhotoReader();
    bloc = BulkAddBloc(_Resolver(), _TextReader(), reader);
    kept = [];
    gate = null;
    review = PhotoReviewController(
      bloc,
      note: () => null,
      records: () async {
        await gate?.future;
        return [...kept];
      },
      cookingFatFood: (_) async => null,
    );
  });
  tearDown(() async {
    review.dispose();
    await bloc.close();
  });

  List<BulkAddRow> rows() => (bloc.state as BulkAddLoadedState).rows;
  List<String> amounts() => [for (final row in rows()) row.amountText];

  Future<void> read([
    List<ParsedMealItem> items = const [_rice, _chicken, _salad],
  ]) async {
    reader.items = items;
    bloc.add(
      ReadMealPhotoEvent(
        photo: MealPhoto(
          bytes: Uint8List.fromList([1]),
          mediaType: 'image/webp',
        ),
        usesImperialUnits: false,
      ),
    );
    await pumpEventQueue();
  }

  /// Row [index] set by the user to [text], as the screen's steppers do.
  Future<void> setByUser(int index, String text) async {
    review.pinRow(index);
    bloc.add(ChangeRowAmountEvent(index, text));
    await pumpEventQueue();
  }

  Future<void> size(double factor) async {
    review.setMealSize(factor);
    await pumpEventQueue();
  }

  group('usual sizes', () {
    test('applied on arrival; "Use the photo\'s amounts" puts the photo\'s '
        'bases back, and the usual sizes come back with their size', () async {
      kept.addAll([_sized(1), _sized(2), _sized(3)]);
      await read();
      expect(amounts(), ['105', '80', '60']);
      expect(review.usualInForce, isTrue);
      expect(review.usualShown(rows()), isTrue);
      expect(
        [for (final f in review.usualFoods) (f.name, f.factor)],
        [('rice', 0.7), ('chicken', 0.8), ('salad', 0.75)],
      );
      expect(review.mealScale.factor, 1);

      await size(1.2);
      expect(amounts(), ['126', '96', '72']);

      review.usePhotoAmounts();
      await pumpEventQueue();
      expect(amounts(), ['150', '100', '80']);
      expect(review.mealScale.factor, 1);
      expect(review.usualInForce, isFalse);
      // the line stays, to bring them back
      expect(review.usualShown(rows()), isTrue);
      expect(rows().any((row) => row.amountEditedByUser), isFalse);

      await size(0.8);
      expect(amounts(), ['120', '80', '64']);

      review.useUsualSizes();
      await pumpEventQueue();
      expect(amounts(), ['126', '96', '72']);
      expect(review.mealScale.factor, 1.2);
      expect(review.usualInForce, isTrue);
    });

    test('a dish is named as its row reads', () async {
      _dishNames['rice'] = 'Plov, chicken (chicken pilaf, pilau)';
      kept.addAll([_sized(1), _sized(2), _sized(3)]);
      await read();
      expect(review.usualFoods.first.name, 'Plov, chicken');
    });

    test('none with 2 like corrections', () async {
      kept.addAll([_sized(1), _sized(2)]);
      await read();
      expect(amounts(), ['150', '100', '80']);
      expect(review.usualShown(rows()), isFalse);
      expect(review.usualInForce, isFalse);
    });

    test('a row the user set before the memory was read is left alone, '
        'and stays as set both ways', () async {
      kept.addAll([_sized(1), _sized(2), _sized(3)]);
      final held = gate = Completer<void>();
      await read();
      await setByUser(1, '110');

      held.complete();
      await pumpEventQueue();
      expect(amounts(), ['105', '110', '60']);
      expect([for (final f in review.usualFoods) f.name], ['rice', 'salad']);

      review.usePhotoAmounts();
      await pumpEventQueue();
      expect(amounts(), ['150', '110', '80']);
      review.useUsualSizes();
      await pumpEventQueue();
      expect(amounts(), ['105', '110', '60']);
    });

    test('not applied once a size was chosen', () async {
      kept.addAll([_sized(1), _sized(2), _sized(3)]);
      final held = gate = Completer<void>();
      await read();
      await size(1.2);
      expect(amounts(), ['180', '120', '96']);

      held.complete();
      await pumpEventQueue();
      expect(amounts(), ['180', '120', '96']);
      expect(review.usualShown(rows()), isFalse);
    });
  });

  group('the cooking fat question', () {
    // fried in the model's words, a plain food in the table's
    setUp(() => _dishNames['egg, fried'] = 'Egg, whole');
    const egg = ParsedMealItem(query: 'egg, fried', quantity: 100, unit: 'g');
    const oil = ParsedMealItem(query: 'olive oil', quantity: 5, unit: 'g');

    test('None after a chip gives the read\'s oil back as read: the Size '
        'scales it, and the meal is not corrected', () async {
      await read(const [egg, oil]);
      expect(review.fatAsk, isNotNull);
      await review.chooseCookingFat(1);
      await pumpEventQueue();
      expect(amounts(), ['100', '15']);
      expect(review.photoCorrected(rows()), isTrue);

      await review.chooseCookingFat(-1);
      await pumpEventQueue();
      expect(amounts(), ['100', '5']);
      expect(review.mealScale.isPinned(rows()[1]), isFalse);
      expect(review.photoCorrected(rows()), isFalse);
      await size(1.4);
      expect(amounts(), ['140', '7']);
    });

    test('None at another size than the chip\'s: the oil at its read grams '
        'times the size now', () async {
      await read(const [egg, oil]);
      await review.chooseCookingFat(1);
      await pumpEventQueue();
      await size(1.4);
      await review.chooseCookingFat(-1);
      await pumpEventQueue();
      expect(amounts(), ['140', '7']);
      await size(1);
      expect(amounts(), ['100', '5']);

      await read(const [egg, oil]);
      await size(1.4);
      await review.chooseCookingFat(1);
      await pumpEventQueue();
      expect(amounts(), ['140', '17']);
      await review.chooseCookingFat(-1);
      await pumpEventQueue();
      expect(amounts(), ['140', '7']);
      await size(1);
      expect(amounts(), ['100', '5']);
    });

    test('a hand edit of the oil after None counts', () async {
      await read(const [egg, oil]);
      await review.chooseCookingFat(1);
      await pumpEventQueue();
      await review.chooseCookingFat(-1);
      await pumpEventQueue();
      await setByUser(1, '12');
      await setByUser(1, '5');
      expect(review.photoCorrected(rows()), isTrue);
    });

    test(
      'None after a chip keeps another amount the user set counted',
      () async {
        await read(const [egg, oil]);
        await review.chooseCookingFat(1);
        await pumpEventQueue();
        await setByUser(0, '120');
        await setByUser(0, '100');
        await review.chooseCookingFat(-1);
        await pumpEventQueue();
        expect(amounts(), ['100', '5']);
        expect(review.photoCorrected(rows()), isTrue);
      },
    );

    test(
      'None after a chip leaves an oil the user set before it set',
      () async {
        await read(const [egg, oil]);
        await setByUser(1, '5');
        await review.chooseCookingFat(1);
        await pumpEventQueue();
        await review.chooseCookingFat(-1);
        await pumpEventQueue();
        expect(review.mealScale.isPinned(rows()[1]), isTrue);
        await size(1.4);
        expect(amounts(), ['140', '5']);
      },
    );
  });

  group('a remembered meal', () {
    test('its amounts used and undone bring back the bases and the size '
        'before', () async {
      kept.add(_dinner());
      await read();
      expect(review.history, isNotNull);
      expect(review.historyShown(rows()), isTrue);
      await size(1.2);
      expect(amounts(), ['180', '120', '96']);
      // what the tap will give: the salad back at the photo's 80
      expect(
        [for (final row in review.withHistory(rows())) row.amountText],
        ['300', '200', '80'],
      );

      review.useHistory();
      await pumpEventQueue();
      expect(amounts(), ['300', '200', '80']);
      expect(review.mealScale.factor, 1);
      expect(review.historyTaken, isTrue);
      expect(rows().any((row) => row.amountEditedByUser), isFalse);

      // the salad from the photo's 80, not from the 96 it was at
      await size(0.6);
      expect(amounts(), ['180', '120', '48']);

      review.undoHistory();
      await pumpEventQueue();
      expect(amounts(), ['180', '120', '96']);
      expect(review.mealScale.factor, 1.2);
      expect(review.historyTaken, isFalse);
      expect(review.historyShown(rows()), isTrue);

      await size(1);
      expect(amounts(), ['150', '100', '80']);
    });

    test('over the usual sizes: a food it does not cover keeps its usual '
        'amount, and Undo brings the usual sizes back', () async {
      kept.addAll([_dinner(), _sized(1), _sized(2), _sized(3)]);
      await read();
      expect(amounts(), ['105', '80', '60']);

      review.useHistory();
      await pumpEventQueue();
      expect(amounts(), ['300', '200', '60']);
      expect(review.usualShown(rows()), isFalse);
      expect(review.usualInForce, isFalse);

      review.undoHistory();
      await pumpEventQueue();
      expect(amounts(), ['105', '80', '60']);
      expect(review.usualInForce, isTrue);
    });

    test('a row the user set keeps its amount', () async {
      kept.add(_dinner());
      await read();
      await setByUser(1, '110');
      review.useHistory();
      await pumpEventQueue();
      expect(amounts(), ['300', '110', '80']);
    });

    test('the amount question on a row that took an amount goes, and Undo '
        'does not bring it back', () async {
      kept.add(_dinner());
      await read();
      expect(review.amountQuestion?.isFor(rows()[0]), isTrue);

      review.useHistory();
      await pumpEventQueue();
      expect(review.amountQuestion, isNull);
      review.undoHistory();
      await pumpEventQueue();
      expect(review.amountQuestion, isNull);
    });

    test('Log: corrected with its amounts used, and at the photo\'s own '
        'amounts', () async {
      kept.add(_dinner());
      await read();
      expect(review.photoCorrected(rows()), isFalse);
      review.useHistory();
      await pumpEventQueue();
      expect(review.photoCorrected(rows()), isTrue);
      expect(
        [for (final row in rows()) review.photoAmountOf(row)],
        [150, 100, 80],
      );
    });
  });

  group('the meal\'s Size', () {
    test('leaves a row the user set', () async {
      await read();
      await setByUser(1, '110');
      await size(1.2);
      expect(amounts(), ['180', '110', '96']);
      expect(review.mealScale.isPinned(rows()[1]), isTrue);
      await size(1);
      expect(amounts(), ['150', '110', '80']);
    });

    test('a size chosen and put back is not a correction; a size is', () async {
      await read();
      await size(1.2);
      expect(review.photoCorrected(rows()), isTrue);
      await size(1);
      expect(review.photoCorrected(rows()), isFalse);
    });
  });

  group('the amount question', () {
    test('chosen once per read, on the row with the most energy, and kept '
        'through later states of the read', () async {
      await read();
      final question = review.amountQuestion;
      expect(question?.isFor(rows()[0]), isTrue);

      await size(1.2);
      expect(review.amountQuestion, same(question));
      // the rice no longer the most energy: still the rice's question
      bloc.add(const ChangeRowAmountEvent(1, '400'));
      await pumpEventQueue();
      expect(review.amountQuestion, same(question));
    });

    test('ended by the user setting its row, and not asked of another row on '
        'the next state', () async {
      await read();
      await setByUser(0, '200');
      expect(review.amountQuestion, isNull);
      await size(1.2);
      expect(review.amountQuestion, isNull);
    });
  });

  group('a new read', () {
    test('starts over: As shown, nothing set, nothing used, a question of '
        'its own', () async {
      kept.add(_dinner());
      await read();
      final first = review.amountQuestion;
      await size(1.2);
      await setByUser(2, '90');
      review.useHistory();
      await pumpEventQueue();
      expect(review.historyTaken, isTrue);
      await size(1.4);

      await read();
      expect(amounts(), ['150', '100', '80']);
      expect(review.mealScale.factor, 1);
      expect(review.historyTaken, isFalse);
      expect(rows().any(review.mealScale.isPinned), isFalse);
      expect(review.photoCorrected(rows()), isFalse);
      expect(review.amountQuestion, isNot(same(first)));
      expect(review.amountQuestion?.isFor(rows()[0]), isTrue);
      // found anew for this read
      expect(review.history, isNotNull);
    });

    test('a memory read for the read before is not offered on it', () async {
      kept.add(_dinner());
      final held = gate = Completer<void>();
      await read();
      expect(review.history, isNull);

      await read(const [_pasta]);
      held.complete();
      await pumpEventQueue();
      expect(review.history, isNull);
      expect(review.historyShown(rows()), isFalse);
    });
  });
}
