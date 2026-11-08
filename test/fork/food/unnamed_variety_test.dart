// A bare count does not take a kind of the food it did not name (S197):
// "2 tomatoes" tied the table's grape, Italian and plum tomato on the food's
// own word, and the first, a grape tomato, logged 16 g.
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_portion_entity.dart';
import 'package:opennutritracker/features/add_meal/util/portion_match.dart';

MealPortionEntity _p(String label) =>
    MealPortionEntity(label: label, gramWeight: 1, localized: false);

void main() {
  // "Tomatoes, raw" as the table lists its portions
  final tomato = [
    _p('1 serving'),
    _p('1 slice'),
    _p('1 grape tomato'),
    _p('1 cherry'),
    _p('1 Italian tomato'),
    _p('1 plum tomato'),
    _p('1 whole'),
    _p('1 cup'),
  ];

  test('a count of the food is no kind of it', () {
    expect(matchPortionToQuery('tomatoes', tomato), isNull);
    expect(matchPortionToQuery('tomato', tomato), isNull);
  });

  test('the kind the text names is still the kind', () {
    expect(matchPortionToQuery('grape tomatoes', tomato), 2);
    expect(matchPortionToQuery('plum tomato', tomato), 5);
    expect(matchPortionToQuery('slices of tomato', tomato), 1);
  });

  test('a size is no kind: the ladder keeps its middle', () {
    final cookie = [
      _p('1 bite size cookie'),
      _p('1 medium cookie'),
      _p('1 large cookie'),
    ];
    expect(matchPortionToQuery('cookies', cookie), 1);
    final roll = [_p('1 small roll'), _p('1 large roll')];
    expect(matchPortionToQuery('rolls', roll), 0);
  });

  test('roast potatoes are not baby potatoes unless they say so', () {
    final potato = [
      _p('1 serving'),
      _p('1 baby potato'),
      _p('1 new potato'),
      _p('1 small'),
      _p('1 medium'),
    ];
    expect(matchPortionToQuery('roast potatoes', potato), isNull);
    expect(matchPortionToQuery('baby potatoes', potato), 1);
  });
}
