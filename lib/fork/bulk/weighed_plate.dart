import 'dart:convert';

import 'package:opennutritracker/features/add_meal/domain/meal_items_api.dart';
import 'package:opennutritracker/features/add_meal/domain/meal_photo_interpreter.dart';
import 'package:opennutritracker/features/add_meal/util/meal_text_parser.dart';
import 'package:opennutritracker/features/add_meal/util/soft_text_score.dart';
import 'package:opennutritracker/fork/bulk/note_counts.dart';
import 'package:opennutritracker/fork/bulk/note_weights.dart';
import 'package:opennutritracker/fork/dish/dish_breakdown_rows.dart';

/// What every plate-reading prompt opens with: [plateItemsSchemaFor] tells
/// these requests apart by it.
const plateReadOpening = 'You list the foods on a plate';

/// A photo whose note states weights (S175, D24): the user weighed the
/// plate, or some of its foods. The model lists the plate's foods as served
/// with grams, and [weighedPlateItems] holds them to what the note states:
/// a food's own weight exactly, the rest sized to the total, and with no total
/// the rest at the model's estimate (the user, 2026-11-01): a default serving
/// logged a burger's 25 g of bacon as 85 g.
const weighedPlatePrompt =
    '''
$plateReadOpening the user has weighed, so each can be looked up
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
/// estimates each food's grams from the photo, by the size of what it sits
/// in. Measured in `portion_eval_test.dart` with Haiku: the meals' median
/// kcal 21% off against 31% for counts and the table's serving, and weights
/// 16% off the six known ones; asking it to write down its scale first, or
/// to fall back to a typical serving, did no better. A named dish is split
/// into its foods (the user, 2026-10-30): a pizza searched by its name
/// found a puffed snack. The screen asks the user to check every amount.
/// The per-piece weights it once gave (a cutlet 80-150 g, a slice of bread
/// 30 g, a whole pizza at least 350 g) went in D42: without them 51 unseen
/// weighed plates came in nearer, and meat landed on 100 g no more often.
final estimatedPlatePrompt = _estimatedPlatePrompt(withNote: true);

/// A photo with no note (D42): the same estimate, every food from the
/// photo alone.
final noNotePlatePrompt = _estimatedPlatePrompt(withNote: false);

String _estimatedPlatePrompt({required bool withNote}) {
  final rules = withNote
      ? '''
