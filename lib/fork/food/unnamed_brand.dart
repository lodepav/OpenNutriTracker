import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/util/soft_text_score.dart';

/// How far a packaged product the name did not ask for sorts below a food
/// that matches as well (S196). Enough that a generic row a word short of
/// the product's exact name still wins: "pickled gherkins" scores Dawtona's
/// "Pickled Gherkins" 1.0 and the table's "Cucumber/gherkin, pickled" 0.6.
const unnamedBrandPenalty = 0.45;

/// A name asking for the food as sold, which the table leaves out and a
/// packet holds: a recipe's "penne pasta, uncooked".
final _asSold = RegExp(
  r'\b(raw|dry|dried|uncooked|unprepared)\b',
  caseSensitive: false,
);

/// [unnamedBrandPenalty] for an Open Food Facts product with a brand that
/// [query] does not name apart from the product's own name, or with none,
/// else 0 (S196).
///
/// A meal read off a photo names foods, not packets, and so does a model's
/// reading of typed text (S204); the resolver asks for those only, as the
/// parser's words may mean the packet:
/// "tomato" logged Maestri's tinned tomatoes by the cup, "sausages" Naked
/// Glory's plant-based ones, "oatmeal porridge" a dry porridge mix at 347
/// kcal per 100 g. The generic row is the food as eaten; a product only
/// wins where nothing generic matches near as well, or where the name
/// gives its brand ("Heinz baked beans"). Ordering only: the product stays
/// among the candidates, one tap away, and the confidence the review reads
/// is the text match's.
double unnamedBrandOf(MealEntity meal, String query) {
  if (meal.source != MealSourceEntity.off || _asSold.hasMatch(query)) {
    return 0;
  }
  // The first brand: a listing often adds its owner ("Freshona, Lidl").
  final brand = tokenize(meal.brands?.split(',').first);
  // A product with no brand is one no name can ask for: a brandless "Big
  // Mac" at no serving beat the table's, and logged 1 g of it.
  if (brand.isEmpty) return unnamedBrandPenalty;
  final named = tokenize(query);
  // A brand the product's own name holds ("Snickers bar" by Snickers, a
  // "rice pilaf" by "Rice Pilaf") is the food's words, not the user asking
  // for that packet: a plov's "pilaf with carrots and rice" logged a dry
  // pilaf mix at 339 kcal per 100 g.
  final asName = tokenize(meal.name);
  return brand.every(named.contains) && !brand.every(asName.contains)
      ? 0
      : unnamedBrandPenalty;
}
