import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:logging/logging.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/core/utils/meal_type_suggester.dart';
import 'package:opennutritracker/core/utils/tracked_day_lock.dart';
import 'package:opennutritracker/features/meal_detail/presentation/bloc/meal_detail_bloc.dart';
import 'package:opennutritracker/fork/basket/basket.dart';
import 'package:opennutritracker/fork/basket/basket_ui.dart';
import 'package:opennutritracker/fork/copy/copy_entries.dart';
import 'package:opennutritracker/fork/plan/plan_store.dart';
import 'package:opennutritracker/fork/units/energy_text.dart';
import 'package:opennutritracker/fork/display/display_prefs.dart';

final _log = Logger('PlannedFoodsCard');

/// Writes one planned food to the diary; upstream's meal detail add in
/// the app. What it wrote, or null when it was not written (a profile
/// switch).
typedef LogPlannedFood =
    Future<IntakeEntity?> Function(BuildContext context, PlannedFood food);

Future<IntakeEntity?> _logWithMealDetail(
  BuildContext context,
  PlannedFood food,
) => locator<MealDetailBloc>().addIntake(
  context,
  food.unit,
  food.amountText,
  food.type,
  food.meal,
  food.day,
);

Future<bool> _undoLog(Placed placed, ProfileStamp startedOn) =>
    CopyEntries.fromLocator().undoPlace(placed, startedOn: startedOn);

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

/// Of [foods], sorted by meal, those of the meal to eat next: the time's meal
/// or the first after it, else the first left (one that went past uneaten).
List<PlannedFood> upNextFoods(List<PlannedFood> foods, DateTime now) {
  if (foods.isEmpty) return const [];
  final at = MealTypeSuggester.suggestFromTime(now);
  // Dinner comes after the afternoon snack, though not in the enum.
  final afternoon = now.hour >= 15 && now.hour < 17;
  final next =
      (foods.where((f) => f.type.index >= at.index).firstOrNull ??
              foods
                  .where((f) => afternoon && f.type == IntakeTypeEntity.dinner)
                  .firstOrNull ??
              foods.first)
          .type;
  return [
    for (final f in foods)
      if (f.type == next) f,
  ];
}

/// Seam S43: a day's planned foods on Home and in the Diary, each logged
/// with a tick (on its planned day and meal) or dropped; "Log all" logs
/// the lot. Nothing when the day has no plan. With [showUpNext] (Home, for
/// today) the next meal leads, to log with one tap.
class PlannedFoodsCard extends StatefulWidget {
  final DateTime day;
  final PlanStore? store;
  final LogPlannedFood log;
  final Future<bool> Function(Placed placed, ProfileStamp startedOn) undoLog;
  final bool showUpNext;

