import 'package:flutter/material.dart';
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
                    '${food.unit} · ${energyText(context, food.kcal)}',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        key: ValueKey('plan-log-${food.id}'),
                        tooltip: 'Log it',
                        icon: const Icon(Icons.check_circle_outline_rounded),
                        onPressed: _busy ? null : () => _logAll([food]),
                      ),
                      IconButton(
                        key: ValueKey('plan-drop-${food.id}'),
                        tooltip: 'Drop it',
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
