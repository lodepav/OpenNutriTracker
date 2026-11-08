// lib/fork/bulk/soup_contents.dart: a soup's own meat is not listed beside it.
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/features/add_meal/util/meal_text_parser.dart';
import 'package:opennutritracker/fork/bulk/soup_contents.dart';

List<String> _kept(List<String> queries, {String? note}) => [
  for (final item in withoutSoupContents(
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
        'pickled cucumber',
        'pickles',
        'sour cream',
        'bread croutons',
        'lemon slice',
      ]),
      ['solyanka soup', 'sour cream', 'bread croutons', 'lemon slice'],
    );
  });

  test('a dish beside the bowl stays, and so does meat with no soup', () {
    expect(_kept(['borscht', 'roast beef', 'pork chop']), [
      'borscht',
      'roast beef',
      'pork chop',
    ]);
    expect(_kept(['mashed potatoes', 'sausage', 'pickled cucumber']), [
      'mashed potatoes',
      'sausage',
      'pickled cucumber',
    ]);
    expect(_kept(['rassolnik', 'cucumber salad', 'olive bread']), [
      'rassolnik',
      'cucumber salad',
      'olive bread',
    ]);
  });

  test('meat the note names stays', () {
    expect(_kept(['solyanka', 'sausage', 'ham'], note: 'solyanka, sausage'), [
      'solyanka',
      'sausage',
    ]);
  });
}
