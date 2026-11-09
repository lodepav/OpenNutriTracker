import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/util/soft_text_score.dart';
import 'package:opennutritracker/fork/food/local_food_data_source.dart';

/// Above this, a starchy row is the dry food: cooked pasta, rice and pulses
/// are about 100-180 kcal per 100 g, dry ones about 340-370.
const _dryKcal = 250.0;

final _asksForUncooked = RegExp(
  r'\b(raw|dry|dried|uncooked|unprepared)\b',
  caseSensitive: false,
);

/// Words that say how a food was made, not which food it is: the food in
/// "rice cooked" is still the rice.
final _with = RegExp(r'\s(with|and|in)\s', caseSensitive: false);

const _stateWords = {'cooked', 'boiled', 'steamed'};

/// [ranked] with the dry rows of a food eaten cooked moved last (S186).
///
/// Food on a plate is cooked, but the rows a search finds are often dry: a
/// packet's label gives the food as sold. A photo of cooked penne logged
/// Barilla's "Penne Pasta" at 357 kcal per 100 g, so 280 g read 1000 kcal
/// against about 440. The bundled table already leaves out its dry rows
/// (`_servedNotDry`, `listedAfter`), which Open Food Facts never reaches.
///
/// A row is dry by what it holds, since a label rarely says so. The rule
/// stands down when the name asks for the food dry or raw, as a recipe's
/// ingredients do, and for a product whose brand the name gives ("100 g
/// Barilla penne"): someone naming the packet means the packet. The dry rows
/// stay among the candidates, one tap away, unless [modelRead] and they are
/// all there is.
List<MealEntity> dryRowsLast(
  List<MealEntity> ranked,
  String query, {
  bool modelRead = false,
}) {
  if (_namesReadyFood(query)) return _mixesLast(ranked, query);
  if (_asksForUncooked.hasMatch(query) || !_namesFoodEatenCooked(query)) {
    return ranked;
  }
  final named = tokenize(query);
  // The whole brand: "red lentils" does not name Bob's Red Mill. Only the
  // first, as a listing often adds its owner ("Barilla, Barilla G.e.R.").
  bool brandNamed(MealEntity meal) {
    final brand = tokenize(meal.brands?.split(',').first);
    return brand.isNotEmpty && brand.every(named.contains);
  }

  bool dry(MealEntity meal) {
    final food = meal.nutriments;
    return (food.energyKcal100 ?? 0) > _dryKcal &&
        (food.carbohydrates100 ?? 0) > 50 &&
        !brandNamed(meal);
  }

  final cooked = ranked.where((m) => !dry(m)).toList();
  // A model's read with nothing but the dry product: none, so the dish is
  // broken down (D9) into foods as eaten. A typed "griķi ar sēnēm" logged
  // Uvelka's dry buckwheat-with-mushrooms mix, 347 kcal per 100 g.
  if (modelRead && cooked.isEmpty) return const [];
  return [...cooked, ...ranked.where(dry)];
}

/// Above this per 100 g, a drink, soup or mash is the powder it is made
/// from: a latte is about 40-80 kcal, a soup 20-150, mashed potatoes about
/// 100; their powders and flakes 350-450.
const _mixKcal = 250.0;

/// What a powder or a mix's name says it is.
final _mixWords = RegExp(
  r'\b(powder|powdered|mix|instant|granules|granulated|dehydrated|'
  r'concentrate|flakes|cubes?|pulver|sachets?|bouillon cubes?)\b',
  caseSensitive: false,
);

/// A food eaten made up from a powder or flakes, by the last word before
/// the first comma ("latte", "tomato soup", "mashed potatoes").
final _readyFood = RegExp(
  r'\b(latte|cappuccino|flat white|mocha|coffee|cocoa|hot chocolate|tea|'
  r'soup|broth|porridge|oatmeal|mashed potato(es)?|potato mash|mash|'
  r'pur[eé]e|pudding|custard|kissel|smoothie|milkshake)$',
  caseSensitive: false,
);

bool _namesReadyFood(String query) =>
    _readyFood.hasMatch(query.split(',').first.trim()) &&
    !_mixWords.hasMatch(query) &&
    !_asksForUncooked.hasMatch(query);

/// [ranked] with the powders and mixes of a ready food moved last: the
/// same rule as the dry pasta's, for the powder sold to make a drink, a
/// soup or a mash. "latte" found a latte powder at 400 kcal per 100 g, so a
/// 300 ml cup read 1200 kcal. A row is a mix by its name or by an energy
/// no made-up drink or soup has; the brand the name gives stands it down.
List<MealEntity> _mixesLast(List<MealEntity> ranked, String query) {
  final named = tokenize(query);
  bool brandNamed(MealEntity meal) {
    final brand = tokenize(meal.brands?.split(',').first);
    return brand.isNotEmpty && brand.every(named.contains);
  }

  bool mix(MealEntity meal) =>
      !brandNamed(meal) &&
      (_mixWords.hasMatch(meal.name ?? '') ||
          (meal.nutriments.energyKcal100 ?? 0) > _mixKcal);

  return [...ranked.where((m) => !mix(m)), ...ranked.where(mix)];
}

/// Whether [query] names a food [eatenCooked], by the last word before its
/// first comma: "penne pasta, cooked" and "rice, white" do; "rice cakes" and
/// "rice flour", a different food, do not.
bool _namesFoodEatenCooked(String query) {
  // the food before a "with": "buckwheat with mushrooms" is buckwheat
  final words = nameWords(
    query.split(',').first.split(_with).first,
  ).where((w) => !describingWords.contains(w) && !_stateWords.contains(w));
  return words.isNotEmpty && eatenCooked.contains(spelling(words.last));
}
