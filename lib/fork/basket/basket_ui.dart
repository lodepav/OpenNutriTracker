import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:logging/logging.dart';
import 'package:opennutritracker/fork/copy/copy_ui.dart' show mealLabel;
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/core/utils/calc/day_boundary_calc.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/core/utils/navigation_options.dart';
import 'package:opennutritracker/core/utils/navigation_predicates.dart';
import 'package:opennutritracker/core/utils/tracked_day_lock.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/diary/presentation/bloc/calendar_day_bloc.dart';
import 'package:opennutritracker/features/diary/presentation/bloc/diary_bloc.dart';
import 'package:opennutritracker/features/home/presentation/bloc/home_bloc.dart';
import 'package:opennutritracker/features/meal_detail/presentation/bloc/meal_detail_bloc.dart';
import 'package:opennutritracker/fork/add/logged_bar.dart';
import 'package:opennutritracker/fork/basket/basket.dart';
import 'package:opennutritracker/core/presentation/widgets/app_card.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/fork/display/meal_macros_line.dart';
import 'package:opennutritracker/fork/meal_detail/food_page.dart'
    show DayTotals, TodayAfterAdding, loadDayTotals;
import 'package:opennutritracker/fork/plan/plan_store.dart';
import 'package:opennutritracker/fork/plan/plan_ui.dart';
import 'package:opennutritracker/fork/units/energy_text.dart';

final _log = Logger('Basket');

/// Writes one basket item; upstream's meal detail add in the app. Null
/// when it was not written (a profile switch).
typedef LogBasketItem =
    Future<IntakeEntity?> Function(
      BuildContext context,
      BasketItem item,
      IntakeTypeEntity type,
      DateTime day,
    );

Future<IntakeEntity?> _logWithMealDetail(
  BuildContext context,
  BasketItem item,
  IntakeTypeEntity type,
  DateTime day,
) => locator<MealDetailBloc>().addIntake(
  context,
  item.unit,
  item.amountText,
  type,
  item.meal,
  day,
);

/// Ticks when [refreshAfterLogging] runs, for what reads the day's totals
/// outside the blocs.
final entriesChanged = ValueNotifier<int>(0);

/// Home and the Diary, after entries were written outside upstream's
/// screens; skipped where the app's blocs are not registered (tests).
void refreshAfterLogging() {
  entriesChanged.value++;
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

  /// Only the basket icon, for a row beside Add (S125).
  final bool compact;

  /// "Add to plan" rather than "Add to basket", while planning.
  final bool planning;

  const AddToBasketButton({
    super.key,
    required this.meal,
    required this.type,
    required this.day,
    required this.current,
    this.basket,
    this.compact = false,
    this.planning = false,
  });

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return IconButton.outlined(
        key: const ValueKey('add-to-basket'),
        tooltip: 'Add to basket',
        icon: const Icon(Icons.shopping_basket_outlined),
        onPressed: () => _add(context),
      );
    }
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        key: const ValueKey('add-to-basket'),
        icon: Icon(
          planning ? Icons.event_note_rounded : Icons.shopping_basket_outlined,
        ),
        label: Text(planning ? 'Add to plan' : 'Add to basket'),
        onPressed: () => _add(context),
      ),
    );
  }

  void _add(BuildContext context) {
    final item = current();
    if (item == null) return;
    final target = basket ?? FoodBasket.instance;
    target.add(item, type, day);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          target.planning != null
              ? '${meal.name ?? 'Food'} is picked. Review to plan it.'
              : '${meal.name ?? 'Food'} is in the basket '
                    '(${target.items.length}).',
        ),
      ),
    );
    Navigator.of(context).pop();
  }
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
                '${items.length} ${target.planning != null ? 'to plan' : 'in the basket'} · '
                '${basketShownEnergy(items, (kcal) => energyValue(context, kcal))} '
                '${energyUnit(context)}',
              ),
              trailing: const Text('Review'),
              onTap: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                useSafeArea: true,
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

/// The basket's energy as its rows show it, each rounded by [shown] and
/// then summed, so the bar and the meal card agree with the rows (#1469).
int basketShownEnergy(
  Iterable<BasketItem> items,
  int Function(double kcal) shown,
) => items.fold(0, (sum, i) => sum + shown(i.kcal));

/// The day's totals for the basket's meal card; tests swap it.
Future<DayTotals> Function(DateTime day) basketDayTotals = loadDayTotals;

/// [item]'s carbs, fat and protein in grams: its amount is stored as an
/// entry's is, in grams or millilitres whatever unit it was picked in.
({double carbs, double fat, double protein}) basketItemMacros(BasketItem item) {
  final amount = double.tryParse(item.amountText.replaceAll(',', '.')) ?? 0;
  final n = item.meal.nutriments;
  return (
    carbs: amount * (n.carbohydratesPerUnit ?? 0),
    fat: amount * (n.fatPerUnit ?? 0),
    protein: amount * (n.proteinsPerUnit ?? 0),
  );
}

