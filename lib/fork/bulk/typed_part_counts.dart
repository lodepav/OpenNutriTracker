import 'package:opennutritracker/features/add_meal/util/meal_text_parser.dart';

/// A typed count of a burger's patties is not how many burgers there are (S187):
/// "smash burger with 3 patties" and "3 patty smash burger" come back from the
/// model as 3 burgers, and the second from the parser too. Such an item goes
/// back to the words the user typed, with no quantity, so the dish's breakdown
/// reads the count; a real count of the dish stays with it. "3 patties, bun"
/// names the patties themselves and stays.
MealTextParseResult keepPattyCounts(String input, MealTextParseResult result) {
  final segments = input.split(_segment);
  final dishes = [
    for (final item in result.items) (item, _wholeDish(segments, item)),
  ];
  final anyDish = dishes.any((d) => d.$2 != null);
  return MealTextParseResult(
    errors: result.errors,
    items: [
      for (final (item, dish) in dishes)
        // The dish holds its patties now: "burger x2, beef patty x6" is not both.
        if (dish != null) dish else if (!anyDish || !_namesPatties(item)) item,
    ],
  );
}

bool _namesPatties(ParsedMealItem item) =>
    item.unit == null && _pattyWord.hasMatch(item.query);

ParsedMealItem? _wholeDish(List<String> segments, ParsedMealItem item) {
  if (item.unit != null) return null;
  final food = item.query.replaceAll(_pattyWord, ' ').trim().toLowerCase();
  if (food.isEmpty) return null;
  for (final segment in segments) {
    final count = _pattyCount.firstMatch(segment);
    if (count == null) continue;
    // The dish comes before "with": "burger with 3 patties with fries".
    final dish = segment
        .replaceRange(count.start, count.end, ' ')
        .toLowerCase()
        .split(_with)
        .first;
    if (!dish.contains(food)) continue;
    final patties = double.parse(count[1]!);
    if (item.quantity == null || item.quantity == patties) {
      return ParsedMealItem(query: segment.trim());
    }
    // "2 burgers with 3 patties": 2 of the dish, named with its patties.
    return ParsedMealItem(
      query: segment.trim().replaceFirst(_leadingCount, ''),
      quantity: item.quantity,
      portion: item.portion,
    );
  }
  return null;
}

final _with = RegExp(r'\bwith\b');
final _leadingCount = RegExp(
  r'^(?:\d+\s*x?|an?|one|two|three|four)\s+(?!x?\s*-?\s*patt)',
  caseSensitive: false,
);
final _segment = RegExp(r',|;|\n|\+|\band\b', caseSensitive: false);
final _pattyWord = RegExp(r'\b(?:patty|patties)\b', caseSensitive: false);
final _pattyCount = RegExp(
  r'(?<![\d.,])(\d+)\s*x?\s*-?\s*(?:patty|patties)\b',
  caseSensitive: false,
);
