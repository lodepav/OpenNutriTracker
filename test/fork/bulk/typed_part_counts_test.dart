import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/features/add_meal/util/meal_text_parser.dart';
import 'package:opennutritracker/fork/bulk/typed_part_counts.dart';

List<ParsedMealItem> kept(String input, List<ParsedMealItem> items) =>
    keepPattyCounts(
      input,
      MealTextParseResult(items: items, errors: const []),
    ).items;

void main() {
  test("the model's 3 burgers with a patty portion stay one burger", () {
    for (final input in [
      'smash burger with 3 patties',
      '3 patty smash burger',
    ]) {
      final item = kept(input, const [
        ParsedMealItem(query: 'smash burger', quantity: 3, portion: 'patty'),
      ]).single;
      expect(item.query, input);
      expect(item.quantity, isNull);
      expect(item.portion, isNull);
    }
  });

  test("the parser's patty burger stays one burger", () {
    final item = keepPattyCounts(
      '3 patty smash burger',
      parseMealText('3 patty smash burger'),
    ).items.single;
    expect(item.query, '3 patty smash burger');
    expect(item.quantity, isNull);
  });

  test('the other foods on the line are left alone', () {
    final items = kept('smash burger with 3 patties and 2 cokes, fries', const [
      ParsedMealItem(query: 'smash burger', quantity: 3, portion: 'patty'),
      ParsedMealItem(query: 'cokes', quantity: 2),
      ParsedMealItem(query: 'fries'),
    ]);
    expect(items.map((i) => i.query), [
      'smash burger with 3 patties',
      'cokes',
      'fries',
    ]);
    expect(items[1].quantity, 2);
  });

  test('patties named as the food keep their count', () {
    final item = kept('3 patties, bun', const [
      ParsedMealItem(query: 'patties', quantity: 3),
      ParsedMealItem(query: 'bun'),
    ]).first;
    expect(item.query, 'patties');
    expect(item.quantity, 3);
  });

  test('a count of burgers is a count of burgers', () {
    final item = kept('2 burgers with 3 patties', const [
      ParsedMealItem(query: 'burgers', quantity: 2),
    ]).single;
    expect(item.quantity, 2);
  });
}
