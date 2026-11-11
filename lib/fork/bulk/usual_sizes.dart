// How this user usually corrects a photo's amounts, learnt from the photo
// meals they logged (D46): foods they keep logging smaller or larger than
// the photo shows. Pure code; the memory it reads stays on the device.
import 'dart:collection';
import 'dart:math' as math;

import 'package:opennutritracker/features/add_meal/domain/usecase/resolve_parsed_meals_usecase.dart';
import 'package:opennutritracker/features/add_meal/presentation/bloc/bulk_add_bloc.dart';
import 'package:opennutritracker/fork/bulk/meal_scale.dart';
import 'package:opennutritracker/fork/bulk/note_weights.dart';
import 'package:opennutritracker/fork/bulk/photo_meal_memory.dart';

/// How many recent records holding a food its own size is learnt from.
const usualFoodRecords = 5;

/// How many corrections it takes, all one way, before anything is applied.
const usualMinimum = 3;

/// A correction under 10% is no correction, and a size within 10% of 1 is
/// not worth applying.
const _off = 0.1;

/// Below 0.5 or above 2 a learnt size is more likely a meal that differed
/// than a habit, so it is held there.
const _least = 0.5;
const _most = 2.0;

/// The sizes learnt, one per food key, only those that act. No whole-meal
/// size: one learnt from three meals shrank every later meal whatever the
/// dish, where the read was as often short as over.
class UsualSizes {
  final Map<String, double> foods;

  const UsualSizes({this.foods = const {}});

  static const none = UsualSizes();

  bool get isEmpty => foods.isEmpty;

  /// The factor a food of [key] takes; 1 for a food with none.
  double factorFor(String key) => foods[key] ?? 1;
}

/// -1, 0 or 1: whether [value] is 10% or more under 1, within it, or over.
int _direction(double value) {
  // a hair of slack, so a chip's 0.9 or 1.1 counts as off
  if (value >= 1 + _off - 1e-9) return 1;
  if (value <= 1 - _off + 1e-9) return -1;
  return 0;
}

double _median(List<double> values) {
  final sorted = [...values]..sort();
  final mid = sorted.length ~/ 2;
  return sorted.length.isOdd
      ? sorted[mid]
      : (sorted[mid - 1] + sorted[mid]) / 2;
}

/// The median of [values] held to 0.5-2, or null within 10% of 1.
double? _learnt(List<double> values) {
  final value = _median(values).clamp(_least, _most).toDouble();
  return _direction(value) == 0 ? null : value;
}

/// [records] newest first.
List<PhotoMealRecord> _newestFirst(Iterable<PhotoMealRecord> records) =>
    [...records]..sort((a, b) {
      final byDay = b.day.compareTo(a.day);
      return byDay != 0 ? byDay : b.loggedAt.compareTo(a.loggedAt);
    });

/// The usual sizes [records] show at [now]. A record's `size` is not read:
/// a Size chosen on meals holding a food is evidence about that food, and
/// counts in its logged amount. Records kept before photo amounts were
/// give no food a size.
UsualSizes usualSizesOf(
  Iterable<PhotoMealRecord> records, {
  required DateTime now,
}) => UsualSizes(
  foods: _usualFoods(
    _newestFirst(records.where((record) => !record.expiredAt(now))),
  ),
);

/// Each food's size: what was logged against the photo's amount, at least
/// 3 of its last 5 off one way and none the other.
Map<String, double> _usualFoods(List<PhotoMealRecord> recent) {
  final residuals = <String, List<double>>{};
  for (final record in recent) {
    final logged = <String, double>{};
    final photo = <String, double>{};
    for (final food in record.foods) {
      final shown = food.photoAmount;
      if (shown == null || shown <= 0) continue;
      logged[food.key] = (logged[food.key] ?? 0) + food.amount;
      photo[food.key] = (photo[food.key] ?? 0) + shown;
    }
    for (final MapEntry(:key, value: shown) in photo.entries) {
      final list = residuals[key] ??= [];
      if (list.length >= usualFoodRecords) continue;
      list.add(logged[key]! / shown);
    }
  }
  final foods = <String, double>{};
  for (final MapEntry(:key, value: values) in residuals.entries) {
    var up = 0, down = 0;
    for (final value in values) {
      switch (_direction(value)) {
        case 1:
          up++;
        case -1:
          down++;
      }
    }
    if (up > 0 && down > 0) continue;
    if (math.max(up, down) < usualMinimum) continue;
    if (_learnt(values) case final value?) foods[key] = value;
  }
  return foods;
}

/// The usual amount text of each of [rows] [sizes] change, by resolved
/// item: its amount times its food's size, rounded as the
/// Size rounds. Only rows [canTake] allows (the screen: the Size may change
/// it and the user has not set it), never on a weighed plate's read, and
/// none whose amount would not change.
Map<ResolvedMealItem, String> usualAmounts(
  List<BulkAddRow> rows,
  UsualSizes sizes, {
  String? note,
  required bool Function(BulkAddRow row) canTake,
}) {
  final amounts = LinkedHashMap<ResolvedMealItem, String>.identity();
  if (sizes.isEmpty || noteWeights(note) != null) return amounts;
  for (final row in rows) {
    final meal = row.meal;
    if (meal == null || !isScalableRow(row, note: note) || !canTake(row)) {
      continue;
    }
    final factor = sizes.factorFor(foodKeyOf(meal));
    if (factor == 1) continue;
    final amount = double.tryParse(row.amountText.trim().replaceAll(',', '.'));
    if (amount == null || amount <= 0) continue;
    final text = scaledAmountText(amount, row.effectiveUnit, factor);
    if (text != row.amountText) amounts[row.resolved] = text;
  }
  return amounts;
}
