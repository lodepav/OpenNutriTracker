import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:opennutritracker/core/data/dbo/meal_dbo.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/utils/id_generator.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_store.dart';

/// A food planned for a meal of a day, not yet logged; or, with
/// [weekdays], one planned on those days from [day] on (a usual
/// breakfast), each day's until it is logged or dropped.
class PlannedFood {
  final String id;
  final DateTime day;
  final IntakeTypeEntity type;
  final MealEntity meal;
  final String unit;
  final String amountText;
  final double kcal;

  /// [DateTime.weekday]s it repeats on; empty for one day only.
  final Set<int> weekdays;

  /// Days a repeating food was logged or dropped on.
  final Set<DateTime> doneDays;

  /// For one day of a repeating food, the repeating food's id.
  final String? repeatOf;

  const PlannedFood({
    required this.id,
    required this.day,
    required this.type,
    required this.meal,
    required this.unit,
    required this.amountText,
    required this.kcal,
    this.weekdays = const {},
    this.doneDays = const {},
    this.repeatOf,
  });

  bool get repeats => weekdays.isNotEmpty;

  PlannedFood _copy({
    String? id,
    DateTime? day,
    Set<int>? weekdays,
    Set<DateTime>? doneDays,
    String? repeatOf,
  }) => PlannedFood(
    id: id ?? this.id,
    day: day ?? this.day,
    type: type,
    meal: meal,
    unit: unit,
    amountText: amountText,
    kcal: kcal,
    weekdays: weekdays ?? this.weekdays,
    doneDays: doneDays ?? this.doneDays,
    repeatOf: repeatOf ?? this.repeatOf,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'day': day.toIso8601String(),
    'type': type.name,
    // Deep: MealDBO's toJson leaves its nutriments an object.
    'meal': jsonDecode(jsonEncode(MealDBO.fromMealEntity(meal))),
    'unit': unit,
    'amountText': amountText,
    'kcal': kcal,
    if (repeats) 'weekdays': weekdays.toList()..sort(),
    if (repeats) 'doneDays': [for (final d in doneDays) d.toIso8601String()],
  };

  static PlannedFood fromJson(Map<dynamic, dynamic> json) => PlannedFood(
    id: json['id'] as String,
    day: DateTime.parse(json['day'] as String),
    type: IntakeTypeEntity.values.byName(json['type'] as String),
    // Deep: after a reopen Hive gives nested maps back as Map<dynamic,
    // dynamic>, which MealDBO's generated fromJson casts to String keys.
    meal: MealEntity.fromMealDBO(
      MealDBO.fromJson(
        jsonDecode(jsonEncode(json['meal'])) as Map<String, dynamic>,
      ),
    ),
    unit: json['unit'] as String,
    amountText: json['amountText'] as String,
    kcal: (json['kcal'] as num).toDouble(),
    weekdays: {for (final d in json['weekdays'] as List? ?? const []) d as int},
    doneDays: {
      for (final d in json['doneDays'] as List? ?? const [])
        DateTime.parse(d as String),
    },
  );
}

/// The meal plan (MacroFactor's planner): foods put on a day's meal ahead,
/// counted nowhere until each is logged. Kept in the fork's per-profile box
/// beside the adaptive state, so it follows the profile.
class PlanStore {
  static const _key = 'plannedFoods';

  /// Bumped on every write, so the cards showing the plan reload.
  static final changes = ValueNotifier(0);

  final Future<Box<dynamic>> Function() _box;

  PlanStore([Future<Box<dynamic>> Function()? box])
    : _box = box ?? AdaptiveStore.openActiveBox;

  Future<List<PlannedFood>> all() async => [
    for (final json in (await _box()).get(_key, defaultValue: []) as List)
      PlannedFood.fromJson(json as Map),
  ];

  /// [day]'s foods: those planned on it, and a repeating food's day
  /// when it falls on one of its weekdays and is not yet logged or
  /// dropped.
  Future<List<PlannedFood>> forDay(DateTime day) async {
    final date = _date(day);
    return [
      for (final food in await all())
        if (!food.repeats && _sameDay(food.day, date))
          food
        else if (food.repeats &&
            !date.isBefore(_date(food.day)) &&
            food.weekdays.contains(date.weekday) &&
            !food.doneDays.contains(date))
          food._copy(
            id: '${food.id}@${_dayKey(date)}',
            day: date,
            repeatOf: food.id,
          ),
    ];
  }

  Future<void> add(
    Iterable<({MealEntity meal, String unit, String amountText, double kcal})>
    foods,
    IntakeTypeEntity type,
    DateTime day,
  ) async => _write([
    ...await all(),
    for (final f in foods)
      PlannedFood(
        id: IdGenerator.getUniqueID(),
        day: DateTime(day.year, day.month, day.day),
        type: type,
        meal: f.meal,
        unit: f.unit,
        amountText: f.amountText,
        kcal: f.kcal,
      ),
  ]);

  /// Drops one planned food (logged, or not wanted); for a repeating
  /// food's day, that day only.
  Future<void> remove(String id) async {
    final at = id.indexOf('@');
    if (at < 0) {
      return _write([
        for (final f in await all())
          if (f.id != id) f,
      ]);
    }
    final ruleId = id.substring(0, at);
    final day = DateTime.parse(id.substring(at + 1));
    // Days long past are forgotten, so the list stays short.
    final keepFrom = _date(DateTime.now()).subtract(const Duration(days: 60));
    await _write([
      for (final f in await all())
        if (f.id == ruleId)
          f._copy(
            doneDays: {
              for (final d in f.doneDays)
                if (!d.isBefore(keepFrom)) d,
              day,
            },
          )
        else
          f,
    ]);
  }

  /// Makes the food [id] (planned, or one day of a repeating one) repeat
  /// on [weekdays] from its day on; empty [weekdays] stops it repeating
  /// and drops it.
  Future<void> setRepeat(String id, Set<int> weekdays) async {
    final ruleId = id.contains('@') ? id.substring(0, id.indexOf('@')) : id;
    await _write([
      for (final f in await all())
        if (f.id != ruleId)
          f
        else if (weekdays.isNotEmpty)
          f._copy(weekdays: weekdays),
    ]);
  }

  /// Adds [foods] from a backup; one with an id already here replaces it.
  Future<void> merge(List<PlannedFood> foods) async {
    final byId = {
      for (final f in [...await all(), ...foods]) f.id: f,
    };
    await _write(byId.values.toList());
  }

  Future<void> _write(List<PlannedFood> foods) async {
    await (await _box()).put(_key, [for (final f in foods) f.toJson()]);
    changes.value++;
  }

  static DateTime _date(DateTime d) => DateTime(d.year, d.month, d.day);

  static String _dayKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}
