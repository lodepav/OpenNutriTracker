import 'dart:convert';

import 'package:opennutritracker/features/add_meal/domain/meal_items_api.dart';
import 'package:opennutritracker/features/add_meal/domain/meal_photo_interpreter.dart';
import 'package:opennutritracker/features/add_meal/util/meal_text_parser.dart';
import 'package:opennutritracker/features/add_meal/util/soft_text_score.dart';
import 'package:opennutritracker/fork/bulk/note_counts.dart';
import 'package:opennutritracker/fork/bulk/note_weights.dart';
import 'package:opennutritracker/fork/dish/dish_breakdown_rows.dart';

/// A photo whose note states weights (S175, D24): the user weighed the
/// plate, or some of its foods. The model lists the plate's foods as served
/// with grams, and [weighedPlateItems] holds them to what the note states:
/// a food's own weight exactly, the rest sized to the total, and with no total
/// the rest at the model's estimate (the user, 2026-11-01): a default serving
/// logged a burger's 25 g of bacon as 85 g.
const weighedPlatePrompt = '''
You list the foods on a plate the user has weighed, so each can be looked up
in a table of generic foods (USDA, BLS). You do not estimate nutrition.

The user's note states weights. Rules:
- If the note names one plain food and nothing else ("a banana", "greek
  yogurt 200g"), return just that one item: "query" its name as the note
  writes it, with the note's weight as "quantity" and "unit". Food on the
  bone is not plain: see bones below.
- Otherwise the first item names the plate: "query" is "dish=" and the name
  the note gives it, without its weight, in the user's app language; when
  the note gives no name for the whole meal, a short one ("dish=Chicken
  rice bowl"). It has no quantity.
- Then one item per food on the plate, as served (cooked, as eaten, not
  raw), a named dish too: a pizza is its crust, sauce, cheese and each
  topping; loaded fries are the fries, each topping and each sauce on them;
  melted cheese poured over them is "cheese sauce", not a block of cheese;
  a soup or stew is its broth or base and each solid in it. A sauce poured
  over is a food. A salad lists its dressing: the oil, vinaigrette or
  mayonnaise the note or the photo shows, and when it looks dressed with
  nothing to say what, oil, a tablespoon (14 g) for each 150 g of salad.
  Every food the note names is among them; the rest are what the photo
  shows. "query" is the nearest generic food in English, named
  the way a food table names it: the food, then its form and state after
  commas ("chicken breast, grilled", "rice, white, cooked", "potatoes,
  roasted", "spinach, raw"). Fries from a kitchen are "french fries, fast
  food".
- Every food has "quantity" in grams with "unit" "g".
- A weight the note gives a food is copied exactly.
- A total weight in the note is the whole plate: give each food without a
  weight of its own its share of what remains, judged from the photo, so
  that all the foods add up to the total.
- A number of patties the note gives ("with 3 patties", "3 patty burger",
  "double") is how many there are, whatever the photo shows: their share of
  the weight is for that many, about 90 g each when the total allows it.
- The scale weighed the bones, nobody eats them: food on the bone (ribs,
  wings, drumsticks, a bone-in chop) is the meat as eaten and one more item,
  "bones", with their share of the weight: about 35% of ribs, 45% of wings,
  30% of a drumstick, thigh or chop.
- Leave out water, salt and garnish nobody eats.
- If the photo contains no food, return an empty list.''';

