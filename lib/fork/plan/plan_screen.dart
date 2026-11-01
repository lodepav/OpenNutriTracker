import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/utils/navigation_options.dart';
import 'package:opennutritracker/features/add_meal/presentation/add_meal_screen.dart';
import 'package:opennutritracker/features/add_meal/presentation/add_meal_type.dart';
import 'package:opennutritracker/fork/basket/basket.dart';
import 'package:opennutritracker/fork/copy/copy_ui.dart';
import 'package:opennutritracker/fork/plan/plan_store.dart';
import 'package:opennutritracker/fork/plan/plan_ui.dart';

/// How many days ahead, today included, the screen offers.
const planDaysAhead = 14;

/// Opens search for [meal] on [day] with the basket planning as [mode].
/// Search logs nothing meanwhile (`FoodBasket.planning`); what was picked and
/// not planned goes when it closes, so it cannot be logged later by mistake.
/// A basket already being filled for the diary waits, and comes back then.
Future<void> _pickFoods(
  BuildContext context,
  IntakeTypeEntity meal,
  DateTime day,
  PlanMode mode,
) async {
  final basket = FoodBasket.instance;
  final putBack = basket.setAside();
  basket.planning = mode;
  try {
    await Navigator.of(context).pushNamed(
      NavigationOptions.addMealRoute,
      arguments: AddMealScreenArguments(
        AddMealExtension.fromIntakeTypeEntity(meal),
        day,
      ),
    );
  } finally {
    basket.planning = null;
    putBack();
  }
}

/// The meal plan: what is planned on the days ahead, adding to them, and the
/// foods that repeat. Reached from Home's quick actions.
class MealPlanScreen extends StatefulWidget {
  /// The logical day it opens on; found from the settings when null.
  final DateTime? today;
  final PlanStore? store;
  final Future<void> Function(
    BuildContext,
    IntakeTypeEntity,
    DateTime,
    PlanMode,
  )
  pickFoods;

  const MealPlanScreen({
    super.key,
    this.today,
    this.store,
    this.pickFoods = _pickFoods,
  });

  @override
  State<MealPlanScreen> createState() => _MealPlanScreenState();
}

class _MealPlanScreenState extends State<MealPlanScreen> {
  late final _store = widget.store ?? PlanStore();
  late final Future<DateTime> _today = widget.today != null
      ? Future.value(widget.today)
      : logicalToday();
  late Future<List<PlannedFood>> _foods = _store.all();
  DateTime? _picked;

  @override
  void initState() {
    super.initState();
    PlanStore.changes.addListener(_reload);
  }

  @override
  void dispose() {
    PlanStore.changes.removeListener(_reload);
    super.dispose();
  }

  void _reload() {
    if (!mounted) return;
    setState(() {
      _foods = _store.all();
    });
  }

  Future<void> _add(DateTime day, PlanMode mode) async {
    final meal = await showModalBottomSheet<IntakeTypeEntity>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final type in IntakeTypeEntity.values)
              ListTile(
                key: ValueKey('plan-meal-${type.name}'),
                leading: Icon(type.getIconData()),
                title: Text(mealLabel(context, type)),
                onTap: () => Navigator.pop(context, type),
              ),
          ],
        ),
      ),
    );
    if (meal == null || !mounted) return;
    await widget.pickFoods(context, meal, day, mode);
  }

  /// Changes the days [food] repeats on; none left drops it for good.
  Future<void> _editRepeat(PlannedFood food) async {
    final weekdays = await showDialog<Set<int>>(
      context: context,
      builder: (_) => RepeatDialog(
        name: food.meal.name ?? '',
        initial: food.weekdays,
        repeating: true,
        stopLabel: 'Remove',
      ),
    );
    if (weekdays == null) return;
    if (weekdays.isEmpty) {
      await _store.remove(food.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          // An action keeps a bar up until dismissed: this one goes.
          persist: false,
          content: Text('Removed ${food.meal.name ?? 'food'}'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => _store.putBack(food),
          ),
        ),
      );
    } else {
      await _store.setRepeat(food.id, weekdays);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Meal plan')),
    body: FutureBuilder<DateTime>(
      future: _today,
      builder: (context, today) {
        final first = today.data;
        if (first == null) return const SizedBox.shrink();
        final day = _picked ?? first;
        return ListView(
          padding: const EdgeInsets.only(bottom: 48),
          children: [
            _days(first, day),
            _nothingPlanned(day),
            PlannedFoodsCard(key: ValueKey(day), day: day, store: _store),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Semantics(
                    identifier: 'plan-add-foods',
                    child: FilledButton.icon(
                      key: const ValueKey('plan-add-foods'),
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Plan foods'),
                      onPressed: () => _add(day, PlanMode.once),
                    ),
                  ),
                  Semantics(
                    identifier: 'plan-add-recurring',
                    child: OutlinedButton.icon(
                      key: const ValueKey('plan-add-recurring'),
                      icon: const Icon(Icons.repeat_rounded),
                      label: const Text('Add recurring meal'),
                      onPressed: () => _add(day, PlanMode.recurring),
                    ),
                  ),
                ],
              ),
            ),
            FutureBuilder<List<PlannedFood>>(
              future: _foods,
              builder: (context, foods) => _recurring([
                for (final food in foods.data ?? const <PlannedFood>[])
                  if (food.repeats) food,
              ]),
            ),
          ],
        );
      },
    ),
  );

  Widget _days(DateTime first, DateTime day) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
    child: Row(
      spacing: 8,
      children: [
        for (var i = 0; i < planDaysAhead; i++)
          () {
            final date = DateTime(first.year, first.month, first.day + i);
            return ChoiceChip(
              key: ValueKey('plan-day-$i'),
              label: Text(i == 0 ? 'Today' : DateFormat.MMMEd().format(date)),
              selected: DateUtils.isSameDay(date, day),
              onSelected: (_) => setState(() => _picked = date),
            );
          }(),
      ],
    ),
  );

  /// Said only once the day is known to be empty; the card then shows nothing.
  Widget _nothingPlanned(DateTime day) => FutureBuilder<List<PlannedFood>>(
    // forDay and not [_foods]: it works out a repeating food's days.
    future: _store.forDay(day),
    builder: (context, planned) => planned.data?.isEmpty ?? false
        ? const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text('Nothing planned for this day.'),
          )
        : const SizedBox.shrink(),
  );

  Widget _recurring(List<PlannedFood> foods) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: Semantics(
          container: true,
          header: true,
          child: Text(
            'Recurring meals',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
      ),
      if (foods.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'Foods that repeat on set days show here, and on those days '
            'are planned for you to log.',
          ),
        ),
      for (final food in foods)
        ListTile(
          key: ValueKey('plan-recurring-${food.id}'),
          title: Text(food.meal.name ?? ''),
          subtitle: Text(
            '${mealLabel(context, food.type)} · '
            '${repeatText(context, food.weekdays)}',
          ),
          trailing: const Icon(Icons.edit_outlined),
          onTap: () => _editRepeat(food),
        ),
    ],
  );
}
