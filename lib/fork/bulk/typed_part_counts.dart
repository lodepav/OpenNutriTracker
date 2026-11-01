import 'package:opennutritracker/features/add_meal/util/meal_text_parser.dart';

/// A typed count of a burger's patties is not how many burgers there are (S187):
/// "smash burger with 3 patties" and "3 patty smash burger" come back from the
/// model as 3 burgers, and the second from the parser too. Such an item goes
/// back to the words the user typed, with no quantity, so the dish's breakdown
/// reads the count. "3 patties, bun" names the patties themselves and stays.
MealTextParseResult keepPattyCounts(String input, MealTextParseResult result) {
  final segments = input.split(_segment);
  return MealTextParseResult(
    errors: result.errors,
    items: [
      for (final item in result.items) _wholeDish(segments, item) ?? item,
    ],
  );
}

ParsedMealItem? _wholeDish(List<String> segments, ParsedMealItem item) {
  final food = item.query.replaceAll(_pattyWord, ' ').trim().toLowerCase();
  if (food.isEmpty) return null;
  for (final segment in segments) {
    final count = _pattyCount.firstMatch(segment);
    if (count == null || double.parse(count[1]!) != item.quantity) continue;
    final rest = segment
        .replaceRange(count.start, count.end, ' ')
        .toLowerCase();
    if (rest.contains(food)) return ParsedMealItem(query: segment.trim());
  }
  return null;
}

final _segment = RegExp(r',|;|\n|\+|\band\b', caseSensitive: false);
final _pattyWord = RegExp(r'\b(?:patty|patties)\b', caseSensitive: false);
final _pattyCount = RegExp(
  r'(?<![\d.,])(\d+)\s*x?\s*-?\s*(?:patty|patties)\b',
  caseSensitive: false,
);
