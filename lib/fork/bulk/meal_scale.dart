import 'dart:collection';
import 'dart:math' as math;

import 'package:opennutritracker/features/add_meal/domain/usecase/resolve_parsed_meals_usecase.dart';
import 'package:opennutritracker/features/add_meal/presentation/bloc/bulk_add_bloc.dart';
import 'package:opennutritracker/features/add_meal/util/portion_unit.dart';
import 'package:opennutritracker/fork/bulk/note_counts.dart';
import 'package:opennutritracker/fork/bulk/note_weights.dart';

/// The whole-meal sizes a photo's review offers: the model sizes portions
/// 20-60% off, and one right scale per plate halves that.
const mealSizeFactors = [0.6, 0.8, 1.0, 1.2, 1.4];

/// [base] in [unit] times [factor], as the amount field holds it: whole
/// grams and millilitres, ounces to a tenth, a count to the nearest half
/// and never below a half; a pinch stays a pinch, since a 0 would refuse the
/// whole batch.
String scaledAmountText(double base, String unit, double factor) {
  final amount = base * factor;
  var rounded = isPortionUnit(unit)
      ? math.max(0.5, (amount * 2).roundToDouble() / 2)
      : unit == 'oz' || unit == 'fl.oz'
      ? (amount * 10).roundToDouble() / 10
      : amount.roundToDouble();
  if (rounded <= 0 && amount > 0) {
    rounded = double.parse(amount.toStringAsFixed(2));
    if (rounded <= 0) rounded = 0.01;
  }
  return rounded == rounded.roundToDouble()
      ? rounded.toInt().toString()
      : double.parse(rounded.toStringAsFixed(2)).toString();
}

/// Whether the meal's Size may change [row] at all (R2), [note] being what
/// the photo was sent with: not a weighed plate's (the note states weights,
/// D24), nor a count the note states (S170), nor a row left out, without a
/// match, held back as an amount that would be wrong, at the app's default
/// amount, or with an amount that is not one.
bool isScalableRow(BulkAddRow row, {String? note}) {
  if (row.skipped || !row.isResolved) return false;
  if (row.amountWouldBeWrong || row.amountIsProvisional) return false;
  if (row.quantityError != null) return false;
  if (noteWeights(note) != null) return false;
  final parsed = row.resolved.parsed;
  final counted = parsed.unit == null || isPortionUnit(parsed.unit!);
  return !(counted && noteStatesCount(note, parsed.quantity));
}

/// The amount a row had when the photo's read arrived, which every size
/// scales from, so that no size compounds on another.
typedef _Base = ({double amount, String text});

/// The amount the screen last gave a row (or found on it), so that one the
/// user changed can be told from it. [prior] is what it had before, while
/// the change is on its way to the bloc; [factor] the size it was scaled to.
typedef _Given = ({
  String text,
  String? prior,
  String unit,
  int selected,
  double factor,
});

/// The meal's Size on a photo's review: the size chosen, each row's base,
/// and the rows the user set (R1), which a size no longer changes. Rows are
/// held by their resolved item, which a row keeps through every edit, so a
/// breakdown moving them keeps all of it.
class MealScale {
  /// The note the photo was sent with.
  final String? note;

  MealScale({this.note});

  /// The size chosen: 1 is "As shown".
  double factor = 1;

  bool _started = false;
  final _base = LinkedHashMap<ResolvedMealItem, _Base>.identity();
  final _given = LinkedHashMap<ResolvedMealItem, _Given>.identity();
  final _pinned = Set<ResolvedMealItem>.identity();
  List<ResolvedMealItem> _seen = const [];

  bool isPinned(BulkAddRow row) => _pinned.contains(row.resolved);

  /// The user set [row]'s amount: it is what they ate, and stays so.
  void pin(BulkAddRow row) => _pinned.add(row.resolved);

  /// [row]'s amount, [amountText] or the one it has, is the one sizes scale
  /// from, and the row is no longer pinned. [shownAt] is the size that
  /// amount is already at, so its base is the amount divided by it.
  void setBase(BulkAddRow row, {String? amountText, double shownAt = 1}) {
    final text = amountText ?? row.amountText;
    final amount = double.tryParse(text.trim().replaceAll(',', '.'));
    _pinned.remove(row.resolved);
    if (amount != null && amount > 0) {
      _base[row.resolved] = (
        amount: amount / shownAt,
        text: shownAt == 1
            ? text
            : scaledAmountText(amount, row.effectiveUnit, 1 / shownAt),
      );
    } else {
      _base.remove(row.resolved);
    }
    _given[row.resolved] = (
      text: text,
      prior: null,
      unit: row.unit,
      selected: row.selectedIndex,
      factor: shownAt,
    );
  }

