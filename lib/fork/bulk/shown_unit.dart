import 'package:opennutritracker/features/add_meal/presentation/bloc/bulk_add_bloc.dart';
import 'package:opennutritracker/features/add_meal/util/recipe_count.dart';

/// A row's amount stepped or typed in the unit the review shows it in:
/// ounces for a row held in grams on an imperial profile. Handled at seam
/// S210 in `BulkAddBloc`.
///
/// Not upstream's `ChangeRowUnitEvent`, which marks the unit as the user's
/// choice. A row held for "check the unit" is answered by any amount set by
/// hand ([answeredByHand]); the review sends a held row's edits here, in
/// grams as in ounces.
class SetRowInShownUnitEvent extends BulkAddEvent {
  final int rowIndex;
  final String unit;
  final String amountText;

  const SetRowInShownUnitEvent(this.rowIndex, this.unit, this.amountText);

  @override
  List<Object?> get props => [rowIndex, unit, amountText];
}

/// [state] with the row of [event] at its amount in its unit, an amount
/// the user set.
BulkAddLoadedState setRowInShownUnit(
  BulkAddLoadedState state,
  SetRowInShownUnitEvent event,
) {
  final index = event.rowIndex;
  if (index < 0 || index >= state.rows.length) return state;
  final rows = [...state.rows];
  rows[index] = answeredByHand(
    rows[index].copyWith(
      unit: event.unit,
      amountText: event.amountText,
      amountEditedByUser: true,
    ),
  );
  return state.copyWith(rows: rows);
}

/// [row], just set by hand, no longer held for "check the unit": the user
/// looked at the amount and set it, which is the answer the hold asks for.
/// A recipe's count stays checked on the number set, or one tap on − would
/// log 13 servings of a batch of 6.
BulkAddRow answeredByHand(BulkAddRow row) {
  if (!row.amountWouldBeWrong) return row;
  final count =
      double.tryParse(row.amountText.trim().replaceAll(',', '.')) ??
      row.resolved.parsed.quantity!;
  if (row.resolved.parsed.unit == null && countExceedsRecipe(row.meal, count)) {
    return row;
  }
  return row.copyWith(unitChosenByUser: true);
}