/// The plan button's words: the day it plans for, "today" when it is.
String planButtonLabel(DateTime day, DateTime now, String locale) =>
    DateUtils.isSameDay(day, now)
    ? 'Plan for today'
    : 'Plan for ${DateFormat.MMMEd(locale).format(day)}';

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

  /// Log all, not a plan, is under way: its button shows it.
  bool _loggingAll = false;

  /// Why the last "Log all" wrote nothing: said here, as a bar would show
  /// under this sheet, which stays open for another go.
  String? _failed;

  /// The food just removed while others stay, and how to put it back: said
  /// in the sheet, as a bar would show under it.
  ({String name, VoidCallback restore})? _removed;

  void _remove(int index, BasketItem item) {
    final restore = widget.basket.restorePoint();
    widget.basket.removeAt(index);
    final name = item.meal.name ?? 'Food';
    if (widget.basket.items.isNotEmpty) {
      setState(() => _removed = (name: name, restore: restore));
      return;
    }
    _closeWithUndo('Removed $name.', restore);
  }

  void _empty() {
    _closeWithUndo(
      widget.basket.planning != null
          ? 'Cleared the foods to plan.'
          : 'Emptied the basket.',
      widget.basket.setAside(),
    );
  }

  /// Closes the sheet and offers [restore] on the screen under it.
  void _closeWithUndo(String message, VoidCallback restore) {
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    messenger
      ..removeCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          action: SnackBarAction(label: 'Undo', onPressed: restore),
        ),
      );
  }

  /// Puts the foods on the day's plan (`PlanStore`) instead of the diary,
  /// repeating on [weekdays] if any.
  Future<void> _plan({Set<int> weekdays = const {}}) async {
    setState(() => _logging = true);
    final items = widget.basket.itemsFor(widget.type, widget.day);
    // Home passes the moment: after midnight but before the day starts it
    // is still the previous day's plan.
    final offset = (await locator<GetConfigUsecase>().getConfig())
        .dayStartOffsetTotalMinutes;
    final planDay = DayBoundaryCalc.dayLabelOf(widget.day, offset);
    await (widget.plans ?? PlanStore()).add(
      [
        for (final i in items)
          (meal: i.meal, unit: i.unit, amountText: i.amountText, kcal: i.kcal),
      ],
      widget.type,
      planDay,
      weekdays: weekdays,
    );
    final planning = widget.basket.planning != null;
    widget.basket.clear();
    if (!mounted) return;
    final count = items.length == 1 ? '1 food' : '${items.length} foods';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          weekdays.isEmpty
              ? 'Planned $count for '
                    '${DateFormat.MMMEd(Localizations.localeOf(context).toLanguageTag()).format(planDay)}.'
              : 'Repeating $count.',
        ),
      ),
    );
    final navigator = Navigator.of(context);
    if (planning) {
      // The sheet and search, back to the meal plan they came from.
      navigator
        ..pop()
        ..pop();
    } else {
      navigator.popUntil(namedRouteOrFirst(NavigationOptions.mainRoute));
    }
  }

  /// Asks which days, from the day picked on, then plans the foods on them.
  Future<void> _repeat() async {
    final weekdays = await showDialog<Set<int>>(
      context: context,
      builder: (_) => RepeatDialog(
        name: mealLabel(context, widget.type),
        initial: {widget.day.weekday},
      ),
    );
    if (weekdays != null && weekdays.isNotEmpty && mounted) {
      await _plan(weekdays: weekdays);
    }
  }

  Future<void> _logAll() async {
    setState(() {
      _logging = true;
      _loggingAll = true;
      _failed = null;
    });
    final items = widget.basket.itemsFor(widget.type, widget.day);
    final messenger = ScaffoldMessenger.of(context);
    final stamp = ProfileStamp.now();
    final written = <IntakeEntity>[];
    var failed = false;
    try {
      for (final item in items) {
        if (!mounted) break;
        final intake = await widget.log(context, item, widget.type, widget.day);
        // Not written (a profile switch): it and the rest stay in the basket.
        if (intake == null) break;
        // Out of the basket once logged: a sheet closed partway leaves only
        // what was not, so logging again adds nothing twice.
        widget.basket.remove(item);
        written.add(intake);
      }
    } catch (error, stack) {
      _log.warning('Log all stopped by a failed write', error, stack);
      failed = true;
    }
    refreshAfterLogging();
    if (!mounted) return;
    final logged = written.length;
    final unwritten = failed
        ? "The rest couldn't be saved and stay in the basket."
        : 'Not all added: the profile changed.';
    if (logged == 0) {
      if (failed) {
        setState(() {
          _logging = false;
          _loggingAll = false;
          _failed = unwritten;
        });
        return;
      }
      messenger
        ..removeCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(unwritten)));
    } else {
      showLoggedBar(
        messenger,
        'Logged $logged ${logged == 1 ? 'food' : 'foods'} to '
        '${mealLabel(context, widget.type)}.'
        '${logged < items.length ? ' $unwritten' : ''}',
        day: widget.day,
        written: written,
        stamp: stamp,
      );
    }
    Navigator.of(
      context,
    ).popUntil(namedRouteOrFirst(NavigationOptions.mainRoute));
  }

  /// What the foods come to together, and the day with them added (D39),
  /// as Log with AI's review shows its meal. A meal repeated on set days
  /// has no one day to show.
  Widget _mealCard(BuildContext context, List<BasketItem> items) {
    final theme = Theme.of(context);
    final palette = paletteOf(context);
    final muted = theme.textTheme.labelMedium?.copyWith(
      color: palette.textMuted,
    );
    var carbs = 0.0, fat = 0.0, protein = 0.0;
    for (final item in items) {
      final m = basketItemMacros(item);
      carbs += m.carbs;
      fat += m.fat;
      protein += m.protein;
    }
    final kcal = items.fold(0.0, (sum, i) => sum + i.kcal);
    final showDay = widget.basket.planning != PlanMode.recurring;
    return AppCard(
      key: const ValueKey('basket-meal-card'),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text(
                  'This meal · ${items.length} '
                  '${items.length == 1 ? 'food' : 'foods'}',
                  style: muted,
                ),
              ),
              // summed as the rows show it (#1469)
              Text(
                '${basketShownEnergy(items, (kcal) => energyValue(context, kcal))} '
                '${energyUnit(context)}',
                key: const ValueKey('basket-meal-kcal'),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: palette.textStrong,
                ),
              ),
            ],
          ),
          MacrosLine(carbs: carbs, fat: fat, protein: protein),
          if (showDay) ...[
            const SizedBox(height: 10),
            Text(
              DateUtils.isSameDay(widget.day, DateTime.now())
                  ? 'Today with this meal'
                  : 'That day with this meal',
              style: muted,
            ),
            const SizedBox(height: 6),
            TodayAfterAdding(
              day: widget.day,
              kcal: kcal,
              carbs: carbs,
              fat: fat,
              protein: protein,
              load: basketDayTotals,
              framed: false,
            ),
          ] else
            const SizedBox(height: 8),
        ],
      ),
    );
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
              Semantics(
                header: true,
                child: Text(
                  // as the bar names it while planning
                  widget.basket.planning != null ? 'To plan' : 'Basket',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              if (items.isNotEmpty) ...[
                const SizedBox(height: 12),
                _mealCard(context, items),
              ],
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
                          tooltip: 'Remove ${item.meal.name ?? ''}',
                          onPressed: _logging ? null : () => _remove(i, item),
                        ),
                      ),
                  ],
                ),
              ),
              if (_removed case final removed?)
                Semantics(
                  liveRegion: true,
                  child: Row(
                  key: const ValueKey('basket-removed'),
                  children: [
                    Expanded(child: Text('Removed ${removed.name}.')),
                    TextButton(
                      onPressed: _logging
                          ? null
                          : () {
                              removed.restore();
                              setState(() => _removed = null);
                            },
                      child: const Text('Undo'),
                    ),
                  ],
                  ),
                ),
              const Divider(),
              if (_failed case final failed?)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    failed,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              if (widget.basket.planning == null) ...[
                FilledButton.icon(
                  onPressed: _logging || items.isEmpty ? null : _logAll,
                  // a slow log shows it is under way
                  icon: _loggingAll
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : null,
                  label: Text(
                    '${items.length == 1 ? 'Log 1 food' : 'Log all ${items.length}'} '
                    'to ${mealLabel(context, widget.type)}',
                  ),
                ),
                OutlinedButton(
                  key: const ValueKey('basket-plan'),
                  onPressed: _logging || items.isEmpty ? null : _plan,
                  child: Text(
                    planButtonLabel(
                      widget.day,
                      DateTime.now(),
                      Localizations.localeOf(context).toLanguageTag(),
                    ),
                  ),
                ),
              ] else ...[
                if (widget.basket.planning == PlanMode.once)
                  FilledButton(
                    key: const ValueKey('basket-plan'),
                    onPressed: _logging || items.isEmpty ? null : _plan,
                    child: Text(
                      'Plan for ${DateFormat.MMMEd(Localizations.localeOf(context).toLanguageTag()).format(widget.day)}',
                    ),
                  ),
                OutlinedButton(
                  key: const ValueKey('basket-repeat'),
                  onPressed: _logging || items.isEmpty ? null : _repeat,
                  child: const Text('Repeat on set days…'),
                ),
              ],
              TextButton(
                onPressed: _logging ? null : _empty,
                child: Text(
                  widget.basket.planning != null
                      ? 'Clear the foods to plan'
                      : 'Empty the basket',
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
