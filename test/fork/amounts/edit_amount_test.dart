import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/utils/calc/unit_calc.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/fork/amounts/edit_amount.dart';

import 'amount_test_foods.dart';

IntakeEntity _logged(String unit, double amount, [MealEntity? meal]) =>
    IntakeEntity(
      id: 'i-1',
      unit: unit,
      amount: amount,
      type: IntakeTypeEntity.lunch,
      meal: meal ?? bread(),
      dateTime: DateTime.utc(2026, 11, 15),
    );

void main() {
  group('editOpening', () {
    test('a portion opens as its count, not the grams', () {
      final open = editOpening(
        _logged('serving#1', 120),
        bread(),
        imperial: false,
      );
      expect(open.unit, 'serving#1');
      expect(open.quantity, 2);
    });

    test('a bare serving is the first portion', () {
      final open = editOpening(
        _logged('serving', 70),
        bread(),
        imperial: false,
      );
      expect(open.unit, 'serving');
      expect(open.quantity, closeTo(2.1875, 1e-9));
    });

    test('grams and ounces open as logged', () {
      expect(editOpening(_logged('g', 64.3), bread(), imperial: true), (
        unit: 'g',
        quantity: 64.3,
      ));
      final oz = editOpening(
        _logged('oz', UnitCalc.ozToG(2)),
        bread(),
        imperial: false,
      );
      expect(oz.unit, 'oz');
      expect(oz.quantity, closeTo(2, 1e-9));
    });

    test('a portion no longer on the food opens as its weight', () {
      expect(editOpening(_logged('serving#5', 64), bread(), imperial: false), (
        unit: 'g',
        quantity: 64,
      ));
      final oz = editOpening(_logged('serving#5', 64), bread(), imperial: true);
      expect(oz.unit, 'oz');
      expect(oz.quantity, closeTo(UnitCalc.gToOz(64), 1e-9));
    });
  });

  group('quantityInUnit', () {
    test('keeps the weight across units', () {
      expect(quantityInUnit(1.5, 'serving#1', 'g', bread()), 90);
      expect(quantityInUnit(90, 'g', 'serving', bread()), 2.8125);
      expect(quantityInUnit(2, 'serving#1', 'serving', bread()), 3.75);
    });
  });

  group('editStoredAmount', () {
    test('a weight stores as the old dialog did for the same number', () {
      final intake = _logged('g', 64.3);
      final opened = editOpening(intake, bread(), imperial: false);
      expect(editStoredAmount(64.3, 'g', bread(), intake, opened), 64.3);
      expect(editStoredAmount(80, 'g', bread(), intake, opened), 80);
      final inOz = _logged('oz', UnitCalc.ozToG(2));
      expect(
        editStoredAmount(
          3,
          'oz',
          bread(),
          inOz,
          editOpening(inOz, bread(), imperial: true),
        ),
        UnitCalc.ozToG(3),
      );
    });

    test('a portion count left as it opened keeps the logged grams', () {
      final intake = _logged('serving', 70);
      final opened = editOpening(intake, bread(), imperial: false);
      // shown as 2.19, which would store 70.08
      expect(editStoredAmount(2.19, 'serving', bread(), intake, opened), 70);
    });

    test('a changed count or unit stores its grams', () {
      final intake = _logged('serving', 70);
      final opened = editOpening(intake, bread(), imperial: false);
      expect(editStoredAmount(3, 'serving', bread(), intake, opened), 96);
      expect(
        editStoredAmount(2.19, 'serving#1', bread(), intake, opened),
        closeTo(131.4, 1e-9),
      );
    });

    test('a leftover in a portion takes its share of the portion', () {
      final intake = _logged('serving#1', 120);
      final opened = editOpening(intake, bread(), imperial: false);
      // 2 rolls, half a roll left: 1.5 rolls
      expect(
        editStoredAmount(
          opened.quantity - 0.5,
          'serving#1',
          bread(),
          intake,
          opened,
        ),
        90,
      );
    });
  });
}
