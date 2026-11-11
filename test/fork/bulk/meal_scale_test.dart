import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/usecase/resolve_parsed_meals_usecase.dart';
import 'package:opennutritracker/features/add_meal/presentation/bloc/bulk_add_bloc.dart';
import 'package:opennutritracker/features/add_meal/util/meal_text_parser.dart';
import 'package:opennutritracker/fork/bulk/meal_scale.dart';
import 'package:opennutritracker/fork/dish/dish_breakdown_rows.dart';
import 'package:opennutritracker/fork/dish/dish_group.dart';

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

/// A photo's row: [quantity] in [parsedUnit] as the model read it, at
/// [amount] in [unit] on screen.
BulkAddRow _row(
  String name,
  String amount,
  String unit, {
  double? quantity,
  bool stated = true,
  String? parsedUnit = 'g',
  double? serving,
  bool resolved = true,
  bool skipped = false,
  ParsedMealItem? parsed,
  List<MealEntity>? candidates,
}) {
  final item =
      parsed ??
      ParsedMealItem(
        query: name,
        quantity: stated ? quantity ?? double.tryParse(amount) : null,
        unit: parsedUnit,
      );
  return BulkAddRow(
    resolved: ResolvedMealItem(
      parsed: item,
      candidates: resolved
          ? candidates ?? [_food(name, serving: serving)]
          : const [],
      selectedIndex: 0,
      confidence: resolved ? 1 : 0,
    ),
    selectedIndex: 0,
    amountText: amount,
    unit: unit,
    skipped: skipped,
    fromPhoto: true,
  );
}

/// [rows] with [amounts] set, as the bloc's `ScaleRowsEvent` sets them.
List<BulkAddRow> _apply(
  List<BulkAddRow> rows,
  Map<ResolvedMealItem, String> amounts,
) => [
  for (final row in rows)
    amounts.entries
            .where((e) => identical(e.key, row.resolved))
            .map((e) => row.copyWith(amountText: e.value))
            .firstOrNull ??
        row,
];

/// [scale] at [factor], and the rows it leaves.
List<BulkAddRow> _size(MealScale scale, List<BulkAddRow> rows, double factor) {
  scale.factor = factor;
  final next = _apply(rows, scale.retarget(rows));
  // the state arrives
  return _apply(next, scale.follow(next));
}

List<String> _amounts(List<BulkAddRow> rows) => [
  for (final row in rows) row.amountText,
];

