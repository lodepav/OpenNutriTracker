import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/usecase/resolve_parsed_meals_usecase.dart';
import 'package:opennutritracker/features/add_meal/presentation/bloc/bulk_add_bloc.dart';
import 'package:opennutritracker/features/add_meal/util/meal_text_parser.dart';
import 'package:opennutritracker/fork/bulk/review_totals.dart';
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
  source: MealSourceEntity.off,
  nutriments: const MealNutrimentsEntity(
    energyKcal100: 200,
    carbohydrates100: 10,
    fat100: 10,
    proteins100: 20,
    sugars100: null,
    saturatedFat100: null,
    fiber100: null,
  ),
);

BulkAddRow _row(
  String name,
  String amount,
  String unit, {
  double confidence = 1,
  bool resolved = true,
  bool skipped = false,
  double? serving,
}) => BulkAddRow(
  resolved: ResolvedMealItem(
    parsed: ParsedMealItem(query: name),
    candidates: resolved ? [_food(name, serving: serving)] : const [],
    selectedIndex: 0,
    confidence: resolved ? confidence : 0,
  ),
  selectedIndex: 0,
  amountText: amount,
  unit: unit,
  skipped: skipped,
  unitChosenByUser: true,
);

void main() {
  test("a row's energy and macros at its amount, a portion counted", () {
    expect(rowMacros(_row('eggs', '150', 'g')), (
      kcal: 300.0,
      protein: 30.0,
      carbs: 15.0,
      fat: 15.0,
    ));
    expect(
      rowMacros(_row('meatballs', '6', 'serving', serving: 30))?.kcal,
      360,
    );
    expect(rowMacros(_row('eggs', '', 'g')), isNull);
    expect(rowMacros(_row('unicorn', '100', 'g', resolved: false)), isNull);
  });

  test('the meal is what will be logged: a left-out food is not', () {
    final meal = mealMacros([
      _row('eggs', '100', 'g'),
      _row('bacon', '50', 'g'),
      _row('toast', '100', 'g', skipped: true),
      _row('unicorn', '100', 'g', resolved: false),
    ]);
    expect(meal.kcal, 300);
    expect(meal.protein, 30);
  });

  test('a doubtful match or no match needs a look; a chosen amount does '
      'not', () {
    expect(rowNeedsLook(_row('meatballs', '6', 'g', confidence: 0.3)), isTrue);
    expect(rowNeedsLook(_row('unicorn', '1', 'g', resolved: false)), isTrue);
    expect(rowNeedsLook(_row('eggs', '100', 'g')), isFalse);
  });

  test('the foods that need a look come first; a dish stays together', () {
    final rows = [
      _row('eggs', '100', 'g'),
      _row('meatballs', '6', 'g', confidence: 0.3),
      _row('rice', '100', 'g', confidence: 0.3),
      _row('toast', '100', 'g'),
    ];
    final group = Object();
    final entries = needsLookFirst([
      const DishRowEntry(0, inDish: false),
      DishHeading(group, const [2]),
      const DishRowEntry(2, inDish: true),
      const DishRowEntry(1, inDish: false),
      const DishRowEntry(3, inDish: false),
    ], rows);
    expect(
      [
        for (final e in entries)
          switch (e) {
            DishRowEntry(:final index, :final inDish) =>
              '${inDish ? 'dish ' : ''}$index',
            DishHeading() => 'heading',
            DishActions() => 'actions',
          },
      ],
      ['1', '0', 'heading', 'dish 2', '3'],
    );
  });
}
