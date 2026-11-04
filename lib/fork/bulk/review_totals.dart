import 'package:opennutritracker/features/add_meal/presentation/bloc/bulk_add_bloc.dart';
import 'package:opennutritracker/features/meal_detail/util/meal_quantity_converter.dart';
import 'package:opennutritracker/fork/dish/dish_group.dart';

/// Energy in kcal and the three macros in grams.
typedef ReviewMacros = ({
  double kcal,
  double protein,
  double carbs,
  double fat,
});

/// Whether Log with AI's review should ask the user to look at [row]
/// (D36): no match, a doubtful one, or a count the app could not read. An
/// amount the app chose is said quietly, as nearly every photo row has one.
bool rowNeedsLook(BulkAddRow row) =>
    !row.isResolved || row.isLowConfidence || row.amountNeedsCheck;

/// [row]'s energy and macros at its amount; null without a match or a
/// usable amount.
ReviewMacros? rowMacros(BulkAddRow row) {
  final meal = row.meal;
  if (meal == null) return null;
  final quantity = double.tryParse(row.amountText.replaceAll(',', '.'));
  if (quantity == null || quantity <= 0) return null;
  final base = convertQuantityToBaseUnit(quantity, row.effectiveUnit, meal);
  final n = meal.nutriments;
  return (
    kcal: base * (n.energyPerUnit ?? 0),
    protein: base * (n.proteinsPerUnit ?? 0),
    carbs: base * (n.carbohydratesPerUnit ?? 0),
    fat: base * (n.fatPerUnit ?? 0),
  );
}

/// What the Log button will log, summed: the rows that will be logged.
ReviewMacros mealMacros(Iterable<BulkAddRow> rows) {
  var (kcal, protein, carbs, fat) = (0.0, 0.0, 0.0, 0.0);
  for (final row in rows) {
    if (!row.willBeLogged) continue;
    final m = rowMacros(row);
    if (m == null) continue;
    kcal += m.kcal;
    protein += m.protein;
    carbs += m.carbs;
    fat += m.fat;
  }
  return (kcal: kcal, protein: protein, carbs: carbs, fat: fat);
}

/// [entries] with the foods that need a look first (D36), in their order;
/// a dish keeps its heading and its foods together where it stood.
List<DishListEntry> needsLookFirst(
  List<DishListEntry> entries,
  List<BulkAddRow> rows,
) {
  bool first(DishListEntry e) =>
      e is DishRowEntry && !e.inDish && rowNeedsLook(rows[e.index]);
  return [...entries.where(first), ...entries.where((e) => !first(e))];
}
