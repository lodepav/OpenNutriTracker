import 'dart:convert';

import 'package:opennutritracker/features/add_meal/domain/meal_items_api.dart';
import 'package:opennutritracker/features/add_meal/domain/meal_photo_interpreter.dart';
import 'package:opennutritracker/features/add_meal/util/meal_text_parser.dart';
import 'package:opennutritracker/features/add_meal/util/soft_text_score.dart';
import 'package:opennutritracker/fork/bulk/note_weights.dart';
import 'package:opennutritracker/fork/dish/dish_breakdown_rows.dart';

/// A photo whose note states weights (S175, D24): the user weighed the
/// plate, or some of its foods. The model lists the plate's foods as served
/// with grams, and [weighedPlateItems] holds them to what the note states:
/// a food's own weight exactly, and the rest sized to the total. The model
/// only judges the split, from the photo, of a weight the user gave; a
/// weight nobody gave is still never taken from a photograph (#250).
const weighedPlatePrompt = '''
You list the foods on a plate the user has weighed, so each can be looked up
in a table of generic foods (USDA, BLS). You do not estimate nutrition.

The user's note states weights. Rules:
- If the note names one dish or food and nothing else, return just that one
  item: "query" its name as the note writes it, with the note's weight as
  "quantity" and "unit". Do not split it into ingredients.
- Otherwise the first item names the plate: "query" is "dish=" and a short
  name for the whole meal in the user's app language ("dish=Chicken rice
  bowl"), with no quantity.
- Then one item per food on the plate, as served (cooked, as eaten, not
  raw): every food the note names, and when the note names none, every food
  the photo shows. "query" is the nearest generic food in English, named
  the way a food table names it: the food, then its form and state after
  commas ("chicken breast, grilled", "rice, white, cooked", "potatoes,
  roasted", "spinach, raw").
- Every food has "quantity" in grams with "unit" "g".
- A weight the note gives a food is copied exactly.
- A total weight in the note is the whole plate: give each food without a
  weight of its own its share of what remains, judged from the photo, so
  that all the foods add up to the total.
- Leave out water, salt and garnish nobody eats.
- If the photo contains no food, return an empty list.''';

const _dishKey = 'dish=';

/// Reads [photo] as a weighed plate; [weights] is what [note] states.
Future<MealTextParseResult> readWeighedPlate(
  MealItemsApi api,
  MealPhoto photo, {
  required String note,
  required NoteWeights weights,
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
        weighedPlatePrompt +
        (localeCode == null
            ? ''
            : '\nThe user\'s app language is "$localeCode".') +
        (savedDishes == null ? '' : '\n$savedDishes'),
  );
  return MealTextParseResult(
    items: weighedPlateItems(reply.items, weights),
    errors: reply.errors,
  );
}

/// The model's [items] held to [weights]: one food comes back as a plain
/// row at the plate's weight; several, as one dish's ingredients in grams
/// that add up to the total.
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

  // Each food the note weighs takes its weight, on the food its name agrees
  // with best ("carrot" with "carrots, raw"), else is added as the note
  // names it.
  final stated = <int, double>{};
  for (final weight in weights.foods) {
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

  final total = weights.totalGrams;
  final grams = <double?>[
    for (final (i, food) in foods.indexed)
      stated[i] ??
          // the model's split of a weight the user gave, never its own
          // estimate of one nobody gave
          (total != null ? food.grams : null),
  ];
  if (total != null) _sizeToTotal(grams, stated.keys.toSet(), total);

  if (foods.isEmpty) return const [];
  if (foods.length == 1) {
    final weight = grams.single ?? total;
    return [
      ParsedMealItem(
        query: foods.single.query,
        quantity: weight ?? foods.single.count,
        unit: weight == null ? null : 'g',
      ),
    ];
  }
  final group = Object();
  final known = grams.nonNulls;
  final plate = total ?? (known.isEmpty ? null : known.reduce((a, b) => a + b));
  return [
    for (final (i, food) in foods.indexed)
      DishIngredientItem(
        query: food.query,
        quantity: grams[i] ?? food.count,
        unit: grams[i] == null ? null : 'g',
        dish: dish == null || dish.isEmpty ? 'Meal' : dish,
        group: group,
        dishGrams: plate,
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
