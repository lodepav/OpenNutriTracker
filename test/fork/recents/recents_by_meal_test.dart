import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/fork/recents/recents_by_meal.dart';

final _now = DateTime(2026, 10, 23, 8);

IntakeEntity _log(String food, IntakeTypeEntity type, int daysAgo) =>
    IntakeEntity(
      id: '$food-$daysAgo-${type.name}',
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
        nutriments: MealNutrimentsEntity.empty(),
        source: MealSourceEntity.custom,
      ),
      dateTime: _now.subtract(Duration(days: daysAgo)),
    );

List<String> _names(List<IntakeEntity> intakes) => [
  for (final i in intakes) i.meal.name!,
];

void main() {
  const breakfast = IntakeTypeEntity.breakfast;
  const dinner = IntakeTypeEntity.dinner;

  final history = [
    for (var d = 1; d <= 20; d++) _log('Oats', breakfast, d),
    for (var d = 1; d <= 20; d++) _log('Pasta', dinner, d),
    _log('Pasta', breakfast, 0),
    _log('Cake', IntakeTypeEntity.snack, 0),
  ];
  // Upstream's recents: newest first.
  final recents = [
    _log('Cake', IntakeTypeEntity.snack, 0),
    _log('Pasta', breakfast, 0),
    _log('Oats', breakfast, 1),
    _log('Old soup', dinner, 200),
  ];

  test('the usual foods of the meal come first', () {
    expect(_names(rankRecentsForMeal(recents, history, breakfast, _now)), [
      'Oats',
      'Pasta',
      'Cake',
      'Old soup',
    ]);
    expect(_names(rankRecentsForMeal(recents, history, dinner, _now)), [
      'Pasta',
      'Oats',
      'Cake',
      'Old soup',
    ]);
  });

  test('a log fades: two old ones count less than one fresh', () {
    final ranked = rankRecentsForMeal(
      [_log('Old', breakfast, 0), _log('New', breakfast, 0)],
      [
        _log('Old', breakfast, 80),
        _log('Old', breakfast, 81),
        _log('New', breakfast, 0),
      ],
      breakfast,
      _now,
    );
    expect(_names(ranked), ['New', 'Old']);
  });

  test('with no meal the recents stay in upstream order', () async {
    expect(await recentsForMeal(recents, null), same(recents));
  });
}
