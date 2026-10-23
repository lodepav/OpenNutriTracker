import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/body_weight_unit_entity.dart';
import 'package:opennutritracker/fork/widget/macro_widget.dart';

void main() {
  MacroWidgetFigures figures({bool kj = false, int offset = 0}) =>
      MacroWidgetFigures.fromHome(
        logicalDay: DateTime(2026, 10, 23),
        offsetMinutes: offset,
        kilojoules: kj,
        kcal: 1240.4,
        kcalGoal: 2140,
        protein: 92.6,
        proteinGoal: 150,
        carbs: 120.2,
        carbsGoal: 220,
        fat: 41.5,
        fatGoal: 70,
      );

  test('today\'s figures, rounded, as the widget reads them', () {
    expect(jsonDecode(figures().encode()), {
      'day': '2026-10-23',
      'offsetMinutes': 0,
      'energy': [1240, 2140],
      'energyUnit': 'kcal',
      'protein': [93, 150],
      'carbs': [120, 220],
      'fat': [42, 70],
    });
  });

  test('energy in kilojoules when chosen; a bad offset is none', () {
    final f = figures(kj: true, offset: 24 * 60);
    expect(f.energyUnit, 'kJ');
    expect(f.energy, 5190);
    expect(f.energyGoal, 8954);
    expect(f.offsetMinutes, 0);
  });

  test('the key and the provider match the Android side', () {
    expect(MacroWidgetFigures.storageKey, 'openbite_macro_widget');
    expect(
      MacroWidgetFigures.androidProvider,
      endsWith('.fork.MacroWidgetProvider'),
    );
  });

  test('the trend weight and its week, in the user\'s unit', () {
    final trend = [for (var d = 0; d < 10; d++) 81.0 - 0.06 * d];
    final kg = WeightWidgetFigures.fromTrend(trend, BodyWeightUnit.kg)!;
    expect(kg.trend, '80.5 kg');
    expect(kg.change, '-0.4 kg in 7 days');
    final lb = WeightWidgetFigures.fromTrend(trend, BodyWeightUnit.lb)!;
    expect(lb.trend, '177.4 lb');
    expect(lb.change, '-0.9 lb in 7 days');
  });

  test('a short trend has no change; none has no figures', () {
    expect(
      WeightWidgetFigures.fromTrend([80, 79.9], BodyWeightUnit.kg)!.change,
      isNull,
    );
    expect(WeightWidgetFigures.fromTrend([], BodyWeightUnit.kg), isNull);
    expect(
      jsonDecode(
        WeightWidgetFigures.fromTrend([80], BodyWeightUnit.kg)!.encode(),
      ),
      {'trend': '80.0 kg', 'change': null},
    );
  });
}