  const PlannedFoodsCard({
    super.key,
    required this.day,
    this.store,
    this.showUpNext = false,
    this.log = _logWithMealDetail,
    this.undoLog = _undoLog,
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
    final messenger = ScaffoldMessenger.maybeOf(context);
    final startedOn = ProfileStamp.now();
    final logged = <PlannedFood>[];
    final written = <IntakeEntity>[];
    setState(() => _busy = true);
    try {
      for (final food in foods) {
        if (!mounted) break;
        final intake = await widget.log(context, food);
        // Not written (a profile switch): it and the rest stay planned.
        if (intake == null) break;
        await _store.remove(food.id);
        logged.add(food);
        written.add(intake);
      }
      refreshAfterLogging();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (logged.isEmpty) return;
    final undoLog = widget.undoLog;
    final meals = logged.map((f) => f.type).toSet();
    final to = [
      if (meals.length == 1) _typeName(meals.single),
      DateFormat.MMMEd().format(logged.first.day),
    ];
    _showWithUndo(
      messenger,
      'Logged${logged.length == 1 ? '' : ' ${logged.length} foods'} '
      'to ${to.join(', ')}',
      () async {
        final undone = await undoLog((
          day: logged.first.day,
          written: written,
        ), startedOn);
        if (undone) await _putBack(logged);
        refreshAfterLogging();
        return undone;
      },
    );
  }

  Future<void> _drop(PlannedFood food) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    await _store.remove(food.id);
    _showWithUndo(messenger, 'Dropped ${food.meal.name ?? 'food'}', () async {
      await _putBack([food]);
      return true;
    });
  }

  Future<void> _putBack(List<PlannedFood> foods) async {
    for (final food in foods) {
      await _store.putBack(food);
    }
  }

  void _showWithUndo(
    ScaffoldMessengerState? messenger,
    String text,
    Future<bool> Function() undo,
  ) {
    if (messenger == null) return;
    messenger.removeCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        // An action keeps a bar up until dismissed: this one goes.
        persist: false,
        content: Text(text),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () async {
            if (!await undo()) {
              messenger.showSnackBar(
                const SnackBar(
                  content: Text('Not undone: the profile changed.'),
                ),
              );
            }
          },
        ),
      ),
    );
  }

  Future<void> _repeat(PlannedFood food) async {
    final weekdays = await showDialog<Set<int>>(
      context: context,
      builder: (_) => RepeatDialog(
        name: food.meal.name ?? '',
        initial: food.repeats ? food.weekdays : {food.day.weekday},
        repeating: food.repeats,
      ),
    );
    if (weekdays != null) await _store.setRepeat(food.id, weekdays);
  }

  static String _grams(double value, String name) {
    final g = value.round();
    return '$g ${g == 1 ? 'gram' : 'grams'} $name';
  }

  static String _typeName(IntakeTypeEntity type) =>
      '${type.name[0].toUpperCase()}${type.name.substring(1)}';

  Widget _upNext(List<PlannedFood> foods) {
    final kcal = foods.fold<double>(0, (sum, f) => sum + f.kcal);
    return Row(
      children: [
        Expanded(
          child: Text(
            'Up next: ${_typeName(foods.first.type)} · '
            '${energyText(context, kcal)}',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        Semantics(
          identifier: 'plan-up-next-log',
          child: FilledButton.tonal(
            key: const ValueKey('plan-up-next-log'),
            onPressed: _busy ? null : () => _logAll(foods),
            child: const Text('Log it'),
          ),
        ),
      ],
    );
  }

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
                        Semantics(
                          container: true,
                          header: true,
                          child: Text(
                            'Planned · ${energyText(context, total)}',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        Text(
                          inMacroOrder(
                            protein: 'P ${macros.protein.round()} g',
                            carbs: 'C ${macros.carbs.round()} g',
                            fat: 'F ${macros.fat.round()} g',
                          ).join(' · '),
                          key: const ValueKey('plan-macros'),
                          semanticsLabel: inMacroOrder(
                            protein: _grams(macros.protein, 'protein'),
                            carbs: _grams(macros.carbs, 'carbs'),
                            fat: _grams(macros.fat, 'fat'),
                          ).join(', '),
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
              if (widget.showUpNext)
                _upNext(upNextFoods(foods, DateTime.now())),
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
                            ? 'Change how ${food.meal.name ?? 'it'} repeats'
                            : 'Repeat ${food.meal.name ?? 'it'}',
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
                        tooltip: 'Log ${food.meal.name ?? 'it'}',
                        icon: const Icon(Icons.check_circle_outline_rounded),
                        onPressed: _busy ? null : () => _logAll([food]),
                      ),
                      IconButton(
                        key: ValueKey('plan-drop-${food.id}'),
                        tooltip: food.repeats
                            ? 'Drop ${food.meal.name ?? 'it'} on this day'
                            : 'Drop ${food.meal.name ?? 'it'}',
                        icon: const Icon(Icons.close_rounded),
                        onPressed: _busy ? null : () => _drop(food),
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

/// Picks the weekdays [name] repeats on, from its planned day on, starting
/// from [initial]. Pops the days, an empty set to stop one [repeating], or
/// nothing on Cancel.
class RepeatDialog extends StatefulWidget {
  final String name;
  final Set<int> initial;
  final bool repeating;

  /// What the button that stops it says, when that does more than stop it.
  final String stopLabel;

  const RepeatDialog({
    super.key,
    required this.name,
    required this.initial,
    this.repeating = false,
    this.stopLabel = 'Stop repeating',
  });

  @override
  State<RepeatDialog> createState() => _RepeatDialogState();
}

class _RepeatDialogState extends State<RepeatDialog> {
  late final Set<int> _days = {...widget.initial};

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).toString();
    return AlertDialog(
      title: Text('Repeat ${widget.name}'),
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
              if (widget.repeating)
                TextButton(
                  key: const ValueKey('repeat-stop'),
                  onPressed: () => Navigator.pop(context, <int>{}),
                  child: Text(widget.stopLabel),
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
