// lib/fork/bulk/soup_contents.dart: a soup's own meat is not listed beside it.
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/features/add_meal/util/meal_text_parser.dart';
import 'package:opennutritracker/fork/bulk/soup_contents.dart';

List<String> _kept(List<String> queries, {String? note}) => [
  for (final item in withoutSoupMeats(
    MealTextParseResult(
      items: [for (final q in queries) ParsedMealItem(query: q)],
      errors: const [],
    ),
    note,
  ).items)
    item.query,
];

void main() {
  test('a solyanka keeps its meat, what was added stays apart', () {
    expect(
      _kept([
        'solyanka soup',
        'smoked sausage',
        'beef',
        'smoked meat',
        'black olives',
        'sour cream',
        'bread croutons',
      ]),
      ['solyanka soup', 'black olives', 'sour cream', 'bread croutons'],
    );
  });

  test('a dish beside the bowl stays, and so does meat with no soup', () {
    expect(_kept(['borscht', 'roast beef', 'pork chop']), [
      'borscht',
      'roast beef',
      'pork chop',
    ]);
    expect(_kept(['mashed potatoes', 'sausage']), [
      'mashed potatoes',
      'sausage',
    ]);
  });

  test('meat the note names stays', () {
    expect(_kept(['solyanka', 'sausage', 'ham'], note: 'solyanka, sausage'), [
      'solyanka',
      'sausage',
    ]);
  });
}
