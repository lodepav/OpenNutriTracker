import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
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
}
