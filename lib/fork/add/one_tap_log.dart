import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:opennutritracker/core/data/data_source/remote_search_cache_data_source.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/core/utils/navigation_options.dart';
import 'package:opennutritracker/core/utils/tracked_day_lock.dart';
import 'package:opennutritracker/features/add_meal/data/repository/products_repository.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/meal_detail/meal_detail_screen.dart';
import 'package:opennutritracker/features/meal_detail/presentation/bloc/meal_detail_bloc.dart';
import 'package:opennutritracker/features/meal_detail/util/hydrate_off_meal.dart';
import 'package:opennutritracker/features/meal_detail/util/meal_quantity_converter.dart';
import 'package:opennutritracker/features/add_meal/util/portion_unit.dart'
    show isPortionUnit;
import 'package:opennutritracker/fork/add/logged_bar.dart';
import 'package:opennutritracker/fork/amounts/own_portions.dart';
import 'package:opennutritracker/fork/amounts/remembered_amounts.dart';
import 'package:opennutritracker/fork/basket/basket_ui.dart'
    show refreshAfterLogging;
import 'package:opennutritracker/fork/copy/copy_ui.dart' show mealLabel;
import 'package:opennutritracker/fork/meal_detail/missing_info.dart';
import 'package:opennutritracker/fork/units/amount_text.dart'
    show amountText, isEnergyOnly;

/// What a food row's plus logs at once: the unit and the amount in grams
/// or millilitres, as an entry stores them.
typedef OneTapAmount = ({String unit, double amount});

/// The amount the food's page would open at: [last], a recent's latest
/// entry, as it was logged; else the amount last logged of the food
/// ([remembered]); else a serving when the food has one that scales and
/// [rawUnits] is off, else 100 g or ml (1 oz or fl oz when [imperial]).
OneTapAmount oneTapAmount(
  MealEntity meal, {
  IntakeEntity? last,
  RememberedAmount? remembered,
  bool imperial = false,
  bool rawUnits = false,
}) {
  if (last != null && last.amount > 0) {
    return (unit: last.unit, amount: last.amount);
  }
  OneTapAmount of(String unit, double quantity) =>
      (unit: unit, amount: convertQuantityToBaseUnit(quantity, unit, meal));
  if (remembered != null) {
    final quantity = double.tryParse(remembered.quantity.replaceAll(',', '.'));
    final serving = remembered.unit == UnitDropdownItem.serving.toString();
    if (quantity != null &&
        quantity > 0 &&
        (!serving || meal.scalableServingQuantity != null)) {
      return of(remembered.unit, quantity);
    }
  }
  if (meal.scalableServingQuantity != null && !rawUnits) {
    return of(UnitDropdownItem.serving.toString(), 1);
  }
  final unit = meal.isLiquid
      ? (imperial ? UnitDropdownItem.flOz : UnitDropdownItem.ml)
      : meal.isSolid
      ? (imperial ? UnitDropdownItem.oz : UnitDropdownItem.g)
      : UnitDropdownItem.gml;
  return of(
    unit.toString(),
    imperial && unit != UnitDropdownItem.gml ? 1 : 100,
  );
}

/// The amount the plus logs for [meal] once its record is in: the user's
/// raw-units choice and the food's remembered amount read as the log
/// reads them, so the plus's label and what it logs agree. A remembered
/// own portion is found by its name among the user's portions (S195), and
/// is passed over once removed.
Future<OneTapAmount> rowAmount(
  MealEntity meal, {
  IntakeEntity? last,
  bool imperial = false,
}) async {
  final rawUnits =
      (await locator<GetConfigUsecase>().getConfig()).defaultToRawFoodUnits;
  final stored = last == null ? await RememberedAmounts.current.of(meal) : null;
  final own = stored?.unit.startsWith(ownUnitPrefix) == true
      ? withOwnPortions(meal, await OwnPortions.current.of(meal))
      : meal;
  final unit = stored == null ? null : unitFromRemembered(own, stored.unit);
  return oneTapAmount(
    own,
    last: last,
    remembered: unit == null ? null : (unit: unit, quantity: stored!.quantity),
    imperial: imperial,
    rawUnits: rawUnits,
  );
}

/// What the plus says it adds (D39): "1 roll" when it adds one of the
/// food's servings and the serving names itself, else the amount as the
/// Diary will show it, "60 g". Null when the amount is not known before
/// the tap: a text-search hit's serving comes with its record, and a
/// Quick add of energy alone has no amount to name.
String? oneTapLabel(
  MealEntity meal,
  OneTapAmount amount, {
  bool imperial = false,
}) {
  if (_isThin(meal) || isEnergyOnly(meal) || amount.amount <= 0) return null;
  final serving = meal.scalableServingQuantity;
  if (isPortionUnit(amount.unit) &&
      serving != null &&
      (amount.amount - serving).abs() < 0.01) {
    final named = RegExp(
      r'^\s*1\s+([^\d(),]{1,12}?)\s*(?:\(|$)',
    ).firstMatch(meal.servingSize ?? '');
    if (named != null) return '1 ${named.group(1)}';
  }
  return amountText(
    IntakeEntity(
      id: '',
      unit: amount.unit,
      amount: amount.amount,
      type: IntakeTypeEntity.snack,
      meal: meal,
      dateTime: DateTime(2000),
    ),
    imperial,
  );
}

