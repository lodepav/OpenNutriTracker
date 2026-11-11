import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/usecase/resolve_parsed_meals_usecase.dart';
import 'package:opennutritracker/features/add_meal/presentation/bloc/bulk_add_bloc.dart';
import 'package:opennutritracker/features/add_meal/util/meal_text_parser.dart';
import 'package:opennutritracker/fork/bulk/photo_meal_memory.dart';
import 'package:opennutritracker/fork/bulk/usual_sizes.dart';
import 'package:opennutritracker/fork/dish/dish_strings.dart';
import 'package:opennutritracker/fork/screens/add_meal/usual_sizes_view.dart';

final _now = DateTime(2026, 11, 11, 19);

/// A record [daysAgo] days before [_now], at [size], of [foods]: name to
/// (logged, photo) grams; a null photo amount is a food added by hand.
PhotoMealRecord _record(
  int daysAgo, {
  double? size = 1,
  Map<String, (double, double?)> foods = const {'rice': (150, 150)},
}) {
  final day = DateTime(_now.year, _now.month, _now.day - daysAgo);
  return PhotoMealRecord(
    day: day,
    loggedAt: day.add(const Duration(hours: 19)),
    slot: 'dinner',
    foods: [
      for (final MapEntry(key: name, value: (logged, photo)) in foods.entries)
        PhotoMealFood(
          key: name,
          name: name,
          amount: logged,
          kcal: logged,
          photoAmount: photo,
        ),
    ],
    kcal: 0,
    corrected: false,
    size: size,
  );
}

/// Records at [sizes], newest first, rice as the photo showed it.
List<PhotoMealRecord> _sized(List<double?> sizes) => [
  for (final (i, size) in sizes.indexed)
    _record(i + 1, size: size, foods: {'rice': (150 * (size ?? 1), 150)}),
];

/// Records with rice logged at [grams] against the photo's 100 g, newest
/// first, at "As shown".
List<PhotoMealRecord> _rice(List<double> grams) => [
  for (final (i, logged) in grams.indexed)
    _record(i + 1, foods: {'rice': (logged, 100)}),
];

UsualSizes _usual(List<PhotoMealRecord> records) =>
    usualSizesOf(records, now: _now);

