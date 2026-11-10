import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/fork/units/amount_text.dart' as diary;

/// [meal] at [base] grams or millilitres as the Diary would hold it once
/// logged, so the review says an amount through the Diary's own formatter
/// (`amountText`, `shownUnit`) and the two cannot drift apart.
IntakeEntity _asLogged(double base, MealEntity meal) => IntakeEntity(
  id: '',
  unit: meal.mealUnit ?? 'g',
  amount: base,
  type: IntakeTypeEntity.breakfast,
  meal: meal,
  dateTime: DateTime(0),
);

/// [base] grams or millilitres of [meal] as the Diary shows them: "12.3 oz"
/// for a solid in imperial units, "350 g" otherwise.
String diaryAmountText(double base, MealEntity meal, bool imperial) =>
    diary.amountText(_asLogged(base, meal), imperial);

/// The unit the Diary shows [meal]'s amounts in, and the factor from grams
/// or millilitres to it.
({String unit, double factor}) diaryUnit(MealEntity meal, bool imperial) =>
    diary.shownUnit(_asLogged(0, meal), imperial);

/// A dish logs as a recipe, whose amounts are grams (`RecipeEntity`).
final _dish = MealEntity(
  code: null,
  name: null,
  url: null,
  mealQuantity: null,
  mealUnit: 'g',
  servingQuantity: null,
  servingUnit: null,
  servingSize: null,
  nutriments: MealNutrimentsEntity.empty(),
  source: MealSourceEntity.custom,
);

/// A dish's portion of [grams] as the Diary will show the logged dish.
String dishPortionText(double grams, bool imperial) =>
    diaryAmountText(grams, _dish, imperial);

/// The unit a dish's portion is shown and typed in, and its factor from
/// grams.
({String unit, double factor}) dishPortionUnit(bool imperial) =>
    diaryUnit(_dish, imperial);