final _log = Logger('OneTapLog');

/// An Open Food Facts text-search hit: no serving, no micronutrients.
bool _isThin(MealEntity meal) =>
    meal.source == MealSourceEntity.off &&
    !meal.detailed &&
    (meal.code?.isNotEmpty ?? false);

/// [meal] as the food's page would log it (HydrateMealEvent): the full
/// record of a text-search hit, under the name the search showed (#1475),
/// from the cache or else the network, and
/// [meal] itself when that fails or takes longer than [wait]. A lookup can
/// run for 60 s and the user is waiting on a tap.
Future<MealEntity> hydratedForLog(
  MealEntity meal,
  RemoteSearchCacheDataSource cache,
  ProductsRepository products, {
  Duration wait = const Duration(seconds: 5),
}) async {
  try {
    return await fetchDetailedOffMeal(meal, cache, products).timeout(wait) ??
        meal;
  } catch (error, stack) {
    _log.warning('OFF hydration failed for ${meal.code}', error, stack);
    return meal;
  }
}

/// Codes being looked up: a second tap on the plus in that wait would log
/// the food twice, and the row shows the wait on its plus.
final lookingUp = ValueNotifier<Set<String>>(const {});

/// The plus on a food's row (S179's card, a fork-owned copy): logs [meal]
/// to [type] on [day] at [oneTapAmount] and says so with an Undo. A
/// screen stays open for the next food; the add sheet closes, as its other
/// actions do, so the bar shows rather than under it. The row itself opens
/// the food's page to pick an amount, and so does the plus when the food
/// lacks what the page requires to log it. Tests swap it.
Future<void> Function(
  BuildContext context, {
  required MealEntity meal,
  required IntakeTypeEntity type,
  required DateTime day,
  required bool imperial,
  IntakeEntity? last,
})
logFromRow = defaultLogFromRow;

/// The add sheets logging now: a second tap on the sheet's plus while the
/// first one's log runs would log the food twice, under one bar.
final _sheetsLogging = <Route<dynamic>>{};

/// The app's [logFromRow].
Future<void> defaultLogFromRow(
  BuildContext context, {
  required MealEntity meal,
  required IntakeTypeEntity type,
  required DateTime day,
  required bool imperial,
  IntakeEntity? last,
}) async {
  final route = ModalRoute.of(context);
  final sheet = route is PopupRoute;
  if (sheet && !_sheetsLogging.add(route)) return;
  try {
    await _logFromRow(
      context,
      meal: meal,
      type: type,
      day: day,
      imperial: imperial,
      last: last,
    );
  } finally {
    if (sheet) _sheetsLogging.remove(route);
  }
}

Future<void> _logFromRow(
  BuildContext context, {
  required MealEntity meal,
  required IntakeTypeEntity type,
  required DateTime day,
  required bool imperial,
  IntakeEntity? last,
}) async {
  // The search's keyboard would cover the bar.
  FocusManager.instance.primaryFocus?.unfocus();
  final messenger = ScaffoldMessenger.maybeOf(context);
  final stamp = ProfileStamp.now();
  final thin = _isThin(meal);
  if (thin) {
    if (lookingUp.value.contains(meal.code)) return;
    lookingUp.value = {...lookingUp.value, meal.code!};
  }
  final MealEntity food;
  try {
    food = await hydratedForLog(meal, locator(), locator());
  } finally {
    if (thin) lookingUp.value = {...lookingUp.value}..remove(meal.code);
  }
  if (!context.mounted) return;
  // The unit only names what is missing, which the page says itself.
  if (missingForLog(food, 'kcal').isNotEmpty) {
    Navigator.of(context).pushNamed(
      NavigationOptions.mealDetailRoute,
      arguments: MealDetailScreenArguments(food, type, day, imperial),
    );
    return;
  }
  final amount = await rowAmount(food, last: last, imperial: imperial);
  if (!context.mounted) return;
  final mealName = mealLabel(context, type);
  final route = ModalRoute.of(context);
  IntakeEntity? written;
  var failed = false;
  try {
    written = await locator<MealDetailBloc>().addIntake(
      context,
      amount.unit,
      amount.amount.toString(),
      type,
      food,
      day,
    );
  } catch (error, stack) {
    _log.warning('One-tap write failed for ${meal.code}', error, stack);
    failed = true;
  }
  if (!failed) refreshAfterLogging();
  // A page opened over the sheet while this logged stays open.
  if (route is PopupRoute && route.isCurrent && context.mounted) {
    Navigator.of(context).pop();
  }
  if (messenger == null) return;
  if (written == null) {
    showNotAdded(messenger, failed: failed);
    return;
  }
  final amountAdded = isEnergyOnly(food) ? '' : amountText(written, imperial);
  final name = food.name?.trim() ?? '';
  showLoggedBar(
    messenger,
    name.isEmpty
        ? 'Added ${amountAdded.isEmpty ? 'it' : amountAdded} to $mealName'
        : 'Added $name${amountAdded.isEmpty ? '' : ', $amountAdded,'} to '
              '$mealName',
    day: day,
    written: [written],
    stamp: stamp,
  );
}
