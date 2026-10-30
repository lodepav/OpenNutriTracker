import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:opennutritracker/core/utils/ai_credential_storage.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/add_meal/data/meal_items_api_factory.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/meal_items_api.dart';
import 'package:opennutritracker/features/add_meal/domain/meal_photo_interpreter.dart';
import 'package:opennutritracker/features/add_meal/domain/usecase/resolve_parsed_meals_usecase.dart';

/// One serving of a dish, as ingredients matched against the food table.
class DishBreakdown {
  final String dish;

  /// The model's ingredients, each resolved like any other row. Only the
  /// grams are the model's; every nutrient comes from the matched food.
  final List<ResolvedMealItem> ingredients;

  const DishBreakdown(this.dish, this.ingredients);
}

/// Breaks a dish the tables lack into the ingredients of one serving (D12).
///
/// The same forced tool call and schema as upstream's text path, so the
/// model still returns names and amounts, never nutrients. The one
/// deviation is that it is asked for gram amounts nobody stated: upstream's
/// photo path refuses to estimate grams (#250), and this is the fork-only,
/// marked exception D12 makes for dishes with no table row. With the
/// photo the dish was read from, the grams are sized to the plate shown,
/// which the eval found mattered most: a typical serving runs low on a big
/// plate.
class BreakDownDishUseCase {
  final AiCredentialStorage _credentials;
  final MealItemsApi Function(AiSelection selection) _apiFor;
  final ResolveParsedMealsUseCase _resolver;

  BreakDownDishUseCase(this._credentials, this._apiFor, this._resolver);

  /// Built from upstream's registrations, so the fork needs no locator seam.
  factory BreakDownDishUseCase.fromLocator() => BreakDownDishUseCase(
    locator<AiCredentialStorage>(),
    (selection) => mealItemsApiFor(locator<http.Client>(), selection),
    locator<ResolveParsedMealsUseCase>(),
  );

  static const systemPrompt = '''
You break a dish into the ingredients of one typical serving, so each can be
looked up in a table of generic foods (USDA, BLS). You do not estimate
nutrition.

Rules:
- One entry per ingredient, weighed as it goes into the dish: raw, uncooked,
  as bought. Include oil, butter and salt when they are used; leave out water.
- "query" is the nearest generic ingredient in English, whatever language
  the dish is written in, named the way a food table names it: the food,
  then its form and state after commas. "egg, whole, raw", "carrot, raw",
  "wheat flour, white, all-purpose", "sour cream, regular", "beef, ground,
  raw". A bare "egg" or "carrot" finds a creamed egg or a dried carrot.
- A regional or branded ingredient becomes its generic equivalent: grey peas
  -> "split peas, raw", sulguni -> "cheese, mozzarella, whole milk",
  biezpiens -> "quark", speķis -> "pork bacon".
- Every entry has "quantity" in grams with "unit" "g". A liquid may use "ml".
  Never leave the amount out, never use "portion".
- An amount given is the whole of what was eaten: weigh the ingredients
  for it. A bare count is pieces, or servings of a dish not eaten in
  pieces.
- With a photo, break down only the named dish, sized to the portion the
  photo shows; leave out the other foods on the plate.
- A drink is not broken down: kvass, juice, a soft drink, beer, wine,
  coffee, tea, milk, a smoothie or a shake. Return an empty list for it.
  A soup is a dish, a cold one too.
- If the input is not a dish or food, return an empty list.''';

  /// The text the model is given. It has to state a unit: every client
  /// drops a unit the text it was given does not state (#977,
  /// `validateParsedMealItems`), which would turn the grams into bare
  /// counts. "e.g. 100 g" is what makes `textStatesAUnit` see one.
  /// [amount] is what the user stated ("500 ml", "3"); without one, one
  /// serving, or the portion in the photo.
  static String contentFor(String dish, {String? amount, bool photo = false}) {
    final size = amount != null
        // a bare count next to "amounts in grams" read as 2 g (Haiku)
        ? 'Amount: $amount${double.tryParse(amount) != null ? ' (a count, not grams)' : ''}'
        : photo
        ? 'The portion in the photo'
        : 'One serving';
    return 'Dish: ${dish.trim()}. $size; amounts in grams, e.g. 100 g';
  }

  /// Null when no model is configured. Raises [MealInterpreterException]
  /// when the model could not answer; unlike the text path there is no
  /// parser to fall back to.
  Future<DishBreakdown?> call(
    String dish, {
    String? amount,
    MealPhoto? photo,
  }) async {
    final selection = await _credentials.readSelection();
    if (selection == null) return null;
    final text = contentFor(dish, amount: amount, photo: photo != null);
    final reply = await _apiFor(selection).requestItems(
      // The clients send a photo's note after "List the foods in this
      // photo."; the system prompt narrows that to the dish. A photo keeps
      // the reply's units (only text is checked for one, #977).
      content: photo == null
          ? MealTextContent(text)
          : MealPhotoContent(
              mediaType: photo.mediaType,
              base64Data: base64Encode(photo.bytes),
              note: text,
            ),
      system: systemPrompt,
    );
    final resolved = await _resolver.resolve(reply.items);
    return DishBreakdown(dish, [
      for (final item in resolved) preferTableRow(item),
    ]);
  }
}

/// [item] with the food table's best row selected in place of a packaged
/// product. The resolver merges Open Food Facts and the table, and for a
/// generic name such as "cheese, mozzarella, whole milk" a product of that
/// name can outscore the table row; an ingredient of an estimated dish
/// wants the generic food, not a brand nobody named. Anything else the
/// resolver chose (a recipe, a custom meal, a table row) is kept, and so is
/// a product when the table has nothing.
ResolvedMealItem preferTableRow(ResolvedMealItem item) {
  if (item.selected?.source != MealSourceEntity.off) return item;
  final table = item.candidates.indexWhere(
    (m) => m.source == MealSourceEntity.fdc,
  );
  if (table < 0) return item;
  return ResolvedMealItem(
    parsed: item.parsed,
    candidates: item.candidates,
    selectedIndex: table,
    confidence: item.confidence,
  );
}