  /// Whether the Size is offered on [row]: it may be scaled, or would be
  /// had the user not set it.
  bool isEligible(BulkAddRow row) =>
      isScalableRow(row, note: note) &&
      (isPinned(row) || _base.containsKey(row.resolved));

  /// Whether the Size changes [row] now.
  bool canScale(BulkAddRow row) => isEligible(row) && !isPinned(row);

  /// Whether the Size is offered at all: some row is eligible.
  bool offered(List<BulkAddRow> rows) => rows.any(isEligible);

  /// Whether every eligible row is set by the user, so no size changes any.
  bool allSet(List<BulkAddRow> rows) => offered(rows) && !rows.any(canScale);

  /// [row]'s amount text at the size chosen; null when it has no base.
  String? targetText(BulkAddRow row) {
    final base = _base[row.resolved];
    if (base == null) return null;
    if (factor == 1) return base.text;
    final given = _given[row.resolved];
    if (given != null && given.factor == factor) return given.text;
    return scaledAmountText(base.amount, row.effectiveUnit, factor);
  }

  /// The amounts that put each row the size changes at the size chosen, by
  /// the row's resolved item (`ScaleRowsEvent`): those not there already.
  /// Recorded as given, so the state they arrive in is not taken for the
  /// user's edit.
  Map<ResolvedMealItem, String> retarget(List<BulkAddRow> rows) {
    final amounts = LinkedHashMap<ResolvedMealItem, String>.identity();
    for (final row in rows) {
      if (!canScale(row)) continue;
      final target = targetText(row);
      if (target == null) continue;
      final given = _given[row.resolved];
      _given[row.resolved] = (
        text: target,
        // still on its way when unchanged
        prior: given?.text == target ? given?.prior : given?.text,
        unit: row.unit,
        selected: row.selectedIndex,
        factor: factor,
      );
      if (row.amountText != target) amounts[row.resolved] = target;
    }
    return amounts;
  }

  /// Follows the review's [rows] after any change, and returns the amounts
  /// still to set ([retarget]). The first rows of a read are the base. An
  /// amount, unit or match the screen did not give is the user's: pinned,
  /// except a match picked on a row with no amount of the user's, which the
  /// bloc re-derived for that food and so becomes its base. Rows a breakdown
  /// wrote take their base from the amount they were weighed for, the
  /// parent's amount at its size (`breakdownAmount` keeps it), so divided by
  /// that size, and are not pinned; under a parent the user set, they are
  /// set too.
  Map<ResolvedMealItem, String> follow(List<BulkAddRow> rows) {
    if (!_started) {
      _started = true;
      for (final row in rows) {
        setBase(row);
      }
      _seen = [for (final row in rows) row.resolved];
      return const {};
    }

    final now = [for (final row in rows) row.resolved];
    final known = Set<ResolvedMealItem>.identity()..addAll(_seen);
    final present = Set<ResolvedMealItem>.identity()..addAll(now);
    final lost = [
      for (final item in _seen)
        if (!present.contains(item)) item,
    ];
    final parent = lost.length == 1 ? lost.single : null;
    for (final row in rows) {
      if (known.contains(row.resolved)) continue;
      if (parent != null && _pinned.contains(parent)) {
        pin(row);
        continue;
      }
      setBase(row, shownAt: parent == null ? 1 : _given[parent]?.factor ?? 1);
    }
    for (final item in lost) {
      _base.remove(item);
      _given.remove(item);
      _pinned.remove(item);
    }

    for (final row in rows) {
      if (isPinned(row)) continue;
      final given = _given[row.resolved];
      if (given == null) continue;
      if (row.selectedIndex != given.selected) {
        if (row.isPristine) {
          setBase(row);
        } else {
          pin(row);
        }
      } else if (row.unit != given.unit ||
          (row.amountText != given.text && row.amountText != given.prior)) {
        pin(row);
      } else if (row.amountText == given.text && given.prior != null) {
        // arrived
        _given[row.resolved] = (
          text: given.text,
          prior: null,
          unit: given.unit,
          selected: given.selected,
          factor: given.factor,
        );
      }
    }
    _seen = now;
    return retarget(rows);
  }
}
