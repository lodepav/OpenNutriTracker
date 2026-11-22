import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/usecase/resolve_parsed_meals_usecase.dart';
import 'package:opennutritracker/features/add_meal/presentation/bloc/bulk_add_bloc.dart';
import 'package:opennutritracker/features/add_meal/util/meal_text_parser.dart';
import 'package:opennutritracker/features/meal_detail/presentation/bloc/meal_detail_bloc.dart';
import 'package:opennutritracker/fork/bulk/shown_unit.dart';

// Crit r4 g2: an amount set by hand answers "check the unit", except a
// recipe's count, which is checked again on the number typed.

MealEntity _food(
  String name, {
  double? servingQuantity,
  String? mealQuantity,
  MealSourceEntity source = MealSourceEntity.fdc,
}) => MealEntity(
  code: name,
  name: name,
  url: null,
  mealQuantity: mealQuantity,
  mealUnit: 'g',
  servingQuantity: servingQuantity,
  servingUnit: 'g',
  servingSize: null,
  nutriments: MealNutrimentsEntity.empty(),
  source: source,
);

BulkAddLoadedState _state(MealEntity food, String query, String unit) =>
    BulkAddLoadedState(
      rows: [
        BulkAddRow(
          resolved: ResolvedMealItem(
            parsed: ParsedMealItem(query: query, quantity: 14),
            candidates: [food],
            selectedIndex: 0,
            confidence: 1,
          ),
          selectedIndex: 0,
          amountText: '14',
          unit: unit,
        ),
      ],
      parseErrors: const [],
      usesImperialUnits: false,
    );

void main() {
  final gml = UnitDropdownItem.gml.toString();
  final serving = UnitDropdownItem.serving.toString();

  test('a held row set by hand is the answer, and logs', () {
    final state = _state(_food('Banana'), 'banana', gml);
    expect(state.rows.single.willBeLogged, isFalse);

    final row = setRowInShownUnit(
      state,
      SetRowInShownUnitEvent(0, gml, '120'),
    ).rows.single;

    expect(row.amountText, '120');
    expect(row.amountNeedsCheck, isFalse);
    expect(row.willBeLogged, isTrue);
  });

  test("a recipe's count is checked again on the number set", () {
    // a batch of 1200 g in 200 g servings makes 6
    final pelmeni = _food(
      'Pelmeni',
      servingQuantity: 200,
      mealQuantity: '1200',
      source: MealSourceEntity.recipe,
    );
    final state = _state(pelmeni, 'pelmeni', serving);
    expect(state.rows.single.willBeLogged, isFalse);

    final tooMany = setRowInShownUnit(
      state,
      SetRowInShownUnitEvent(0, serving, '13'),
    );
    expect(tooMany.rows.single.willBeLogged, isFalse);

    final corrected = setRowInShownUnit(
      tooMany,
      SetRowInShownUnitEvent(0, serving, '5'),
    ).rows.single;
    expect(corrected.willBeLogged, isTrue);
    // and a later count above the batch is still caught
    expect(
      setRowInShownUnit(
        BulkAddLoadedState(
          rows: [corrected],
          parseErrors: const [],
          usesImperialUnits: false,
        ),
        SetRowInShownUnitEvent(0, serving, '9'),
      ).rows.single.willBeLogged,
      isFalse,
    );
  });

  test('a row with nothing to check keeps its unit unchosen', () {
    final state = _state(_food('Rice', servingQuantity: 150), 'rice', serving);
    final row = setRowInShownUnit(
      state,
      SetRowInShownUnitEvent(0, serving, '2'),
    ).rows.single;
    expect(row.unitChosenByUser, isFalse);
  });
}
