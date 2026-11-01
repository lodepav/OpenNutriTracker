import 'package:flutter/material.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_intake_usecase.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/core/utils/meal_type_suggester.dart';
import 'package:opennutritracker/fork/copy/copy_entries.dart';
import 'package:opennutritracker/fork/copy/copy_ui.dart';
import 'package:opennutritracker/fork/recents/recents_by_meal.dart';
import 'package:opennutritracker/fork/units/amount_text.dart';
import 'package:opennutritracker/fork/units/energy_text.dart';

/// How many foods the list holds; the rest are a search away.
const recentFoodsShown = 10;

/// The time's meal and its recent foods, best first.
typedef RecentFoods = ({
  IntakeTypeEntity meal,
  List<IntakeEntity> foods,
  bool imperial,
});

Future<RecentFoods> _load() async {
  final config = await locator<GetConfigUsecase>().getConfig();
  final meal = MealTypeSuggester.suggestFromTime(
    DateTime.now(),
    mealSharesPct: config.mealKcalSharesPct,
  );
  final foods = await recentsForMeal(
    await locator<GetIntakeUsecase>().getRecentIntake(),
    meal,
  );
  return (
    meal: meal,
    foods: foods.take(recentFoodsShown).toList(),
    imperial: config.usesImperialFoodUnits,
  );
}

/// Logs [food] again now, at its last amount, into [meal]; with Undo.
Future<void> _log(
  BuildContext context,
  IntakeEntity food,
  IntakeTypeEntity meal,
) => placeWithUndo(
  context,
  [food],
  CopyAt(DateTime.now()),
  meal: meal,
  verb: 'Logged',
);

/// Seam S162: Home's recent foods, collapsed until opened. A tap logs a food
/// at its last amount into the time's meal, which the list names. The foods
/// are read on each opening. It stays open when Home reloads after a log (the
/// storage key), so a second food takes one more tap.
class RecentFoodsCard extends StatelessWidget {
  final Future<RecentFoods> Function() load;
  final Future<void> Function(BuildContext, IntakeEntity, IntakeTypeEntity) log;

  const RecentFoodsCard({super.key, this.load = _load, this.log = _log});

  @override
  Widget build(BuildContext context) => Card(
    key: const PageStorageKey('home-recent-foods-card'),
    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    clipBehavior: Clip.antiAlias,
    child: Semantics(
      identifier: 'home-recent-foods',
      child: ExpansionTile(
        key: const ValueKey('home-recent-foods'),
        leading: const Icon(Icons.history_rounded),
        title: const Text('Recent foods'),
        shape: const Border(),
        // A closed tile drops its children, so each opening reads anew.
        children: [_RecentFoodsList(load: load, log: log)],
      ),
    ),
  );
}

class _RecentFoodsList extends StatefulWidget {
  final Future<RecentFoods> Function() load;
  final Future<void> Function(BuildContext, IntakeEntity, IntakeTypeEntity) log;

  const _RecentFoodsList({required this.load, required this.log});

  @override
  State<_RecentFoodsList> createState() => _RecentFoodsListState();
}

class _RecentFoodsListState extends State<_RecentFoodsList> {
  late final _recent = widget.load();
  bool _busy = false;

  Future<void> _logFood(IntakeEntity food, IntakeTypeEntity meal) async {
    setState(() => _busy = true);
    try {
      await widget.log(context, food, meal);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<RecentFoods>(
    future: _recent,
    builder: (context, snapshot) {
      final recent = snapshot.data;
      if (snapshot.hasError) {
        return const ListTile(title: Text('Recent foods could not be read.'));
      }
      if (recent == null) return const SizedBox(height: 48);
      if (recent.foods.isEmpty) {
        return const ListTile(title: Text('Foods you log will show here.'));
      }
      final mealName = mealLabel(context, recent.meal);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Text(
              'Tap a food to log it to $mealName',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          for (final (i, food) in recent.foods.indexed)
            ListTile(
              key: ValueKey('home-recent-$i'),
              dense: true,
              enabled: !_busy,
              title: Text(food.meal.name ?? ''),
              subtitle: Text(
                isEnergyOnly(food.meal)
                    ? energyText(context, food.totalKcal)
                    : '${amountText(food, recent.imperial)} · '
                          '${energyText(context, food.totalKcal)}',
              ),
              trailing: const Icon(Icons.add_rounded),
              onTap: () => _logFood(food, recent.meal),
            ),
        ],
      );
    },
  );
}
