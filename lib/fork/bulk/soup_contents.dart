// A photo's soup with its own meat listed beside it (S199): a solyanka came
// back as the soup, sausage, beef and smoked meat, so the meat the soup's
// row already holds was counted twice, though the prompt says not to.
import 'package:opennutritracker/features/add_meal/util/meal_text_parser.dart';
import 'package:opennutritracker/features/add_meal/util/soft_text_score.dart';
import 'package:opennutritracker/fork/food/soup_serving.dart';

/// The meats a soup is cooked with, named plainly.
final _soupMeat = RegExp(
  r'^((smoked|sliced|diced|chopped|boiled|cooked|pieces of|bits of)\s+)*'
  r'(sausages?|frankfurters?|wieners?|ham|bacon|salami|kielbasa|beef|'
  r'pork|meat|brisket)$',
  caseSensitive: false,
);

/// [result] without the plain meats listed beside a soup, unless [note]
/// names them: the soup's row holds its meat. A dish beside the bowl
/// ("roast beef", "pork chop") is a dish and stays, and so does what
/// nothing in the read says is a soup.
MealTextParseResult withoutSoupMeats(MealTextParseResult result, String? note) {
  if (!result.items.any((item) => isSoup(item.query))) return result;
  final noted = note == null ? const <String>{} : tokenize(note).toSet();
  bool cookedIn(ParsedMealItem item) =>
      _soupMeat.hasMatch(item.query.trim()) &&
      !tokenize(item.query).any(noted.contains);
  if (!result.items.any(cookedIn)) return result;
  return MealTextParseResult(
    items: [
      for (final item in result.items)
        if (!cookedIn(item)) item,
    ],
    errors: result.errors,
  );
}
