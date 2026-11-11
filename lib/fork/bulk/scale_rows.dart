import 'package:opennutritracker/features/add_meal/domain/usecase/resolve_parsed_meals_usecase.dart';
import 'package:opennutritracker/features/add_meal/presentation/bloc/bulk_add_bloc.dart';

/// Many rows' amounts at once, as the meal's Size sets them
/// (`lib/fork/bulk/meal_scale.dart`): one emit, one rebuild. Handled at
/// seam S212 in `BulkAddBloc`.
///
/// Not upstream's `ChangeRowAmountEvent`, which marks the amount as the
/// user's: a size is the photo's amounts scaled, not a number the user set.
/// The row stays pristine, so a "check the unit" stays asking, and picking
/// another match still re-derives its amount for that food, which the
/// screen then scales again.
class ScaleRowsEvent extends BulkAddEvent {
  /// Amount text by the row's resolved item, found by identity as
  /// `ReplaceRowWithBreakdownEvent` finds its row: a breakdown landing
  /// first moves the indexes.
  final Map<ResolvedMealItem, String> amounts;

  const ScaleRowsEvent(this.amounts);

  @override
  List<Object?> get props => [amounts];
}

/// [state] with each row of [event] at its amount, nothing else changed.
BulkAddLoadedState scaleRows(BulkAddLoadedState state, ScaleRowsEvent event) {
  final rows = [...state.rows];
  var changed = false;
  for (final (i, row) in rows.indexed) {
    final text = _amountFor(event.amounts, row.resolved);
    if (text == null || row.amountText == text) continue;
    rows[i] = row.copyWith(amountText: text);
    changed = true;
  }
  return changed ? state.copyWith(rows: rows) : state;
}

String? _amountFor(
  Map<ResolvedMealItem, String> amounts,
  ResolvedMealItem row,
) {
  for (final MapEntry(:key, :value) in amounts.entries) {
    if (identical(key, row)) return value;
  }
  return null;
}