/// A photo whose note names the meal but states no weight (D25): the model
/// estimates each food's grams from the photo, by the sizes of what it sits
/// in and of its pieces. Measured in `portion_eval_test.dart` with Haiku:
/// the meals' median kcal 21% off against 31% for counts and the table's
/// serving, and weights 16% off the six known ones; asking it to write
/// down its scale first, or to fall back to a typical serving, did no
/// better. A named dish is split into its foods (the user, 2026-10-30): a
/// pizza searched by its name found a puffed snack. The screen asks the
/// user to check every amount.
const estimatedPlatePrompt = '''
You list the foods on a plate and estimate how much of each was served, so
each can be looked up in a table of generic foods (USDA, BLS). You do not
estimate nutrition.

The user's note names the meal, or says what a food on it is ("the cheese
is sulguni"), but states no weight. Rules:
- If the note names one plain food and nothing else ("a banana", "greek
  yogurt"), return just that one item: "query" its name, with your
  estimate of its weight as served, every piece of it the photo shows
  ("meatballs": all of them, not one).
- Otherwise the first item names the meal: "query" is "dish=" and the name
  the note gives it, without any size it gives, in the user's app
  language; when the note gives no name for the whole meal, a short one
  ("dish=Chicken rice bowl"). It has no quantity.
- Then one item per food in it, as served (cooked, as eaten, not raw),
  a named dish too: a pizza is its crust, sauce, cheese and each topping;
  loaded fries are the fries and each topping, melted cheese poured over them
  "cheese sauce", not a block of cheese;
  a soup or stew is its broth or base and each solid in it, so none of it
  goes missing. The base is the liquid alone ("chicken broth", "coconut
  milk", "tomato puree"), never the soup itself ("soup, lentil"): that
  counts its solids twice. A salad or slaw lists its dressing as a food: the oil,
  vinaigrette, mayonnaise or sour cream the note or the photo shows, and
  when it looks dressed with nothing to say what, oil, a tablespoon (14 g)
  for each 150 g of salad. Fat a food was cooked in that its own query
  does not name is a food too: the butter a grilled cheese or toast was
  fried in (10 g a sandwich), the oil a soup's, stew's or sauce's
  vegetables were softened in (5 g a serving). A query that says "fried"
  already holds its fat. Every food the note names is among them; the
  rest are what the photo shows, a food the note says what it is taken to
  be that.
  "query" is the nearest generic food in English, named the way a food
  table names it: the food, then its form and state after commas
  ("chicken breast, grilled", "rice, white, cooked", "potatoes, roasted",
  "spinach, raw"). Fries from a kitchen are "french fries, fast food".
- Every food has "quantity" in grams with "unit" "g" (a drink or soup may
  use "ml"): your estimate of what the photo shows. Judge it by what the
  food sits in, how much of it the food fills and how high it is piled.
  Sizes to go by: a dinner plate is about 26 cm across, a side plate 20 cm,
  a soup bowl 15-18 cm and about 350 ml when full, a gravy boat or dip pot
  30-60 ml; a fork or knife is about 20 cm, a tablespoon's bowl 4 cm wide.
  A size the note gives ("a 23 cm pizza") is the dish's size: weigh its
  foods by that, not by the plate.
  Weigh pieces by their size: a cutlet or chop about 80-150 g, a slice of
  bread 30 g, an egg 50 g (two halves are one egg), a taco's tortilla 40 g, a wrap's 70 g, a whole pizza of any shape at least 350 g even if
  small, 30 cm across 450-550 g, a thick pan pizza twice that for its area.
  A number of patties the note gives ("with 3 patties", "3 patty burger",
  "double") is how many there are, whatever the photo shows, about 90 g each.
  Food on the bone is weighed without its bones.
- Leave out water, salt and garnish nobody eats.
- If the photo contains no food, return an empty list.''';

const _dishKey = 'dish=';
const _bones = 'bones';

/// Reads [photo] as a weighed plate; [weights] is what [note] states.
Future<MealTextParseResult> readWeighedPlate(
  MealItemsApi api,
  MealPhoto photo, {
  required String note,
  required NoteWeights weights,
  String? localeCode,
  String? savedDishes,
}) => _readPlate(
  api,
  photo,
  weighedPlatePrompt,
  (items) => weighedPlateItems(items, weights),
  note: note,
  localeCode: localeCode,
  savedDishes: savedDishes,
);

/// Whether [note] names the meal and states no amount, neither a weight
/// nor a count: a count the user gave is kept as given (S170), on the
/// photo prompt. A size ("a 23 cm pizza") is no amount: the model weighs
/// the food by it.
bool noteStatesNoAmount(String? note) =>
    note != null &&
    note.trim().isNotEmpty &&
    !noteHasCount(withoutPartCounts(note)) &&
    parseMealText(
      withoutSizes(withoutPartCounts(note)),
    ).items.every((item) => item.quantity == null);

/// Reads [photo] with a [note] that states no amount: every food at the
/// model's estimate of its grams.
Future<MealTextParseResult> readEstimatedPlate(
  MealItemsApi api,
  MealPhoto photo, {
  required String note,
  String? localeCode,
  String? savedDishes,
}) => _readPlate(
  api,
  photo,
  estimatedPlatePrompt,
  (items) => weighedPlateItems(items, const NoteWeights()),
  note: note,
  localeCode: localeCode,
  savedDishes: savedDishes,
);

Future<MealTextParseResult> _readPlate(
  MealItemsApi api,
  MealPhoto photo,
  String prompt,
  List<ParsedMealItem> Function(List<ParsedMealItem>) hold, {
  required String note,
  String? localeCode,
  String? savedDishes,
}) async {
  final reply = await api.requestItems(
    content: MealPhotoContent(
      mediaType: photo.mediaType,
      base64Data: base64Encode(photo.bytes),
      note: note,
    ),
    system:
        prompt +
        (localeCode == null
            ? ''
            : '\nThe user\'s app language is "$localeCode".') +
        (savedDishes == null ? '' : '\n$savedDishes'),
  );
  return MealTextParseResult(items: hold(reply.items), errors: reply.errors);
}

