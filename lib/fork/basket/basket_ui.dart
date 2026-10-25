import 'package:flutter/material.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/core/utils/calc/day_boundary_calc.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/core/utils/navigation_options.dart';
import 'package:opennutritracker/core/utils/navigation_predicates.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/diary/presentation/bloc/calendar_day_bloc.dart';
import 'package:opennutritracker/features/diary/presentation/bloc/diary_bloc.dart';
import 'package:opennutritracker/features/home/presentation/bloc/home_bloc.dart';
import 'package:opennutritracker/features/meal_detail/presentation/bloc/meal_detail_bloc.dart';
import 'package:opennutritracker/fork/basket/basket.dart';
import 'package:opennutritracker/fork/plan/plan_store.dart';
import 'package:opennutritracker/fork/units/energy_text.dart';

/// Writes one basket item; upstream's meal detail add in the app. False
/// when it was not written (a profile switch).
typedef LogBasketItem =
    Future<bool> Function(
      BuildContext context,
      BasketItem item,
      IntakeTypeEntity type,
      DateTime day,
    );

Future<bool> _logWithMealDetail(
  BuildContext context,
  BasketItem item,
  IntakeTypeEntity type,
  DateTime day,
) async =>
    await locator<MealDetailBloc>().addIntake(
      context,
      item.unit,
      item.amountText,
      type,
      item.meal,
      day,
    ) !=
    null;

/// Home and the Diary, after entries were written outside upstream's
/// screens; skipped where the app's blocs are not registered (tests).
void refreshAfterLogging() {
  if (!locator.isRegistered<HomeBloc>()) return;
  locator<HomeBloc>().add(const LoadItemsEvent());
  locator<DiaryBloc>().add(const LoadDiaryYearEvent());
  locator<CalendarDayBloc>().add(const RefreshCalendarDayEvent());
}

/// Seam S42: beside the meal detail's Add. Puts the food in the basket at
/// the amount chosen and goes back to search for the next one.
class AddToBasketButton extends StatelessWidget {
  final MealEntity meal;
  final IntakeTypeEntity type;
  final DateTime day;

  /// The unit, amount and kcal as the Add button would log them; null
  /// while the amount is not a positive number.
  final BasketItem? Function() current;
  final FoodBasket? basket;

  const AddToBasketButton({
    super.key,
    required this.meal,
    required this.type,
    required this.day,
    required this.current,
    this.basket,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: OutlinedButton.icon(
      key: const ValueKey('add-to-basket'),
      icon: const Icon(Icons.shopping_basket_outlined),
      label: const Text('Add to basket'),
      onPressed: () {
        final item = current();
        if (item == null) return;
        final target = basket ?? FoodBasket.instance;
        target.add(item, type, day);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${meal.name ?? 'Food'} is in the basket '
              '(${target.items.length}).',
            ),
          ),
        );
        Navigator.of(context).pop();
      },
    ),
  );
}

/// Seam S42: under the search results while the basket holds this meal's
/// foods; opens the review.
class BasketBar extends StatelessWidget {
  final IntakeTypeEntity type;
  final DateTime day;
  final FoodBasket? basket;
  final LogBasketItem log;
  final PlanStore? plans;

  const BasketBar({
    super.key,
    required this.type,
    required this.day,
    this.basket,
    this.log = _logWithMealDetail,
    this.plans,
  });

