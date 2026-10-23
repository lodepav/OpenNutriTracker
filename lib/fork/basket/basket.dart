import 'package:flutter/foundation.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';

/// A food picked for the basket, with the amount and unit as the meal
/// detail would log them.
class BasketItem {
  final MealEntity meal;
  final String unit;
  final String amountText;
  final double kcal;

  const BasketItem({
    required this.meal,
    required this.unit,
    required this.amountText,
    required this.kcal,
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
      _type == type && _day == day ? items : const [];

  void add(BasketItem item, IntakeTypeEntity type, DateTime day) {
    if (_type != type || _day != day) _items.clear();
    _type = type;
    _day = day;
    _items.add(item);
    notifyListeners();
  }

  void removeAt(int index) {
    _items.removeAt(index);
    notifyListeners();
  }

  void clear() {
    _items.clear();
    notifyListeners();
  }
}
