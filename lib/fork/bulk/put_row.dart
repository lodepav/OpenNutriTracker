import 'package:opennutritracker/features/add_meal/domain/usecase/resolve_parsed_meals_usecase.dart';
import 'package:opennutritracker/features/add_meal/presentation/bloc/bulk_add_bloc.dart';

/// One row added to the review, changed, or taken off again, as the cooking
/// fat question's chips do (D48). Handled at seam S215 in `BulkAddBloc`:
/// upstream adds rows only by reading text or a photo anew, and takes none
/// off (a row left out stays, to put back).
class PutRowEvent extends BulkAddEvent {
  /// The row's resolved item, found by identity as `ScaleRowsEvent` finds
  /// its rows.
  final ResolvedMealItem item;

  /// The row as it is to be, its `resolved` [item]; null takes it off.
  final BulkAddRow? row;

  const PutRowEvent(this.item, this.row);

  @override
  List<Object?> get props => [item, row];
}

/// [state] with [event]'s row in place of the one it holds for its item,
/// else added after the others; or without that row when [event] has none.
/// Unchanged when there is nothing to take off.
BulkAddLoadedState putRow(BulkAddLoadedState state, PutRowEvent event) {
  final at = state.rows.indexWhere((r) => identical(r.resolved, event.item));
  final row = event.row;
  if (row == null) {
    if (at < 0) return state;
    return state.copyWith(rows: [...state.rows]..removeAt(at));
  }
  if (!identical(row.resolved, event.item)) return state;
  final rows = [...state.rows];
  if (at < 0) {
    rows.add(row);
  } else {
    rows[at] = row;
  }
  return state.copyWith(rows: rows);
}
