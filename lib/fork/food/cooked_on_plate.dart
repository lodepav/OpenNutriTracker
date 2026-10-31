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
/// stay among the candidates, one tap away.
List<MealEntity> dryRowsLast(List<MealEntity> ranked, String query) {
  if (_asksForUncooked.hasMatch(query) || !_namesFoodEatenCooked(query)) {
    return ranked;
  }
  final named = tokenize(query);
  bool dry(MealEntity meal) {
    final food = meal.nutriments;
    return (food.energyKcal100 ?? 0) > _dryKcal &&
        (food.carbohydrates100 ?? 0) > 50 &&
        !tokenize(meal.brands).any(named.contains);
  }

  return [...ranked.where((m) => !dry(m)), ...ranked.where(dry)];
}

/// Whether [query] names a food [eatenCooked], by the last word before its
/// first comma: "penne pasta, cooked" and "rice, white" do; "rice cakes" and
/// "rice flour", a different food, do not.
bool _namesFoodEatenCooked(String query) {
  final words = nameWords(query.split(',').first).where(
    (w) => !describingWords.contains(w) && !_stateWords.contains(w),
  );
  return words.isNotEmpty && eatenCooked.contains(spelling(words.last));
}
