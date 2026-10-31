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
import 'package:opennutritracker/fork/add/logged_bar.dart';
import 'package:opennutritracker/fork/amounts/remembered_amounts.dart';
import 'package:opennutritracker/fork/basket/basket_ui.dart'
    show refreshAfterLogging;
import 'package:opennutritracker/fork/copy/copy_ui.dart' show mealLabel;
import 'package:opennutritracker/fork/meal_detail/missing_info.dart';
import 'package:opennutritracker/fork/units/amount_text.dart' show amountText;

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
  final rawUnits =
      (await locator<GetConfigUsecase>().getConfig()).defaultToRawFoodUnits;
  final amount = oneTapAmount(
    food,
    last: last,
    remembered: last == null ? await RememberedAmounts.current.of(food) : null,
    imperial: imperial,
    rawUnits: rawUnits,
  );
  if (!context.mounted) return;
  final mealName = mealLabel(context, type);
  final route = ModalRoute.of(context);
  final written = await locator<MealDetailBloc>().addIntake(
    context,
    amount.unit,
    amount.amount.toString(),
    type,
    food,
    day,
  );
  refreshAfterLogging();
  // A page opened over the sheet while this logged stays open.
  if (route is PopupRoute && route.isCurrent && context.mounted) {
    Navigator.of(context).pop();
  }
  if (messenger == null) return;
  messenger.removeCurrentSnackBar();
  if (written == null) {
    messenger.showSnackBar(
      const SnackBar(content: Text('Not added: the profile changed.')),
    );
    return;
  }
  final amountAdded = amountText(written, imperial);
  final name = food.name?.trim() ?? '';
  showLoggedBar(
    messenger,
    name.isEmpty
        ? 'Added $amountAdded to $mealName'
        : 'Added $name, $amountAdded, to $mealName',
    day: day,
    written: [written],
    stamp: stamp,
  );
}
