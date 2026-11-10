import 'package:opennutritracker/features/add_meal/presentation/bloc/bulk_add_bloc.dart';

/// A row's amount stepped or typed in the unit the review shows it in:
/// ounces for a row held in grams on an imperial profile. Handled at seam
/// S210 in `BulkAddBloc`.
///
/// Not upstream's `ChangeRowUnitEvent`, which marks the unit as the user's
/// choice and so settles "check the amount": a tap on + or a number typed
/// is no answer to that, and in metric units the same edit leaves it
/// asking.
class SetRowInShownUnitEvent extends BulkAddEvent {
  final int rowIndex;
  final String unit;
  final String amountText;

  const SetRowInShownUnitEvent(this.rowIndex, this.unit, this.amountText);

  @override
  List<Object?> get props => [rowIndex, unit, amountText];
}

/// [state] with the row of [event] at its amount in its unit, an amount
/// the user set, the unit no more chosen than it was.
BulkAddLoadedState setRowInShownUnit(
  BulkAddLoadedState state,
  SetRowInShownUnitEvent event,
) {
  final index = event.rowIndex;
  if (index < 0 || index >= state.rows.length) return state;
  final rows = [...state.rows];
  rows[index] = rows[index].copyWith(
    unit: event.unit,
    amountText: event.amountText,
    amountEditedByUser: true,
  );
  return state.copyWith(rows: rows);
}
