import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:logging/logging.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/meal_detail/presentation/bloc/meal_detail_bloc.dart';
import 'package:opennutritracker/fork/basket/basket.dart';
import 'package:opennutritracker/fork/basket/basket_ui.dart';
import 'package:opennutritracker/fork/plan/plan_store.dart';
import 'package:opennutritracker/fork/units/energy_text.dart';
import 'package:opennutritracker/fork/display/display_prefs.dart';

final _log = Logger('PlannedFoodsCard');

/// Writes one planned food to the diary; upstream's meal detail add in
/// the app. False when it was not written (a profile switch).
typedef LogPlannedFood =
    Future<bool> Function(BuildContext context, PlannedFood food);

Future<bool> _logWithMealDetail(BuildContext context, PlannedFood food) async =>
    await locator<MealDetailBloc>().addIntake(
      context,
      food.unit,
      food.amountText,
      food.type,
      food.meal,
      food.day,
    ) !=
    null;

/// Protein, carbs and fat of [foods] in grams: each food's planned energy
/// split by its figures per 100 (both scale with the amount alike); a food
/// without an energy figure counts none.
({double protein, double carbs, double fat}) plannedMacros(
  List<PlannedFood> foods,
) {
  var protein = 0.0, carbs = 0.0, fat = 0.0;
  for (final f in foods) {
    final n = f.meal.nutriments;
    final energy = n.energyKcal100;
    if (energy == null || energy <= 0) continue;
    protein += f.kcal * (n.proteins100 ?? 0) / energy;
    carbs += f.kcal * (n.carbohydrates100 ?? 0) / energy;
    fat += f.kcal * (n.fat100 ?? 0) / energy;
  }
  return (protein: protein, carbs: carbs, fat: fat);
}

/// Seam S43: a day's planned foods on Home and in the Diary, each logged
/// with a tick (on its planned day and meal) or dropped; "Log all" logs
/// the lot. Nothing when the day has no plan.
class PlannedFoodsCard extends StatefulWidget {
  final DateTime day;
  final PlanStore? store;
  final LogPlannedFood log;

  const PlannedFoodsCard({
    super.key,
    required this.day,
    this.store,
    this.log = _logWithMealDetail,
  });

  @override
  State<PlannedFoodsCard> createState() => _PlannedFoodsCardState();
}