  @override
  Widget build(BuildContext context) {
    final target = basket ?? FoodBasket.instance;
    return ListenableBuilder(
      listenable: target,
      builder: (context, _) {
        final items = target.itemsFor(type, day);
        if (items.isEmpty) return const SizedBox.shrink();
        return Material(
          color: Theme.of(context).colorScheme.secondaryContainer,
          child: SafeArea(
            top: false,
            child: ListTile(
              key: const ValueKey('basket-bar'),
              leading: const Icon(Icons.shopping_basket_rounded),
              title: Text(
                '${items.length} in the basket · '
                '${energyText(context, target.totalKcal)}',
              ),
              trailing: const Text('Review'),
              onTap: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                builder: (_) => BasketSheet(
                  type: type,
                  day: day,
                  basket: target,
                  log: log,
                  plans: plans,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The basket's foods, each removable, and "Log all", which writes them
/// one after another (each takes the tracked-day lock) and goes home.
class BasketSheet extends StatefulWidget {
  final IntakeTypeEntity type;
  final DateTime day;
  final FoodBasket basket;
  final LogBasketItem log;
  final PlanStore? plans;

  const BasketSheet({
    super.key,
    required this.type,
    required this.day,
    required this.basket,
    required this.log,
    this.plans,
  });

  @override
  State<BasketSheet> createState() => _BasketSheetState();
}

class _BasketSheetState extends State<BasketSheet> {
  bool _logging = false;

  /// Puts the foods on the day's plan (`PlanStore`) instead of the diary.
  Future<void> _plan() async {
    setState(() => _logging = true);
    final items = widget.basket.itemsFor(widget.type, widget.day);
    // Home passes the moment: after midnight but before the day starts it
    // is still the previous day's plan.
    final offset = (await locator<GetConfigUsecase>().getConfig())
        .dayStartOffsetTotalMinutes;
    await (widget.plans ?? PlanStore()).add(
      [
        for (final i in items)
          (meal: i.meal, unit: i.unit, amountText: i.amountText, kcal: i.kcal),
      ],
      widget.type,
      DayBoundaryCalc.dayLabelOf(widget.day, offset),
    );
    widget.basket.clear();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Planned ${items.length} foods.')));
    Navigator.of(
      context,
    ).popUntil(namedRouteOrFirst(NavigationOptions.mainRoute));
  }

  Future<void> _logAll() async {
    setState(() => _logging = true);
    final items = widget.basket.itemsFor(widget.type, widget.day);
    var logged = 0;
    for (final item in items) {
      if (!mounted) break;
      // Not written (a profile switch): it and the rest stay in the basket.
      if (!await widget.log(context, item, widget.type, widget.day)) break;
      // Out of the basket once logged: a sheet closed partway leaves only
      // what was not, so logging again adds nothing twice.
      widget.basket.remove(item);
      logged++;
    }
    refreshAfterLogging();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Logged $logged foods.')));
    Navigator.of(
      context,
    ).popUntil(namedRouteOrFirst(NavigationOptions.mainRoute));
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.basket,
    builder: (context, _) {
      final items = widget.basket.itemsFor(widget.type, widget.day);
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Basket', style: Theme.of(context).textTheme.titleLarge),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final (i, item) in items.indexed)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(item.meal.name ?? ''),
                        subtitle: Text(
                          '${item.picked ?? '${amountLabel(item.amountText)} '
                                  '${item.unit}'} · '
                          '${energyText(context, item.kcal)}',
                        ),
                        trailing: IconButton(
                          key: ValueKey('basket-remove-$i'),
                          icon: const Icon(Icons.close_rounded),
                          tooltip: 'Remove',
                          onPressed: _logging
                              ? null
                              : () {
                                  widget.basket.removeAt(i);
                                  if (widget.basket.items.isEmpty) {
                                    Navigator.of(context).pop();
                                  }
                                },
                        ),
                      ),
                  ],
                ),
              ),
              const Divider(),
              Text(
                'Total ${energyText(context, widget.basket.totalKcal)}',
                textAlign: TextAlign.end,
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _logging || items.isEmpty ? null : _logAll,
                child: Text('Log all ${items.length}'),
              ),
              OutlinedButton(
                key: const ValueKey('basket-plan'),
                onPressed: _logging || items.isEmpty ? null : _plan,
                child: const Text('Plan, don\'t log'),
              ),
              TextButton(
                onPressed: _logging
                    ? null
                    : () {
                        widget.basket.clear();
                        Navigator.of(context).pop();
                      },
                child: const Text('Empty the basket'),
              ),
            ],
          ),
        ),
      );
    },
  );
}
