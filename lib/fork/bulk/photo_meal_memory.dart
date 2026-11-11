// A photo meal memory: what the user logged from a photo's review, and
// whether they corrected its amounts. A photo read names foods well and
// sizes them badly; a person eats the same meals again, and their own
// earlier correction is the best estimate there is. On the device only.
import 'dart:collection';
import 'dart:math' as math;

import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/usecase/resolve_parsed_meals_usecase.dart';
import 'package:opennutritracker/features/add_meal/presentation/bloc/bulk_add_bloc.dart';
import 'package:opennutritracker/features/add_meal/util/portion_unit.dart';
import 'package:opennutritracker/features/meal_detail/util/meal_quantity_converter.dart';
import 'package:opennutritracker/fork/bulk/meal_scale.dart';
import 'package:opennutritracker/fork/bulk/note_counts.dart';
import 'package:opennutritracker/fork/bulk/note_weights.dart';
import 'package:opennutritracker/fork/bulk/review_totals.dart';
import 'package:opennutritracker/fork/dish/dish_breakdown_rows.dart';

/// How long a record is kept, and offered.
const photoMealMemoryDays = 120;

/// One food of a logged photo meal.
class PhotoMealFood {
  /// [foodKeyOf] the food matched.
  final String key;
  final String name;

  /// In the food's base unit, grams or millilitres.
  final double amount;
  final double kcal;

  /// The photo's own amount for it as first read, in the same unit; null
  /// for a food the user added, or one whose match or unit they changed,
  /// and in records kept before it was (D46).
  final double? photoAmount;

  const PhotoMealFood({
    required this.key,
    required this.name,
    required this.amount,
    required this.kcal,
    this.photoAmount,
  });

  Map<String, Object> toJson() => {
    'key': key,
    'name': name,
    'amount': amount,
    'kcal': kcal,
    'photoAmount': ?photoAmount,
  };

  static PhotoMealFood fromJson(Map<dynamic, dynamic> json) => PhotoMealFood(
    key: json['key'] as String,
    name: json['name'] as String? ?? '',
    amount: (json['amount'] as num).toDouble(),
    kcal: (json['kcal'] as num?)?.toDouble() ?? 0,
    photoAmount: (json['photoAmount'] as num?)?.toDouble(),
  );
}

/// One photo meal as it was logged.
class PhotoMealRecord {
  /// The diary day it went to, a date.
  final DateTime day;

  /// When it was logged, which orders two records of one day.
  final DateTime loggedAt;

  /// The meal slot, as `IntakeTypeEntity` names it: breakfast, lunch,
  /// dinner or snack.
  final String slot;

  /// The dish the read arrived as, if it arrived as one.
  final String? dish;
  final List<PhotoMealFood> foods;
  final double kcal;

  /// Whether the user changed any amount on that review.
  final bool corrected;

  /// The whole-meal size in force at Log against the photo's amounts: the
  /// Size chosen, times the usual whole-meal size when that was in force
  /// (D46). Null when no amount could be sized, and in older records.
  final double? size;

  const PhotoMealRecord({
    required this.day,
    required this.loggedAt,
    required this.slot,
    this.dish,
    required this.foods,
    required this.kcal,
    required this.corrected,
    this.size,
  });

  Map<String, Object> toJson() => {
    'day': _date(day),
    'loggedAt': loggedAt.toIso8601String(),
    'slot': slot,
    'dish': ?dish,
    'foods': [for (final food in foods) food.toJson()],
    'kcal': kcal,
    'corrected': corrected,
    'size': ?size,
  };

  static PhotoMealRecord fromJson(Map<dynamic, dynamic> json) =>
      PhotoMealRecord(
        day: DateTime.parse(json['day'] as String),
        loggedAt: DateTime.parse(json['loggedAt'] as String),
        slot: json['slot'] as String,
        dish: json['dish'] as String?,
        foods: [
          for (final food in json['foods'] as List)
            PhotoMealFood.fromJson(food as Map),
        ],
        kcal: (json['kcal'] as num).toDouble(),
        corrected: json['corrected'] as bool,
        size: (json['size'] as num?)?.toDouble(),
      );

  /// Whether [now] is past the days it is kept.
  bool expiredAt(DateTime now) => day.isBefore(memoryCutoff(now));

  Set<String> get keys => {for (final food in foods) food.key};
}

