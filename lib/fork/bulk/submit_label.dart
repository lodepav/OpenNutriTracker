import 'package:opennutritracker/features/add_meal/presentation/bloc/bulk_add_bloc.dart';
import 'package:opennutritracker/fork/dish/dish_breakdown_rows.dart';

/// A row held back for a unit check: matched, not left out, and its amount
/// would land meaning something else, so Log leaves it out.
bool heldForUnit(BulkAddRow row) =>
    row.isResolved && !row.skipped && row.amountWouldBeWrong;

/// Whether what Log writes is one dish logged as one, and nothing else.
bool logsAsOneDish(List<BulkAddRow> rows, {Set<Object> separate = const {}}) {
  final logged = rows.where((r) => r.willBeLogged).toList();
  if (logged.isEmpty) return false;
  final group = logged.first.dishIngredient?.group;
  return group != null &&
      !separate.contains(group) &&
      logged.every((r) => identical(r.dishIngredient?.group, group));
}

/// The Log button's words: "Log 2 foods", "Log as 1 dish", or with nothing
/// ready but rows held, what to do first.
String submitLabel({
  required int count,
  required int held,
  bool oneDish = false,
}) {
  if (count == 0 && held > 0) {
    return 'Check $held ${held == 1 ? 'row' : 'rows'} to log';
  }
  if (count == 1 && oneDish) return 'Log as 1 dish';
  return 'Log $count ${count == 1 ? 'food' : 'foods'}';
}

/// "1 waits for a unit" beside a button that logs the rest; null when
/// nothing is held, or nothing logs and the label already says it.
String? heldLabel({required int count, required int held}) {
  if (held == 0 || count == 0) return null;
  return '$held ${held == 1 ? 'waits' : 'wait'} for a unit';
}

/// "Added to Dinner", and the foods Log left out named, at most two by name
/// so the snackbar stays short.
String loggedMessage(String meal, List<String> held) {
  if (held.isEmpty) return 'Added to $meal';
  final names = held.length <= 2
      ? held.join(' and ')
      : '${held.take(2).join(', ')} and ${held.length - 2} more';
  return held.length == 1
      ? 'Added to $meal. $names not logged: check its unit.'
      : 'Added to $meal. $names not logged: check their units.';
}
