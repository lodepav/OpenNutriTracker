import 'package:flutter/foundation.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/util/portion_unit.dart';

/// An amount as stored ("150.0") as a person reads it ("150").
String amountLabel(String text) {
  final value = double.tryParse(text);
  if (value == null) return text;
  return value == value.roundToDouble()
      ? value.round().toString()
      : value.toStringAsFixed(1);
}

/// The amount as it was picked: [text] typed in the dropdown's [unit], which
/// for a serving is a count of servings, not the grams logged.
String pickedLabel(String text, String unit) {
  final unitName = storedUnit(unit);
  if (unitName != 'serving') return '${amountLabel(text)} $unitName';
  return '${amountLabel(text)} '
      '${double.tryParse(text) == 1 ? 'serving' : 'servings'}';
}

/// A food picked for the basket, with the amount and unit as the meal
/// detail would log them.
class BasketItem {
  final MealEntity meal;
  final String unit;
  final String amountText;
  final double kcal;

  /// [pickedLabel], for the review; [amountText] is in the food's own unit.
  final String? picked;

  const BasketItem({
    required this.meal,
    required this.unit,
    required this.amountText,
    required this.kcal,
    this.picked,
  });
}

/// Several foods picked from search and logged together (MacroFactor's
/// multi-add). It holds one meal of one day; picking for another empties
/// it first, so nothing is logged where it was not picked.
class FoodBasket extends ChangeNotifier {
  static final instance = FoodBasket();

  final _items = <BasketItem>[];
  IntakeTypeEntity? _type;
  DateTime? _day;

  List<BasketItem> get items => List.unmodifiable(_items);

  double get totalKcal => _items.fold(0, (sum, i) => sum + i.kcal);

  /// The items when they are for [type] on [day], else none.
  List<BasketItem> itemsFor(IntakeTypeEntity type, DateTime day) =>
      _isFor(type, day) ? items : const [];

  void add(BasketItem item, IntakeTypeEntity type, DateTime day) {
    if (!_isFor(type, day)) _items.clear();
    _type = type;
    _day = day;
    _items.add(item);
    notifyListeners();
  }

  /// The same meal on the same calendar day: a day from the add button
  /// carries the time it was opened at, and is still the same day later.
  bool _isFor(IntakeTypeEntity type, DateTime day) =>
      _type == type &&
      _day?.year == day.year &&
      _day?.month == day.month &&
      _day?.day == day.day;

  void removeAt(int index) {
    _items.removeAt(index);
    notifyListeners();
  }

  void remove(BasketItem item) {
    if (_items.remove(item)) notifyListeners();
  }

  void clear() {
    _items.clear();
    notifyListeners();
  }
}