/// [serving] grams a serving, when it has one.
MealEntity _food(String name, {double? serving}) => MealEntity(
  code: name,
  name: name,
  url: null,
  mealQuantity: null,
  mealUnit: 'g',
  servingQuantity: serving,
  servingUnit: serving == null ? null : 'g',
  servingSize: serving == null ? null : '1 piece ($serving g)',
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

/// A row of [amount] [name] in grams, or with [pieces] in servings of 50 g.
BulkAddRow _row(String name, String amount, {bool pieces = false}) {
  final unit = pieces ? 'serving' : 'g';
  return BulkAddRow(
    resolved: ResolvedMealItem(
      parsed: ParsedMealItem(
        query: name,
        quantity: double.parse(amount),
        unit: pieces ? null : 'g',
      ),
      candidates: [_food(name, serving: pieces ? 50 : null)],
      selectedIndex: 0,
      confidence: 1,
    ),
    selectedIndex: 0,
    amountText: amount,
    unit: unit,
    fromPhoto: true,
  );
}

void main() {
  group('the whole meal', () {
    test('nothing with 2 sizes off, a size with 3', () {
      expect(_usual(_sized([0.8, 0.8])).meal, 1);
      expect(_usual(_sized([0.8, 0.8, 1])).meal, 1);
      expect(_usual(_sized([0.8, 0.8, 0.6])).meal, 0.8);
    });

    test('the median of every size considered, sizes at 1 included', () {
      expect(_usual(_sized([0.6, 0.6, 0.8, 1, 1])).meal, 0.8);
      // the median within 10% of 1 is no size
      expect(_usual(_sized([0.8, 0.8, 0.8, 1, 1, 1, 1])).meal, 1);
    });

    test('one way at least twice as often as the other', () {
      expect(_usual(_sized([0.8, 0.8, 0.8, 1.2])).meal, 0.8);
      expect(_usual(_sized([0.8, 0.8, 0.8, 1.2, 1.2])).meal, 1);
      expect(_usual(_sized([0.6, 0.6, 0.6, 0.6, 1.2, 1.2])).meal, 0.6);
    });

    test('under 10% off is no correction', () {
      expect(_usual(_sized([0.95, 0.95, 0.95, 0.95])).meal, 1);
      expect(_usual(_sized([0.9, 0.9, 0.9])).meal, 0.9);
    });

    test('only the most recent 8 sizes', () {
      // 3 larger sizes before the last 8 would have held it back
      expect(
        _usual(_sized([0.6, 0.6, 0.6, 0.6, 0.6, 1, 1, 1, 1.4, 1.4, 1.4])).meal,
        0.6,
      );
      // 4 smaller, 2 of them out of reach
      expect(_usual(_sized([1, 1, 1, 1, 1, 1, 0.6, 0.6, 0.6, 0.6])).meal, 1);
    });

    test('held to 0.5-2', () {
      expect(_usual(_sized([0.3, 0.3, 0.3])).meal, 0.5);
      expect(_usual(_sized([3, 3, 3])).meal, 2);
    });

    test('records kept before sizes were are left out', () {
      expect(_usual(_sized([null, null, 0.8, 0.8])).meal, 1);
      expect(_usual(_sized([0.8, null, 0.8, null, 0.8])).meal, 0.8);
    });

    test('records past the days kept are left out', () {
      final records = [
        _record(1, size: 0.8),
        _record(2, size: 0.8),
        _record(photoMealMemoryDays + 5, size: 0.8),
      ];
      expect(_usual(records).meal, 1);
    });
  });

  group('a food', () {
    test('nothing with 2 corrections, a size with 3', () {
      expect(_usual(_rice([70, 70])).foods, isEmpty);
      expect(_usual(_rice([70, 70, 100])).foods, isEmpty);
      expect(_usual(_rice([70, 70, 60])).foods, {'rice': 0.7});
    });

    test('none the other way', () {
      expect(_usual(_rice([70, 70, 70, 120])).foods, isEmpty);
      // under 10% the other way is no correction
      expect(_usual(_rice([70, 70, 70, 105])).foods, {'rice': 0.7});
    });

    test('only its most recent 5 records', () {
      expect(_usual(_rice([100, 100, 100, 70, 70, 70])).foods, isEmpty);
      expect(_usual(_rice([70, 70, 70, 100, 100, 140])).foods, {'rice': 0.7});
    });

    test('held to 0.5-2', () {
      expect(_usual(_rice([20, 20, 20])).foods, {'rice': 0.5});
      expect(_usual(_rice([250, 250, 250])).foods, {'rice': 2});
    });

    test('a Size chosen every time is the meal\'s, not each food\'s', () {
      final records = [
        for (var i = 1; i <= 4; i++)
          _record(
            i,
            size: 0.8,
            foods: {'rice': (120, 150), 'chicken': (80, 100)},
          ),
      ];
      final usual = _usual(records);
      expect(usual.meal, 0.8);
      expect(usual.foods, isEmpty);
    });

    test('its own correction apart from the Size chosen', () {
      // at ×0.8 every time, and the rice set to half the photo's
      final records = [
        for (var i = 1; i <= 3; i++)
          _record(
            i,
            size: 0.8,
            foods: {'rice': (75, 150), 'chicken': (80, 100)},
          ),
      ];
      final usual = _usual(records);
      expect(usual.meal, 0.8);
      expect(usual.foods['rice'], closeTo(0.625, 1e-9));
      expect(usual.foods, isNot(contains('chicken')));
      expect(usual.factorFor('rice'), closeTo(0.5, 1e-9));
      expect(usual.factorFor('chicken'), 0.8);
    });

    test('a food added by hand, or in a record kept before, is not learnt '
        'from', () {
      expect(
        _usual([
          for (var i = 1; i <= 3; i++) _record(i, foods: {'rice': (100, null)}),
        ]).foods,
        isEmpty,
      );
      expect(
        _usual([
          for (var i = 1; i <= 3; i++)
            _record(i, size: null, foods: {'rice': (100, 150)}),
        ]).foods,
        isEmpty,
      );
    });

    test('two rows of one food are taken together', () {
      final records = [
        for (var i = 1; i <= 3; i++)
          PhotoMealRecord(
            day: DateTime(_now.year, _now.month, _now.day - i),
            loggedAt: DateTime(_now.year, _now.month, _now.day - i, 19),
            slot: 'dinner',
            foods: const [
              PhotoMealFood(
                key: 'rice',
                name: 'rice',
                amount: 50,
                kcal: 50,
                photoAmount: 100,
              ),
              PhotoMealFood(
                key: 'rice',
                name: 'rice',
                amount: 100,
                kcal: 100,
                photoAmount: 100,
              ),
            ],
            kcal: 150,
            corrected: true,
            size: 1,
          ),
      ];
      expect(_usual(records).foods, {'rice': 0.75});
    });
  });

  group('the usual amounts', () {
    const sizes = UsualSizes(meal: 0.8, foods: {'rice': 0.7});

    test('each row at its food\'s and the meal\'s size, rounded as the Size '
        'rounds', () {
      final rows = [
        _row('rice', '150'),
        _row('chicken', '100'),
        _row('egg', '3', pieces: true),
      ];
      final amounts = usualAmounts(rows, sizes, canTake: (_) => true);
      expect(amounts.values, ['84', '80', '2.5']);
      expect(identical(amounts.keys.first, rows.first.resolved), isTrue);
    });

    test('only rows it may take, none whose amount would not change', () {
      final rows = [_row('rice', '150'), _row('egg', '1', pieces: true)];
      expect(
        usualAmounts(rows, sizes, canTake: (row) => row.meal!.name != 'rice'),
        isEmpty,
      );
    });

    test('never on a weighed plate, nor a count the note states', () {
      final rows = [_row('rice', '150'), _row('egg', '3', pieces: true)];
      expect(
        usualAmounts(rows, sizes, note: 'rice 150 g', canTake: (_) => true),
        isEmpty,
      );
      expect(
        usualAmounts(rows, sizes, note: '3 eggs', canTake: (_) => true).length,
        1,
      );
    });

    test('nothing with no size learnt', () {
      expect(
        usualAmounts(
          [_row('rice', '150')],
          UsualSizes.none,
          canTake: (_) => true,
        ),
        isEmpty,
      );
    });
  });

  test('the line names at most three foods, then how many more', () {
    final foods = [
      for (final (name, factor) in [
        ('rice', 0.7),
        ('bread', 0.75),
        ('chicken', 1.25),
        ('salad', 2.0),
      ])
        (name: name, factor: factor),
    ];
    const shown = UsualSizesView.shownFoods;
    expect(
      DishStrings.usualSized(
        foods.take(shown).toList(),
        meal: 0.8,
        more: foods.length - shown,
      ),
      'Sized the way you usually correct: rice ×0.7 · bread ×0.75 · '
      'chicken ×1.25 · and 1 more · whole meal ×0.8',
    );
    expect(
      DishStrings.usualSized([foods.last]),
      'Sized the way you usually correct: salad ×2',
    );
  });
}
