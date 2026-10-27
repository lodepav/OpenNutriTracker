import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/features/add_meal/presentation/add_meal_type.dart';
import 'package:opennutritracker/fork/display/diary_by_hour.dart';
import 'package:opennutritracker/fork/display/display_prefs.dart';

IntakeEntity _eat(String food, DateTime at, IntakeTypeEntity type) =>
    IntakeEntity(
      id: food,
      unit: 'g',
      amount: 100,
      type: type,
      meal: MealEntity(
        code: food,
        name: food,
        url: null,
        mealQuantity: null,
        mealUnit: 'g',
        servingQuantity: null,
        servingUnit: 'g',
        servingSize: null,
        nutriments: const MealNutrimentsEntity(
          energyKcal100: 100,
          carbohydrates100: null,
          fat100: null,
          proteins100: null,
          sugars100: null,
          saturatedFat100: null,
          fiber100: null,
        ),
        source: MealSourceEntity.custom,
      ),
      dateTime: at,
    );

void main() {
  tearDown(() => DisplayPrefs.macroOrder.value = DisplayPrefs.upstreamOrder);

  test('the macros come in the order picked, upstream\'s by default', () {
    expect(inMacroOrder(carbs: 'C', fat: 'F', protein: 'P'), ['C', 'F', 'P']);
    DisplayPrefs.macroOrder.value = [Macro.protein, Macro.fat, Macro.carbs];
    expect(inMacroOrder(carbs: 'C', fat: 'F', protein: 'P'), ['P', 'F', 'C']);
    expect(
      macroOrderLabel(DisplayPrefs.macroOrder.value),
      'Protein, fat, carbs',
    );
  });

  test('six orders, and a stored one that is not all three reads as '
      'upstream\'s', () {
    expect(macroOrders, hasLength(6));
    expect(macroOrders.first, DisplayPrefs.upstreamOrder);
    expect(DisplayPrefs.parseOrder(['protein', 'carbs', 'fat']), [
      Macro.protein,
      Macro.carbs,
      Macro.fat,
    ]);
    for (final bad in [
      null,
      'protein',
      ['protein', 'protein', 'fat'],
      ['protein', 'fat'],
      ['protein', 'fat', 'sugar'],
    ]) {
      expect(DisplayPrefs.parseOrder(bad), DisplayPrefs.upstreamOrder);
    }
  });

  test('the Diary by the hour: untimed at their meal\'s usual hour, each '
      'hour adds to its usual meal', () {
    final sections = hourSections([
      _eat('Soup', DateTime(2026, 10, 23, 12, 5), IntakeTypeEntity.lunch),
      _eat('Coffee', DateTime(2026, 10, 23, 7, 50), IntakeTypeEntity.snack),
      _eat('Toast', DateTime(2026, 10, 23, 7, 10), IntakeTypeEntity.breakfast),
      _eat('Egg', DateTime(2026, 10, 23, 7, 20), IntakeTypeEntity.breakfast),
      _eat('Apple', DateTime(2026, 10, 23), IntakeTypeEntity.snack),
    ]);
    // The snack with no time sits at 16:00, where the Diary puts snacks.
    expect([for (final s in sections) s.title], ['07:00', '12:00', '16:00']);
    expect(
      [for (final i in sections[0].intakes) i.id],
      ['Toast', 'Egg', 'Coffee'],
    );
    expect(sections[0].addMealType, AddMealType.breakfastType);
    expect(sections[1].addMealType, AddMealType.lunchType);
    expect(sections[2].addMealType, AddMealType.snackType);
  });
}
