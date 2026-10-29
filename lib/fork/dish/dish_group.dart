import 'package:opennutritracker/core/domain/usecase/compute_recipe_nutrition_usecase.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/presentation/bloc/bulk_add_bloc.dart';
import 'package:opennutritracker/features/meal_detail/util/meal_quantity_converter.dart';
import 'package:opennutritracker/fork/dish/dish_breakdown_rows.dart';
import 'package:opennutritracker/fork/dish/dish_recipe.dart';

/// One line of the review list (canvas "AI dish A", D24): a dish's
/// heading, a row (inside a dish or not), or a dish's actions under its
/// last row.
sealed class DishListEntry {
  const DishListEntry();
}

class DishHeading extends DishListEntry {
  final Object group;
  final List<int> members;

  const DishHeading(this.group, this.members);
}

class DishRowEntry extends DishListEntry {
  final int index;
  final bool inDish;

  const DishRowEntry(this.index, {required this.inDish});
}

class DishActions extends DishListEntry {
  final Object group;

  const DishActions(this.group);
}

/// [rows] as the list shows them: each dish's rows under its heading, left
/// out while it is [folded]; a dish in [separate] is logged and shown as
/// plain rows.
List<DishListEntry> dishListEntries(
  List<BulkAddRow> rows, {
  Set<Object> folded = const {},
  Set<Object> separate = const {},
}) {
  final entries = <DishListEntry>[];
  for (var i = 0; i < rows.length; i++) {
    final group = rows[i].dishIngredient?.group;
    if (group == null || separate.contains(group)) {
      entries.add(DishRowEntry(i, inDish: false));
      continue;
    }
    final members = dishMembers(rows, group);
    if (members.first == i) entries.add(DishHeading(group, members));
    if (!folded.contains(group)) entries.add(DishRowEntry(i, inDish: true));
    if (members.last == i) entries.add(DishActions(group));
  }
  return entries;
}

/// The indexes of [group]'s rows.
List<int> dishMembers(List<BulkAddRow> rows, Object group) => [
  for (var i = 0; i < rows.length; i++)
    if (identical(rows[i].dishIngredient?.group, group)) i,
];

/// A row's amount as typed, or null while it is not a number.
double? rowAmount(BulkAddRow row) =>
    double.tryParse(row.amountText.trim().replaceAll(',', '.'));

/// The grams a row will be logged with, or null when it will not be.
double? rowGrams(BulkAddRow row) {
  final amount = rowAmount(row);
  if (!row.willBeLogged || row.quantityError != null || amount == null) {
    return null;
  }
  return convertQuantityToBaseUnit(amount, row.effectiveUnit, row.meal!);
}

/// The grams of the dish's rows that will be logged.
double _rowsGrams(List<BulkAddRow> rows, List<int> members) =>
    members.fold(0, (sum, i) => sum + (rowGrams(rows[i]) ?? 0));

/// Grams as eaten per gram of the rows: a breakdown's rows are raw, and
/// "plov 350g" may come back as 300 g of rice, meat and carrots. One for a
/// weighed plate, whose foods are as served.
double _yield(List<BulkAddRow> rows, List<int> members) {
  final eaten = rows[members.first].dishIngredient?.dishGrams;
  final raw = members.fold<double>(0, (sum, i) {
    final parsed = rows[i].resolved.parsed;
    return sum + (parsed.unit == 'g' ? parsed.quantity ?? 0 : 0);
  });
  return eaten == null || raw <= 0 ? 1 : eaten / raw;
}

/// The dish's portion, in grams as eaten.
double dishPortion(List<BulkAddRow> rows, List<int> members) =>
    _rowsGrams(rows, members) * _yield(rows, members);

/// The dish's energy, of the rows that will be logged.
double dishKcal(List<BulkAddRow> rows, List<int> members) =>
    members.fold(0, (sum, i) {
      final row = rows[i];
      final amount = rowAmount(row);
      if (rowGrams(row) == null || amount == null) return sum;
      return sum + (kcalForQuantity(amount, row.effectiveUnit, row.meal!) ?? 0);
    });

/// Each row's new amount text for a portion of [portion] grams as eaten,
/// from the amounts
/// the rows had when the portion was first changed ([base]), so that the
/// shares between them stay as they were however many keystrokes it took.
/// Null when the base holds no weight to scale.
Map<int, String>? scaledAmounts(
  List<BulkAddRow> rows,
  Map<int, double> base,
  double portion,
) {
  if (base.isEmpty) return null;
  final group = rows[base.keys.first].dishIngredient!.group;
  final grams = portion / _yield(rows, dishMembers(rows, group));
  final baseGrams = base.entries.fold<double>(0, (sum, e) {
    final row = rows[e.key];
    return sum +
        convertQuantityToBaseUnit(e.value, row.effectiveUnit, row.meal!);
  });
  if (baseGrams <= 0) return null;
  final factor = grams / baseGrams;
  return {
    for (final MapEntry(:key, :value) in base.entries)
      key: _amountText(value * factor, rows[key].effectiveUnit),
  };
}

/// The amounts of [members] a portion change scales: the rows that will be
/// logged.
Map<int, double> portionBase(List<BulkAddRow> rows, List<int> members) => {
  for (final i in members)
    if (rowGrams(rows[i]) != null) i: rowAmount(rows[i])!,
};

String _amountText(double amount, String unit) {
  // whole grams and millilitres; a tenth of anything larger
  final rounded = unit == 'g' || unit == 'ml'
      ? amount.roundToDouble()
      : (amount * 10).roundToDouble() / 10;
  return rounded == rounded.roundToDouble()
      ? rounded.toInt().toString()
      : rounded.toString();
}

/// The dish as one food to log: its rows as they stand, combined the way a
/// recipe is. Null when no row is ready.
MealEntity? dishMeal(List<BulkAddRow> rows, Object group) {
  final recipe = recipeFromDishGroup(rows, group);
  if (recipe == null) return null;
  final members = dishMembers(rows, group);
  final nutrition = ComputeRecipeNutritionUseCase().compute(
    recipe.ingredients,
    // a breakdown's raw ingredients weigh what the dish weighed as eaten
    totalWeightOverride: _yield(rows, members) == 1
        ? null
        : dishPortion(rows, members),
  );
  return recipe
      .copyWith(
        totalWeightG: nutrition.totalWeightG,
        aggregatedNutrimentsPer100: nutrition.perHundredG,
      )
      .toMealEntity();
}

/// How many diary entries [rows] log: a dish not in [separate] is one.
int loggedEntries(List<BulkAddRow> rows, {Set<Object> separate = const {}}) {
  final dishes = <Object>{};
  var count = 0;
  for (final row in rows) {
    if (!row.willBeLogged) continue;
    final group = row.dishIngredient?.group;
    if (group == null || separate.contains(group)) {
      count++;
    } else if (dishes.add(group)) {
      count++;
    }
  }
  return count;
}