The user's note names the meal, or says what a food on it is ("the cheese
is sulguni"), but states no weight. Rules:
- If the note names one plain food and nothing else ("a banana", "greek
  yogurt"), return just that one item:'''
      : '''
There is no note from the user. Rules:
- If the photo shows one plain food and nothing else (a banana, a pot of
  yogurt), return just that one item:''';
  final dishName = withNote
      ? '''
the name
  the note gives it, without any size it gives, in the user's app
  language; when the note gives no name for the whole meal, a short one
  ("dish=Chicken rice bowl").'''
      : '''
a short
  name for the whole meal in the user's app language ("dish=Chicken
  rice bowl").''';
  final dressingSeen = withNote
      ? 'the note or the photo shows'
      : 'the photo shows';
  final whichFoods = withNote
      ? ' Every food the note names is among them; the\n'
            '  rest are what the photo shows, a food the note says what it is '
            'taken to\n'
            '  be that.'
      : ' They are the foods the photo shows.';
  final noteSizes = withNote
      ? '''

  A size the note gives ("a 23 cm pizza") is the dish's size: weigh its
  foods by that, not by the plate.
  A number of patties the note gives ("with 3 patties", "3 patty burger",
  "double") is how many there are, whatever the photo shows, about 90 g each.'''
      : '';
  return '''
$plateReadOpening and estimate how much of each was served, so
each can be looked up in a table of generic foods (USDA, BLS). You do not
estimate nutrition.

$rules "query" its name, with your
  estimate of its weight as served, every piece of it the photo shows
  ("meatballs": all of them, not one).
- Otherwise the first item names the meal: "query" is "dish=" and $dishName It has no quantity.
- Then one item per food in it, as served (cooked, as eaten, not raw),
  a named dish too: a pizza is its crust, sauce, cheese and each topping;
  loaded fries are the fries and each topping, melted cheese poured over them
  "cheese sauce", not a block of cheese;
  a soup or stew is its broth or base and each solid in it, so none of it
  goes missing. The base is the liquid alone ("chicken broth", "coconut
  milk", "tomato puree"), never the soup itself ("soup, lentil"): that
  counts its solids twice. A bowl's foods together, base and solids and
  what is on top, weigh what the bowl holds: the solids take the base's
  place and never add to it, so a full 350 ml bowl with 150 g of solids
  has 200 g of base. A salad or slaw lists its dressing as a food: the oil,
  vinaigrette, mayonnaise or sour cream $dressingSeen, and
  when it looks dressed with nothing to say what, oil, a tablespoon (14 g)
  for each 150 g of salad. Fat a food was cooked in that its own query
  does not name is a food too: the butter a grilled cheese or toast was
  fried in (10 g a sandwich), the oil a soup's, stew's or sauce's
  vegetables were softened in (5 g a serving). A query that says "fried"
  already holds its fat.$whichFoods
  "query" is the nearest generic food in English, named the way a food
  table names it: the food, then its form and state after commas
  ("chicken breast, grilled", "rice, white, cooked", "potatoes, roasted",
  "spinach, raw"). Fries from a kitchen are "french fries, fast food".
- Every food has "quantity" in grams with "unit" "g" (a drink or soup may
  use "ml"): your estimate of what the photo shows. Judge it by what the
  food sits in, how much of it the food fills and how high it is piled.
  Sizes to go by: a dinner plate is about 26 cm across, a side plate 20 cm,
  a soup bowl 15-18 cm and about 350 ml when full, a gravy boat or dip pot
  30-60 ml; a fork or knife is about 20 cm, a tablespoon's bowl 4 cm wide.$noteSizes
  Food on the bone is weighed without its bones.
- Leave out water, salt and garnish nobody eats.
- If the photo contains no food, return an empty list.''';
}

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
  bool askAgainForGrams = true,
}) => _readPlate(
  api,
  photo,
  weighedPlatePrompt,
  (items) => weighedPlateItems(items, weights),
  note: note,
  localeCode: localeCode,
  savedDishes: savedDishes,
  askAgainForGrams: askAgainForGrams,
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

/// Reads [photo] with a [note] that states no amount, or with no note
/// (null, D42): every food at the model's estimate of its grams.
/// With [askAgainForGrams] false a food left without grams is not asked
/// for again: the endpoint probe, which counts items, stays two requests.
Future<MealTextParseResult> readEstimatedPlate(
  MealItemsApi api,
  MealPhoto photo, {
  required String? note,
  String? localeCode,
  String? savedDishes,
  bool askAgainForGrams = true,
}) => _readPlate(
  api,
  photo,
  note == null ? noNotePlatePrompt : estimatedPlatePrompt,
  (items) => weighedPlateItems(items, const NoteWeights()),
  note: note,
  localeCode: localeCode,
  savedDishes: savedDishes,
  askAgainForGrams: askAgainForGrams,
);

/// What a read that left a food without grams is asked again with (D42).
const everyFoodGramsLine =
    '- Every food has a "quantity" in grams, even a spoonful of seeds or a '
    'drizzle of sauce: none is left without one.';

Future<MealTextParseResult> _readPlate(
  MealItemsApi api,
  MealPhoto photo,
  String prompt,
  List<ParsedMealItem> Function(List<ParsedMealItem>) hold, {
  required String? note,
  String? localeCode,
  String? savedDishes,
  bool askAgainForGrams = true,
}) async {
  Future<MealTextParseResult> ask(String system) => api.requestItems(
    content: MealPhotoContent(
      mediaType: photo.mediaType,
      base64Data: base64Encode(photo.bytes),
      note: note,
    ),
    system:
        system +
        (localeCode == null
            ? ''
            : '\nThe user\'s app language is "$localeCode".') +
        (savedDishes == null ? '' : '\n$savedDishes'),
  );
  // The meal's name given without "dish=" is no food left without grams,
  // so it is taken as the name before anything is counted.
  var reply = await ask(prompt);
  var items = _namedDish(reply.items);
  // A food left without grams fell to its table default: chia seeds at
  // 100 g against 13. Asked once more, a read gives them; when it still
  // does not, the one with fewer such foods is kept, and those foods start
  // where any amount nobody stated starts (D42).
  final missing = _withoutGrams(items);
  if (missing > 0 && askAgainForGrams) {
    try {
      final again = await ask('$prompt\n$everyFoodGramsLine');
      final againItems = _namedDish(again.items);
      if (againItems.isNotEmpty && _withoutGrams(againItems) <= missing) {
        reply = again;
        items = againItems;
      }
    } on MealInterpreterException {
      // the first read stands
    }
  }
  return MealTextParseResult(items: hold(items), errors: reply.errors);
}

/// How many of [items] are foods without grams; the "dish=" item names the
/// meal and needs none.
int _withoutGrams(List<ParsedMealItem> items) => items.where((item) {
  if (item.query.trim().toLowerCase().startsWith(_dishKey)) return false;
  final grams = item.unit == 'g' || item.unit == 'ml' ? item.quantity : null;
  return grams == null || grams <= 0;
}).length;

/// [items] with a first item that has no quantity and no "dish=" taken as
/// the meal's name, when the rest have grams (D42): "Chicken dinner plate"
/// was logged as a food at its table default.
List<ParsedMealItem> _namedDish(List<ParsedMealItem> items) {
  if (items.length < 2 ||
      items.any((i) => i.query.trim().toLowerCase().startsWith(_dishKey)) ||
      items.first.quantity != null ||
      !items.skip(1).any((i) => i.unit == 'g' || i.unit == 'ml')) {
    return items;
  }
  return [
    ParsedMealItem(query: '$_dishKey${items.first.query.trim()}'),
    ...items.skip(1),
  ];
}

/// The tool schema for a request with [system] as its prompt: a plate read
/// (every prompt opening with [plateReadOpening]) asks for each food's
/// grams, so its `quantity` and `unit` say so (D42); every other request
/// keeps [mealItemsToolSchema] as it is. Only those two descriptions
/// differ, so the plate schema carries no nutrition field either.
Map<String, Object?> plateItemsSchemaFor(String system) =>
    system.startsWith(plateReadOpening)
    ? plateItemsToolSchema
    : mealItemsToolSchema;

/// [mealItemsToolSchema] with `quantity` and `unit` described as the
/// plate prompts ask for them.
final Map<String, Object?> plateItemsToolSchema = _plateSchema();

Map<String, Object?> _plateSchema() {
  final schema =
      jsonDecode(jsonEncode(mealItemsToolSchema)) as Map<String, dynamic>;
  final item = schema['properties']['items']['items'] as Map<String, dynamic>;
  final properties = item['properties'] as Map<String, dynamic>;
  properties['quantity'] = {
    'type': 'number',
    'description':
        'The food\'s weight as served in grams, your estimate from the '
        'photo, or the weight the user stated. Omit only on a "dish=" item.',
  };
  properties['unit'] = {
    'type': 'string',
    'enum': ['g', 'ml'],
    'description': '"g", or "ml" for a drink or soup.',
  };
  return schema;
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