class _PlannedFoodsCardState extends State<PlannedFoodsCard> {
  late final _store = widget.store ?? PlanStore();
  late Future<List<PlannedFood>> _foods = _load();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    PlanStore.changes.addListener(_reload);
  }

  @override
  void didUpdateWidget(PlannedFoodsCard old) {
    super.didUpdateWidget(old);
    if (old.day != widget.day) _reload();
  }

  @override
  void dispose() {
    PlanStore.changes.removeListener(_reload);
    super.dispose();
  }

  /// An unreadable plan shows nothing rather than breaking the day.
  Future<List<PlannedFood>> _load() =>
      _store.forDay(widget.day).catchError((Object e) {
        _log.warning('Meal plan unreadable: $e');
        return <PlannedFood>[];
      });

  void _reload() {
    if (!mounted) return;
    setState(() {
      _foods = _load();
    });
  }

  Future<void> _logAll(List<PlannedFood> foods) async {
    setState(() => _busy = true);
    try {
      for (final food in foods) {
        if (!mounted) return;
        // Not written (a profile switch): it and the rest stay planned.
        if (!await widget.log(context, food)) break;
        await _store.remove(food.id);
      }
      refreshAfterLogging();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _repeat(PlannedFood food) async {
    final weekdays = await showDialog<Set<int>>(
      context: context,
      builder: (_) => RepeatDialog(food: food),
    );
    if (weekdays != null) await _store.setRepeat(food.id, weekdays);
  }

  static String _typeName(IntakeTypeEntity type) =>
      '${type.name[0].toUpperCase()}${type.name.substring(1)}';

  @override
  Widget build(BuildContext context) => FutureBuilder<List<PlannedFood>>(
    future: _foods,
    builder: (context, snapshot) {
      final foods = [...?snapshot.data]
        ..sort((a, b) => a.type.index.compareTo(b.type.index));
      if (foods.isEmpty) return const SizedBox.shrink();
      final total = foods.fold<double>(0, (sum, f) => sum + f.kcal);
      final macros = plannedMacros(foods);
      return Card(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.event_note_rounded),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Planned · ${energyText(context, total)}',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(
                          inMacroOrder(
                            protein: 'P ${macros.protein.round()} g',
                            carbs: 'C ${macros.carbs.round()} g',
                            fat: 'F ${macros.fat.round()} g',
                          ).join(' · '),
                          key: const ValueKey('plan-macros'),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    key: const ValueKey('plan-log-all'),
                    onPressed: _busy ? null : () => _logAll(foods),
                    child: const Text('Log all'),
                  ),
                ],
              ),
              for (final food in foods)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(food.meal.name ?? ''),
                  subtitle: Text(
                    '${_typeName(food.type)} · ${amountLabel(food.amountText)} '
                    '${food.unit} · ${energyText(context, food.kcal)}'
                    '${food.repeats ? '\n${repeatText(context, food.weekdays)}' : ''}',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        key: ValueKey('plan-repeat-${food.id}'),
                        tooltip: food.repeats
                            ? 'Change how it repeats'
                            : 'Repeat it',
                        icon: Icon(
                          Icons.repeat_rounded,
                          color: food.repeats
                              ? Theme.of(context).colorScheme.primary
                              : null,
                        ),
                        onPressed: _busy ? null : () => _repeat(food),
                      ),
                      IconButton(
                        key: ValueKey('plan-log-${food.id}'),
                        tooltip: 'Log it',
                        icon: const Icon(Icons.check_circle_outline_rounded),
                        onPressed: _busy ? null : () => _logAll([food]),
                      ),
                      IconButton(
                        key: ValueKey('plan-drop-${food.id}'),
                        tooltip: food.repeats ? 'Drop it today' : 'Drop it',
                        icon: const Icon(Icons.close_rounded),
                        onPressed: _busy ? null : () => _store.remove(food.id),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}

/// "Every day", "Weekdays", or the days by name: "Mon, Wed, Fri".
String repeatText(BuildContext context, Set<int> weekdays) =>
    repeatTextFor(Localizations.localeOf(context).toString(), weekdays);

String repeatTextFor(String locale, Set<int> weekdays) {
  if (weekdays.length == 7) return 'Repeats every day';
  if (weekdays.length == 5 && !weekdays.contains(6) && !weekdays.contains(7)) {
    return 'Repeats on weekdays';
  }
  // 2024-01-01 was a Monday: day d of that week is weekday d.
  final names = [
    for (final d in weekdays.toList()..sort())
      DateFormat.E(locale).format(DateTime(2024, 1, d)),
  ];
  return 'Repeats ${names.join(', ')}';
}

/// Picks the weekdays [food] repeats on, from its planned day on. Pops
/// the days, an empty set to stop it repeating, or nothing on Cancel.
class RepeatDialog extends StatefulWidget {
  final PlannedFood food;

  const RepeatDialog({super.key, required this.food});

  @override
  State<RepeatDialog> createState() => _RepeatDialogState();
}

class _RepeatDialogState extends State<RepeatDialog> {
  late final Set<int> _days = widget.food.repeats
      ? {...widget.food.weekdays}
      : {widget.food.day.weekday};

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).toString();
    return AlertDialog(
      title: Text('Repeat ${widget.food.meal.name ?? ''}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Planned on these days until you log or drop it. Each day is '
            'logged on its own.',
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (var d = 1; d <= 7; d++)
                FilterChip(
                  key: ValueKey('repeat-day-$d'),
                  label: Text(
                    DateFormat.E(locale).format(DateTime(2024, 1, d)),
                  ),
                  selected: _days.contains(d),
                  onSelected: (on) =>
                      setState(() => on ? _days.add(d) : _days.remove(d)),
                ),
            ],
          ),
          Wrap(
            spacing: 8,
            children: [
              TextButton(
                key: const ValueKey('repeat-every-day'),
                onPressed: () =>
                    setState(() => _days.addAll([1, 2, 3, 4, 5, 6, 7])),
                child: const Text('Every day'),
              ),
              if (widget.food.repeats)
                TextButton(
                  key: const ValueKey('repeat-stop'),
                  onPressed: () => Navigator.pop(context, <int>{}),
                  child: const Text('Stop repeating'),
                ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          key: const ValueKey('repeat-save'),
          onPressed: _days.isEmpty
              ? null
              : () => Navigator.pop(context, {..._days}),
          child: const Text('Repeat'),
        ),
      ],
    );
  }
}
