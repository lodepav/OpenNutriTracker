import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:opennutritracker/core/data/dbo/meal_dbo.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/utils/id_generator.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_store.dart';

/// A food planned for a meal of a day, not yet logged.
class PlannedFood {
  final String id;
  final DateTime day;
  final IntakeTypeEntity type;
  final MealEntity meal;
  final String unit;
  final String amountText;
  final double kcal;

  const PlannedFood({
    required this.id,
    required this.day,
    required this.type,
    required this.meal,
    required this.unit,
    required this.amountText,
    required this.kcal,
  });

  Map<String, Object?> toJson() => {
    'id': id,
    'day': day.toIso8601String(),
    'type': type.name,
    // Deep: MealDBO's toJson leaves its nutriments an object.
    'meal': jsonDecode(jsonEncode(MealDBO.fromMealEntity(meal))),
    'unit': unit,
    'amountText': amountText,
    'kcal': kcal,
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

  Future<List<PlannedFood>> forDay(DateTime day) async => [
    for (final food in await all())
      if (_sameDay(food.day, day)) food,
  ];

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

  Future<void> remove(String id) async => _write([
    for (final f in await all())
      if (f.id != id) f,
  ]);

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

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}
