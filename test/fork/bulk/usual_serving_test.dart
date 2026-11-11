import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_portion_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/usecase/resolve_parsed_meals_usecase.dart';
import 'package:opennutritracker/features/add_meal/presentation/bloc/bulk_add_bloc.dart';
import 'package:opennutritracker/features/add_meal/util/meal_text_parser.dart';
import 'package:opennutritracker/fork/bulk/usual_serving.dart';

MealEntity _food(
  String name, {
  double? serving,
  String? servingSize,
  List<MealPortionEntity> portions = const [],
  String mealUnit = 'g',
}) => MealEntity(
  code: name,
  name: name,
  url: null,
  mealQuantity: null,
  mealUnit: mealUnit,
  servingQuantity: serving,
  servingUnit: serving == null ? null : 'g',
  servingSize: servingSize,
  source: MealSourceEntity.fdc,
  portions: portions,
  nutriments: MealNutrimentsEntity(
    energyKcal100: 100,
    carbohydrates100: 0,
    fat100: 0,
    proteins100: 0,
    sugars100: null,
    saturatedFat100: null,
    fiber100: null,
  ),
);

/// Rice with a 150 g serving.
final _rice = _food('rice', serving: 150, servingSize: '1 cup');

/// Eggs of 50 g, the serving one egg.
final _egg = _food(
  'egg',
  serving: 50,
  servingSize: '1 large',
  portions: const [
    MealPortionEntity(label: '1 large', gramWeight: 50, localized: true),
  ],
);

BulkAddRow _row(
  String amount, {
  String unit = 'g',
  MealEntity? food,
  String? parsedUnit = 'g',
  bool skipped = false,
}) => BulkAddRow(
  resolved: ResolvedMealItem(
    parsed: ParsedMealItem(
      query: (food ?? _rice).name!,
      quantity: double.tryParse(amount),
      unit: parsedUnit,
    ),
    candidates: [food ?? _rice],
    selectedIndex: 0,
    confidence: 1,
  ),
  selectedIndex: 0,
  amountText: amount,
  unit: unit,
  skipped: skipped,
  fromPhoto: true,
);

String? _offer(BulkAddRow row, {String? note, bool imperial = false}) =>
    usualServingFor(row, note: note, imperial: imperial)?.label;

void main() {
  group('a weight', () {
    test('within a third and three times the serving: nothing', () {
      expect(_offer(_row('50')), isNull);
      expect(_offer(_row('150')), isNull);
      expect(_offer(_row('450')), isNull);
    });

    test('over three times or under a third: the serving offered', () {
      expect(_offer(_row('460')), '150 g');
      expect(_offer(_row('40')), '150 g');
    });

    test('the chip sets the serving in the row\'s unit', () {
      final chip = usualServingFor(_row('600'), imperial: false)!;
      expect(chip.unit, 'g');
      expect(chip.text, '150');
      expect(chip.spoken, '150 grams');
    });

    test('a serving put as a person says it', () {
      final food = _food('pasta', serving: 137);
      expect(_offer(_row('20', food: food)), '140 g');
    });

    test('in ounces on an imperial profile, where the Diary shows them', () {
      final chip = usualServingFor(_row('600'), imperial: true)!;
      expect(chip.label, '5.5 oz');
      expect(chip.unit, 'oz');
    });
  });

  group('a count', () {
    BulkAddRow eggs(String n) =>
        _row(n, unit: 'serving', food: _egg, parsedUnit: null);

    test('one to three pieces are never too many', () {
      expect(_offer(eggs('1')), isNull);
      expect(_offer(eggs('3')), isNull);
    });

    test('above three pieces and three servings: the serving in pieces', () {
      final chip = usualServingFor(eggs('4'), imperial: false)!;
      expect(chip.label, '1 large');
      expect(chip.unit, 'serving');
      expect(chip.text, '1');
    });

    test('many small pieces within three servings: nothing', () {
      final dumpling = _food(
        'dumplings',
        serving: 200,
        servingSize: '1 serving',
        portions: const [
          MealPortionEntity(label: '1 piece', gramWeight: 12, localized: true),
          MealPortionEntity(
            label: '1 serving',
            gramWeight: 200,
            localized: true,
          ),
        ],
      );
      expect(
        _offer(_row('14', unit: 'serving', food: dumpling, parsedUnit: null)),
        isNull,
      );
    });

    test('half a piece of a food served by the half dozen', () {
      final food = _food(
        'pancakes',
        serving: 240,
        servingSize: '6 pancakes',
        portions: const [
          MealPortionEntity(
            label: '1 pancake',
            gramWeight: 40,
            localized: true,
          ),
        ],
      );
      final chip = usualServingFor(
        _row('0.5', unit: 'serving', food: food, parsedUnit: null),
        imperial: false,
      )!;
      expect(chip.label, '6 pancakes');
      expect(chip.text, '6');
    });
  });

  group('nothing to compare, or a row no size may change', () {
    test('a food with no serving in the table', () {
      expect(_offer(_row('900', food: _food('soup'))), isNull);
    });

    test('a weighed plate', () {
      expect(_offer(_row('600'), note: '600 g'), isNull);
    });

    test('a count the note states', () {
      expect(
        _offer(
          _row('4', unit: 'serving', food: _egg, parsedUnit: null),
          note: '4 eggs',
        ),
        isNull,
      );
    });

    test('a row left out', () {
      expect(_offer(_row('600', skipped: true)), isNull);
    });

    test('an amount that is none', () {
      expect(_offer(_row('')), isNull);
      expect(_offer(_row('0')), isNull);
    });
  });
}