String _date(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-'
    '${day.month.toString().padLeft(2, '0')}-'
    '${day.day.toString().padLeft(2, '0')}';

/// The first day still kept at [now].
DateTime memoryCutoff(DateTime now) =>
    DateTime(now.year, now.month, now.day - photoMealMemoryDays);

/// A food as the memory knows it: its id or code, else its name made plain.
String foodKeyOf(MealEntity meal) {
  final code = meal.code?.trim();
  if (code != null && code.isNotEmpty) return code;
  final name = (meal.name ?? '').trim().toLowerCase().replaceAll(
    RegExp(r'\s+'),
    ' ',
  );
  return 'name:$name';
}

/// The name a dish is matched by: trimmed, any case.
String? _dishKey(String? dish) {
  final key = dish?.trim().toLowerCase();
  return key == null || key.isEmpty ? null : key;
}

/// The dish [rows] arrived as: the one dish their foods are under, when
/// there is exactly one.
String? readDishName(List<BulkAddRow> rows) {
  final names = <String>{};
  Object? group;
  for (final row in rows) {
    final item = row.dishIngredient;
    if (item == null) continue;
    if (group != null && !identical(group, item.group)) return null;
    group = item.group;
    names.add(item.dish);
  }
  return names.length == 1 ? names.single : null;
}

/// [row]'s grams or millilitres, or null when it has none to log.
double? baseAmountOf(BulkAddRow row) {
  final meal = row.meal;
  if (meal == null) return null;
  final amount = double.tryParse(row.amountText.trim().replaceAll(',', '.'));
  if (amount == null || amount <= 0) return null;
  return convertQuantityToBaseUnit(amount, row.effectiveUnit, meal);
}

/// The record of [rows] logged: each food that will be logged, at its
/// amount, with the photo's own amount [photoAmountOf] gives it, and the
/// meal's [size]. Null when none will be.
PhotoMealRecord? photoMealRecordOf(
  List<BulkAddRow> rows, {
  required DateTime day,
  required DateTime loggedAt,
  required String slot,
  String? dish,
  required bool corrected,
  double? Function(BulkAddRow row)? photoAmountOf,
  double? size,
}) {
  final foods = <PhotoMealFood>[
    for (final row in rows)
      if (row.willBeLogged && row.quantityError == null)
        if (baseAmountOf(row) case final amount?)
          PhotoMealFood(
            key: foodKeyOf(row.meal!),
            name: row.meal!.name ?? row.resolved.parsed.query,
            amount: amount,
            kcal: rowMacros(row)?.kcal ?? 0,
            photoAmount: photoAmountOf?.call(row),
          ),
  ];
  if (foods.isEmpty) return null;
  return PhotoMealRecord(
    day: DateTime(day.year, day.month, day.day),
    loggedAt: loggedAt,
    slot: slot,
    dish: dish,
    foods: foods,
    kcal: foods.fold(0.0, (sum, food) => sum + food.kcal),
    corrected: corrected,
    size: size,
  );
}

/// How a record matched a read.
enum PhotoMealMatchKind {
  /// Two foods or more, most of them shared.
  foods,

  /// The same dish name, half the foods shared.
  dish,
}

/// The record [keys] (a read's foods) and [dish] match among [records], the
/// most recent: a corrected one of the last [photoMealMemoryDays] that
/// shares 2 foods or more, with a Jaccard overlap of 0.6 or more, or has
/// the same dish name with an overlap of 0.5 or more (a one-food dish
/// matches on its name and that food).
({PhotoMealRecord record, PhotoMealMatchKind kind})? matchingRecord(
  Iterable<PhotoMealRecord> records, {
  required Set<String> keys,
  String? dish,
  required DateTime now,
}) {
  final dishKey = _dishKey(dish);
  ({PhotoMealRecord record, PhotoMealMatchKind kind})? best;
  for (final record in records) {
    if (!record.corrected || record.expiredAt(now)) continue;
    final theirs = record.keys;
    final shared = theirs.intersection(keys).length;
    final union = theirs.union(keys).length;
    if (union == 0) continue;
    final overlap = shared / union;
    final PhotoMealMatchKind kind;
    if (shared >= 2 && overlap >= 0.6) {
      kind = PhotoMealMatchKind.foods;
    } else if (dishKey != null &&
        _dishKey(record.dish) == dishKey &&
        overlap >= 0.5) {
      kind = PhotoMealMatchKind.dish;
    } else {
      continue;
    }
    if (best == null || _later(record, best.record)) {
      best = (record: record, kind: kind);
    }
  }
  return best;
}

bool _later(PhotoMealRecord a, PhotoMealRecord b) {
  final byDay = a.day.compareTo(b.day);
  return byDay != 0 ? byDay > 0 : a.loggedAt.isAfter(b.loggedAt);
}

/// A record offered on a photo's review.
class PhotoMealMatch {
  final PhotoMealRecord record;
  final PhotoMealMatchKind kind;

  /// How many of the read's foods it shared when the read arrived.
  final int sharedAtArrival;

  const PhotoMealMatch(this.record, this.kind, this.sharedAtArrival);

  /// The shared foods it needs to stand: 2, or a one-food dish's one.
  int get sharedNeeded =>
      kind == PhotoMealMatchKind.dish ? math.min(2, sharedAtArrival) : 2;
}

/// Whether [row] is one of a read's foods, as matching counts them.
bool _counts(BulkAddRow row) => !row.skipped && row.isResolved;

/// The record to offer for a photo's [rows] as they arrive, read with
/// [note]; null when none matches, or the offer would not help: a weighed
/// plate's read, a note stating every count, no shared food the meal's Size
/// may scale, or the shared foods' energy then within 10% of the read's.
PhotoMealMatch? photoMealMatchFor(
  List<BulkAddRow> rows,
  Iterable<PhotoMealRecord> records, {
  String? note,
  required DateTime now,
}) {
  if (noteWeights(note) != null) return null;
  final counted = [
    for (final row in rows)
      if (_counts(row) &&
          (row.resolved.parsed.unit == null ||
              isPortionUnit(row.resolved.parsed.unit!)))
        row,
  ];
  if (counted.isNotEmpty &&
      counted.every(
        (row) => noteStatesCount(note, row.resolved.parsed.quantity),
      )) {
    return null;
  }
  final keys = {
    for (final row in rows)
      if (_counts(row)) foodKeyOf(row.meal!),
  };
  final match = matchingRecord(
    records,
    keys: keys,
    dish: readDishName(rows),
    now: now,
  );
  if (match == null) return null;
  final theirs = match.record.keys;
  final shared = [
    for (final row in rows)
      if (_counts(row) && theirs.contains(foodKeyOf(row.meal!))) row,
  ];
  if (!shared.any((row) => isScalableRow(row, note: note))) return null;
  final sharedKeys = {for (final row in shared) foodKeyOf(row.meal!)};
  final then = match.record.foods
      .where((food) => sharedKeys.contains(food.key))
      .fold(0.0, (sum, food) => sum + food.kcal);
  final read = shared.fold(
    0.0,
    (sum, row) => sum + (rowMacros(row)?.kcal ?? 0),
  );
  if (read <= 0 || (then - read).abs() / read < 0.1) return null;
  return PhotoMealMatch(match.record, match.kind, sharedKeys.length);
}

/// Whether [match] still stands among [rows]: enough of its foods are
/// there, not broken down or left out.
bool photoMealMatchStands(List<BulkAddRow> rows, PhotoMealMatch match) {
  final theirs = match.record.keys;
  final shared = {
    for (final row in rows)
      if (_counts(row) && theirs.contains(foodKeyOf(row.meal!)))
        foodKeyOf(row.meal!),
  };
  return shared.length >= match.sharedNeeded;
}

/// The amount text each of [rows] takes from [record]: every row of a food
/// in it that [canTake] allows, by its resolved item, in the row's unit.
/// Two rows of one food share its amount as their own amounts do.
Map<ResolvedMealItem, String> photoMealAmounts(
  List<BulkAddRow> rows,
  PhotoMealRecord record, {
  required bool Function(BulkAddRow row) canTake,
}) {
  final then = <String, double>{};
  for (final food in record.foods) {
    then[food.key] = (then[food.key] ?? 0) + food.amount;
  }
  final byKey = <String, List<BulkAddRow>>{};
  for (final row in rows) {
    if (!_counts(row) || !canTake(row)) continue;
    final key = foodKeyOf(row.meal!);
    if (!then.containsKey(key)) continue;
    (byKey[key] ??= []).add(row);
  }
  final amounts = LinkedHashMap<ResolvedMealItem, String>.identity();
  for (final MapEntry(key: key, value: same) in byKey.entries) {
    final now = [for (final row in same) baseAmountOf(row) ?? 0];
    final total = now.fold(0.0, (a, b) => a + b);
    for (final (i, row) in same.indexed) {
      final share = total > 0 ? now[i] / total : 1 / same.length;
      final text = _inRowUnit(row, then[key]! * share);
      if (text != null) amounts[row.resolved] = text;
    }
  }
  return amounts;
}

/// [base] grams or millilitres in [row]'s unit, as its field holds it.
String? _inRowUnit(BulkAddRow row, double base) {
  final meal = row.meal;
  if (meal == null || base <= 0) return null;
  final unit = row.effectiveUnit;
  final perUnit = convertQuantityToBaseUnit(1, unit, meal);
  if (perUnit <= 0) return null;
  return scaledAmountText(base / perUnit, unit, 1);
}
