import 'package:opennutritracker/features/add_meal/domain/usecase/resolve_parsed_meals_usecase.dart';
import 'package:opennutritracker/features/add_meal/presentation/bloc/bulk_add_bloc.dart';
import 'package:opennutritracker/features/add_meal/util/portion_unit.dart';
import 'package:opennutritracker/features/add_meal/util/meal_text_parser.dart';
import 'package:opennutritracker/fork/dish/break_down_dish_usecase.dart';

/// An ingredient row the model wrote for [dish] (D12). A subtype of
/// upstream's parsed item so the row keeps it through every edit: a
/// [BulkAddRow] never replaces its `resolved`, and that holds this.
class DishIngredientItem extends ParsedMealItem {
  final String dish;

  /// The same object on every ingredient of one breakdown, so two
  /// breakdowns of the same dish stay two groups.
  final Object group;

  /// The servings the breakdown was asked for: a stated count of the dish
  /// ("3 sklandrauši"), else one. Its recipe is saved with as many.
  final int servings;

  /// The dish's weight as eaten, when the user stated it in grams: a
  /// weighed plate's total (S175), or the amount a breakdown was asked for.
  /// The ingredients add up to it on a weighed plate; a breakdown's are
  /// raw, so theirs may not.
  final double? dishGrams;

  const DishIngredientItem({
    required super.query,
    super.quantity,
    super.unit,
    required this.dish,
    required this.group,
    this.servings = 1,
    this.dishGrams,
  });
}

/// The amount [row] states for its dish, as the breakdown is asked for it:
/// "500 ml", "200 g", or a bare count "3". Null when nobody stated one, so
/// the breakdown is one serving (or the portion in the photo), not the
/// app's 100 g default.
String? statedAmount(BulkAddRow row) {
  final parsed = row.resolved.parsed;
  if (parsed.quantity == null && !row.amountEditedByUser) return null;
  final text = row.amountText.trim().replaceAll(',', '.');
  final quantity = double.tryParse(text);
  if (quantity == null || quantity <= 0) return null;
  // Typed over the 100 g default, the number is in the unit shown; over a
  // stated count, still a count unless the user picked a unit.
  final unit = row.unitChosenByUser || parsed.quantity == null
      ? row.unit
      : parsed.unit;
  if (unit == null) return text;
  if (isPortionUnit(unit)) return '$text servings';
  if (unit == 'g/ml') return '$text g';
  return '$text $unit';
}

/// The whole count [statedAmount] states, a bare count or "N servings",
/// or null for an amount in other units.
int? statedCount(BulkAddRow row) {
  final amount = statedAmount(row);
  final count = amount == null
      ? null
      : double.tryParse(amount.replaceFirst(RegExp(r' servings$'), ''));
  return count != null && count == count.roundToDouble() ? count.toInt() : null;
}

extension DishIngredientRow on BulkAddRow {
  /// Set on rows a breakdown produced.
  DishIngredientItem? get dishIngredient => switch (resolved.parsed) {
    final DishIngredientItem item => item,
    _ => null,
  };
}

/// Swaps one review row for the ingredient rows of its [breakdown].
///
/// Dispatched by `DishBreakdownController` and handled at seam S3 in
/// `BulkAddBloc`.
class ReplaceRowWithBreakdownEvent extends BulkAddEvent {
  /// The row's resolved item, found by identity: rows above it may have
  /// been swapped since the breakdown started, which moves its index.
  final ResolvedMealItem row;
  final DishBreakdown breakdown;

  const ReplaceRowWithBreakdownEvent(this.row, this.breakdown);

  @override
  List<Object?> get props => [row, breakdown];
}

/// The rows after [event]: the target row replaced by one row per
/// ingredient, each at the model's grams. Unchanged when the row is gone
/// (a new search replaced the batch) or the breakdown is empty.
BulkAddLoadedState replaceRowWithBreakdown(
  BulkAddLoadedState state,
  ReplaceRowWithBreakdownEvent event,
) {
  final index = state.rows.indexWhere((r) => identical(r.resolved, event.row));
  // A row skipped while its breakdown ran stays skipped, as one row.
  if (index < 0 ||
      state.rows[index].skipped ||
      event.breakdown.ingredients.isEmpty) {
    return state;
  }

  final group = Object();
  final servings = statedCount(state.rows[index]) ?? 1;
  final stated = statedAmount(state.rows[index]);
  final dishGrams = stated != null && stated.endsWith(' g')
      ? double.tryParse(stated.substring(0, stated.length - 2))
      : null;
  final ingredients = [
    for (final item in event.breakdown.ingredients)
      _row(
        ResolvedMealItem(
          parsed: DishIngredientItem(
            query: item.parsed.query,
            quantity: item.parsed.quantity,
            unit: item.parsed.unit,
            dish: event.breakdown.dish,
            group: group,
            servings: servings,
            dishGrams: dishGrams,
          ),
          candidates: item.candidates,
          selectedIndex: item.selectedIndex,
          confidence: item.confidence,
        ),
        fromPhoto: state.rows[index].fromPhoto,
      ),
  ];
  return state.copyWith(
    rows: [...state.rows]..replaceRange(index, index + 1, ingredients),
  );
}

/// A row at the model's amount. Every ingredient is asked for in grams
/// (millilitres for a liquid), so there is no portion or serving to derive
/// the way upstream's `_initialUnit` does; a missing amount falls to 100 g,
/// which the row marks as the app's default.
BulkAddRow _row(ResolvedMealItem item, {required bool fromPhoto}) {
  final quantity = item.parsed.quantity;
  return BulkAddRow(
    resolved: item,
    selectedIndex: item.selectedIndex,
    amountText: quantity == null ? '100' : _amountText(quantity),
    unit: item.parsed.unit ?? 'g',
    fromPhoto: fromPhoto,
  );
}

/// Whole grams as an integer, else two decimals: the shape
/// [bulkAddQuantityPattern] accepts.
String _amountText(double value) {
  final rounded = double.parse(value.toStringAsFixed(2));
  return rounded == rounded.roundToDouble()
      ? rounded.toInt().toString()
      : rounded.toString();
}