void main() {
  group('rounding (R3)', () {
    test('grams and millilitres whole, ounces to a tenth', () {
      expect(scaledAmountText(155, 'g', 0.8), '124');
      expect(scaledAmountText(333, 'ml', 0.6), '200');
      expect(scaledAmountText(150, 'g/ml', 1.4), '210');
      expect(scaledAmountText(5.3, 'oz', 1.2), '6.4');
      expect(scaledAmountText(8, 'fl.oz', 0.6), '4.8');
    });

    test('a count to the nearest half, never below one half', () {
      expect(scaledAmountText(1, 'serving', 0.6), '0.5');
      expect(scaledAmountText(1, 'serving', 0.8), '1');
      expect(scaledAmountText(1, 'serving#2', 1.4), '1.5');
      expect(scaledAmountText(3, 'serving', 0.8), '2.5');
      expect(scaledAmountText(0.5, 'serving', 0.6), '0.5');
    });

    test('a pinch stays a pinch', () {
      expect(scaledAmountText(0.3, 'g', 0.6), '0.18');
      expect(scaledAmountText(0.001, 'g', 0.6), '0.01');
    });
  });

  group('which rows a size changes (R2)', () {
    test('a matched row at an amount the photo gave', () {
      expect(isScalableRow(_row('rice', '150', 'g')), isTrue);
      expect(
        isScalableRow(
          _row('egg', '2', 'serving', parsedUnit: null, serving: 50),
        ),
        isTrue,
      );
    });

    test('not one left out, unmatched, or with no amount', () {
      expect(isScalableRow(_row('rice', '150', 'g', skipped: true)), isFalse);
      expect(isScalableRow(_row('rice', '150', 'g', resolved: false)), isFalse);
      expect(isScalableRow(_row('rice', '', 'g', quantity: 150)), isFalse);
      expect(isScalableRow(_row('rice', '0', 'g', quantity: 150)), isFalse);
    });

    test("not the app's default amount, nor one that would be wrong", () {
      // nothing stated, no serving: 100 g, "Amount not stated"
      final provisional = _row('rice', '100', 'g/ml', stated: false);
      expect(provisional.amountIsProvisional, isTrue);
      expect(isScalableRow(provisional), isFalse);
      // a count on a food that cannot be counted is held back
      final wrong = _row('egg', '2', 'g/ml', parsedUnit: null);
      expect(wrong.amountWouldBeWrong, isTrue);
      expect(isScalableRow(wrong), isFalse);
    });

    test("not a weighed plate's, nor a count the note states", () {
      final rice = _row('rice', '150', 'g');
      expect(isScalableRow(rice, note: 'rice 150g, chicken'), isFalse);
      expect(isScalableRow(rice, note: '350g total'), isFalse);
      final eggs = _row('egg', '2', 'serving', parsedUnit: null, serving: 50);
      expect(isScalableRow(eggs, note: '2 eggs and toast'), isFalse);
      expect(isScalableRow(eggs, note: 'breakfast'), isTrue);
      // the note's count is a count, not the toast's grams
      expect(
        isScalableRow(_row('toast', '2', 'g'), note: '2 eggs and toast'),
        isTrue,
      );
    });
  });

  group('a size', () {
    test('scales every row from its base, never from the last size', () {
      final scale = MealScale();
      var rows = [
        _row('rice', '155', 'g'),
        _row('egg', '1', 'serving', parsedUnit: null, serving: 50),
        _row('soup', '333', 'ml'),
      ];
      scale.follow(rows);
      rows = _size(scale, rows, 0.6);
      expect(_amounts(rows), ['93', '0.5', '200']);
      rows = _size(scale, rows, 1.4);
      expect(_amounts(rows), ['217', '1.5', '466']);
      final atPoint8 = _amounts(_size(scale, rows, 0.8));
      for (var i = 0; i < 5; i++) {
        rows = _size(scale, rows, 0.6);
        rows = _size(scale, rows, 1.2);
      }
      expect(_amounts(_size(scale, rows, 0.8)), atPoint8);
      // As shown: the photo's amounts, exactly as they came
      rows = _size(scale, rows, 1);
      expect(_amounts(rows), ['155', '1', '333']);
    });

    test('in ounces does not drift back and forth', () {
      final scale = MealScale();
      var rows = [_row('steak', '3.5', 'oz'), _row('rice', '150', 'g')];
      scale.follow(rows);
      for (var i = 0; i < 10; i++) {
        rows = _size(scale, rows, 0.6);
        expect(_amounts(rows), ['2.1', '90']);
        rows = _size(scale, rows, 1.4);
        expect(_amounts(rows), ['4.9', '210']);
      }
      rows = _size(scale, rows, 1);
      expect(_amounts(rows), ['3.5', '150']);
    });

    test("leaves the rows it may not change as they are", () {
      final scale = MealScale();
      var rows = [
        _row('rice', '150', 'g'),
        _row('pickles', '40', 'g', skipped: true),
        _row('mystery', '80', 'g', resolved: false),
        _row('bread', '100', 'g/ml', stated: false),
      ];
      scale.follow(rows);
      rows = _size(scale, rows, 0.6);
      expect(_amounts(rows), ['90', '40', '80', '100']);
    });

    test('takes a row put back to the size chosen', () {
      final scale = MealScale();
      var rows = [_row('rice', '150', 'g'), _row('beans', '100', 'g')];
      scale.follow(rows);
      rows = [rows[0], rows[1].copyWith(skipped: true)];
      rows = _apply(rows, scale.follow(rows));
      rows = _size(scale, rows, 0.8);
      expect(_amounts(rows), ['120', '100']);
      rows = [rows[0], rows[1].copyWith(skipped: false)];
      rows = _apply(rows, scale.follow(rows));
      expect(_amounts(rows), ['120', '80']);
    });

    test("moves a dish's portion with its foods, its yield fixed", () {
      final group = Object();
      BulkAddRow member(String name, double grams) => _row(
        name,
        '${grams.round()}',
        'g',
        parsed: DishIngredientItem(
          query: name,
          quantity: grams,
          unit: 'g',
          dish: 'plov',
          group: group,
          dishGrams: 350,
          fromBreakdown: true,
        ),
      );
      final scale = MealScale();
      var rows = [member('rice', 200), member('lamb', 100)];
      scale.follow(rows);
      final members = dishMembers(rows, group);
      expect(dishPortion(rows, members), closeTo(350, 0.01));
      rows = _size(scale, rows, 0.8);
      expect(_amounts(rows), ['160', '80']);
      expect(dishPortion(rows, members), closeTo(280, 0.01));
    });
  });

  group('an amount the user set (R1)', () {
    test('is pinned: a size leaves it, and the rest move', () {
      final scale = MealScale();
      var rows = [_row('rice', '150', 'g'), _row('beans', '100', 'g')];
      scale.follow(rows);
      rows = _size(scale, rows, 0.6);
      // typed 120 g of rice
      rows = [
        rows[0].copyWith(amountText: '120', amountEditedByUser: true),
        rows[1],
      ];
      rows = _apply(rows, scale.follow(rows));
      expect(scale.isPinned(rows[0]), isTrue);
      expect(scale.isPinned(rows[1]), isFalse);
      rows = _size(scale, rows, 1.4);
      expect(_amounts(rows), ['120', '140']);
      rows = _size(scale, rows, 1);
      expect(_amounts(rows), ['120', '100']);
    });

    test('as is a unit changed, or a row pinned by hand', () {
      final scale = MealScale();
      var rows = [
        _row('rice', '150', 'g'),
        _row('beans', '100', 'g'),
        _row('corn', '50', 'g'),
      ];
      scale.follow(rows);
      rows = [
        rows[0].copyWith(unit: 'oz', unitChosenByUser: true),
        rows[1],
        rows[2],
      ];
      scale.pin(rows[1]);
      rows = _apply(rows, scale.follow(rows));
      expect(scale.isPinned(rows[0]), isTrue);
      expect(scale.allSet(rows), isFalse);
      rows = _size(scale, rows, 0.8);
      expect(_amounts(rows), ['150', '100', '40']);
      scale.pin(rows[2]);
      expect(scale.allSet(rows), isTrue);
      expect(scale.offered(rows), isTrue);
      expect(scale.retarget(rows), isEmpty);
    });

    test(
      'is not taken from a state that still holds the amount before a size',
      () {
        final scale = MealScale();
        final rows = [_row('rice', '150', 'g')];
        scale.follow(rows);
        scale.factor = 0.6;
        final amounts = scale.retarget(rows);
        // an earlier state reaches the screen before the scaled one
        scale.follow(rows);
        expect(scale.isPinned(rows.single), isFalse);
        final scaled = _apply(rows, amounts);
        expect(scale.follow(scaled), isEmpty);
        expect(scale.isPinned(scaled.single), isFalse);
      },
    );
  });

  test('another match on a row the user did not set is its new base, at the '
      'size chosen', () {
    final scale = MealScale();
    var rows = [
      _row(
        'rice',
        '150',
        'g',
        candidates: [_food('rice'), _food('rice, brown')],
      ),
    ];
    scale.follow(rows);
    rows = _size(scale, rows, 0.8);
    expect(_amounts(rows), ['120']);
    // the bloc re-derives a pristine row's amount for the new food
    rows = [rows.single.copyWith(selectedIndex: 1, amountText: '150')];
    rows = _apply(rows, scale.follow(rows));
    expect(scale.isPinned(rows.single), isFalse);
    expect(_amounts(rows), ['120']);
    expect(_amounts(_size(scale, rows, 1)), ['150']);
  });

  test('a new base for a row, set from outside, stays unpinned', () {
    final scale = MealScale();
    var rows = [_row('rice', '150', 'g')];
    scale.follow(rows);
    scale.pin(rows.single);
    scale.setBase(rows.single, amountText: '200');
    rows = [rows.single.copyWith(amountText: '200')];
    rows = _apply(rows, scale.follow(rows));
    expect(scale.isPinned(rows.single), isFalse);
    expect(_amounts(_size(scale, rows, 0.6)), ['120']);
  });

  group('a breakdown', () {
    BulkAddRow ingredient(String name, double grams, Object group) => _row(
      name,
      '${grams.round()}',
      'g',
      parsed: DishIngredientItem(
        query: name,
        quantity: grams,
        unit: 'g',
        dish: 'plov',
        group: group,
        fromBreakdown: true,
      ),
    );

    test("of a row at a size: its foods were weighed for it, so their base "
        'is that divided by the size', () {
      final scale = MealScale();
      var rows = [_row('plov', '400', 'g'), _row('salad', '100', 'g')];
      scale.follow(rows);
      rows = _size(scale, rows, 0.8);
      expect(_amounts(rows), ['320', '80']);
      final group = Object();
      // 320 g of plov, as rice and lamb
      rows = [
        ingredient('rice', 200, group),
        ingredient('lamb', 120, group),
        rows[1],
      ];
      expect(scale.follow(rows), isEmpty);
      expect(scale.isPinned(rows[0]), isFalse);
      expect(_amounts(_size(scale, rows, 1)), ['250', '150', '100']);
    });

    test('of a row the user set: its foods are set too', () {
      final scale = MealScale();
      var rows = [_row('plov', '400', 'g'), _row('salad', '100', 'g')];
      scale.follow(rows);
      rows = [rows[0].copyWith(amountText: '300'), rows[1]];
      scale.follow(rows);
      final group = Object();
      rows = [
        ingredient('rice', 200, group),
        ingredient('lamb', 100, group),
        rows[1],
      ];
      scale.follow(rows);
      expect(scale.isPinned(rows[0]), isTrue);
      expect(scale.isPinned(rows[1]), isTrue);
      expect(_amounts(_size(scale, rows, 0.6)), ['200', '100', '60']);
    });

    test('of a row nothing matched: its foods are at the photo\'s amount, '
        'and take the size chosen', () {
      final scale = MealScale();
      var rows = [
        _row('plov', '400', 'g', resolved: false),
        _row('salad', '100', 'g'),
      ];
      scale.follow(rows);
      rows = _size(scale, rows, 0.6);
      expect(_amounts(rows), ['400', '60']);
      final group = Object();
      rows = [
        ingredient('rice', 250, group),
        ingredient('lamb', 150, group),
        rows[1],
      ];
      rows = _apply(rows, scale.follow(rows));
      expect(_amounts(rows), ['150', '90', '60']);
      expect(_amounts(_size(scale, rows, 1)), ['250', '150', '100']);
    });
  });
}