/// The model's [items] held to [weights]: one food comes back as a plain
/// row at the plate's weight; several, as one dish's ingredients in grams
/// that add up to the total, or at the model's grams with none.
List<ParsedMealItem> weighedPlateItems(
  List<ParsedMealItem> items,
  NoteWeights weights,
) {
  String? dish;
  final foods = <({String query, double? grams, double? count})>[];
  for (final item in items) {
    final query = item.query.trim();
    if (query.toLowerCase().startsWith(_dishKey)) {
      dish ??= query.substring(_dishKey.length).trim();
      continue;
    }
    final grams = item.unit == 'g' || item.unit == 'ml' ? item.quantity : null;
    foods.add((
      query: query,
      grams: grams != null && grams > 0 ? grams : null,
      // a count is the model's to give (S170), a weight is not
      count: item.unit == null ? item.quantity : null,
    ));
  }

  // The one weight a note naming one thing gives, on what the model split as
  // a dish ("350g plov"), is the whole dish's.
  final wholeDish =
      dish != null &&
      weights.totalGrams == null &&
      weights.namesOneThing &&
      weights.foods.length == 1;

  // Each food the note weighs takes its weight, on the food its name agrees
  // with best ("carrot" with "carrots, raw"), else is added as the note
  // names it.
  final stated = <int, double>{};
  for (final weight in wholeDish ? const <FoodWeight>[] : weights.foods) {
    final words = tokenize(weight.name);
    int? match;
    var best = 0.0;
    for (final (i, food) in foods.indexed) {
      final score = stated.containsKey(i) ? 0.0 : scoreText(food.query, words);
      if (score > best) (match, best) = (i, score);
    }
    if (match != null) {
      stated[match] = weight.grams;
    } else {
      foods.add((query: weight.name, grams: null, count: null));
      stated[foods.length - 1] = weight.grams;
    }
  }

  final total =
      weights.totalGrams ?? (wholeDish ? weights.foods.single.grams : null);
  final grams = <double?>[
    for (final (i, food) in foods.indexed) stated[i] ?? food.grams,
  ];
  if (total != null) _sizeToTotal(grams, stated.keys.toSet(), total);

  // Bones took their share of the total above; nobody eats them.
  final eaten = [
    for (final (i, food) in foods.indexed)
      if (food.query.toLowerCase() != _bones) i,
  ];
  if (eaten.isEmpty) return const [];
  if (eaten.length == 1) {
    final only = foods[eaten.single];
    final weight = grams[eaten.single] ?? total;
    return [
      ParsedMealItem(
        query: only.query,
        quantity: weight ?? only.count,
        unit: weight == null ? null : 'g',
      ),
    ];
  }
  final group = Object();
  return [
    for (final i in eaten)
      DishIngredientItem(
        query: foods[i].query,
        quantity: grams[i] ?? foods[i].count,
        unit: grams[i] == null ? null : 'g',
        dish: dish == null || dish.isEmpty ? 'Meal' : dish,
        group: group,
      ),
  ];
}

/// Sizes the foods not in [fixed] so that all of [grams] add up to [total],
/// keeping the model's proportions between them, in whole grams. A food the
/// model gave no weight takes an even share. Nothing changes when the
/// stated weights already reach the total.
void _sizeToTotal(List<double?> grams, Set<int> fixed, double total) {
  final free = [
    for (var i = 0; i < grams.length; i++)
      if (!fixed.contains(i)) i,
  ];
  final remaining =
      total - fixed.fold<double>(0, (sum, i) => sum + (grams[i] ?? 0));
  if (free.isEmpty || remaining <= 0) return;
  final known = [for (final i in free) grams[i]].nonNulls;
  final even = known.isEmpty
      ? 1.0
      : known.reduce((a, b) => a + b) / known.length;
  final shares = {for (final i in free) i: grams[i] ?? even};
  final sum = shares.values.reduce((a, b) => a + b);
  for (final i in free) {
    grams[i] = (shares[i]! * remaining / sum).roundToDouble();
  }
  // Rounding's leftover goes to the largest, so the plate adds up exactly.
  final largest = free.reduce((a, b) => grams[a]! >= grams[b]! ? a : b);
  final drift = remaining - free.fold<double>(0, (sum, i) => sum + grams[i]!);
  grams[largest] = grams[largest]! + drift;
}
