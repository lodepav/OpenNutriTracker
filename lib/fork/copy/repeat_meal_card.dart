import 'dart:async';

import 'package:flutter/material.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/core/presentation/widgets/app_card.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/core/utils/meal_type_suggester.dart';
import 'package:opennutritracker/fork/copy/copy_entries.dart';
import 'package:opennutritracker/fork/copy/copy_ui.dart';
import 'package:opennutritracker/fork/history/history_file.dart';
import 'package:opennutritracker/fork/screens/home/home_loads.dart';
import 'package:opennutritracker/fork/units/energy_text.dart';

/// Seam S162: "Same lunch as yesterday" on Home, while the time's meal is
/// empty today and held something yesterday. A tap logs yesterday's foods
/// now, with Undo.
class RepeatMealCard extends StatefulWidget {
  /// Home's logical day and what it holds so far.
  final DateTime day;
  final List<IntakeEntity> today;
  final CopyEntries? copier;

  /// Home's loads, on which yesterday is read again; for tests, the app's
  /// from the HomeBloc.
  final Stream<Object?>? homeLoads;

  const RepeatMealCard({
    super.key,
    required this.day,
    required this.today,
    this.copier,
    this.homeLoads,
  });

  @override
  State<RepeatMealCard> createState() => _RepeatMealCardState();
}

class _RepeatMealCardState extends State<RepeatMealCard> {
  late final _copier = widget.copier ?? CopyEntries.fromLocator();
  late var _yesterday = _load();
  bool _busy = false;

  Future<(Map<String, int>, List<IntakeEntity>)> _load() async {
    final config = await locator<GetConfigUsecase>().getConfig();
    final day = widget.day;
    return (
      config.mealKcalSharesPct,
      await _copier.intakesOf(DateTime(day.year, day.month, day.day - 1)),
    );
  }

  // Read again on each Home load (the Diary may have changed yesterday)
  // and on a new day, not on every rebuild of Home.
  late final StreamSubscription<Object?> _homeLoads;

  @override
  void initState() {
    super.initState();
    _homeLoads = (widget.homeLoads ?? homeLoads()).listen(
      (_) => setState(() {
        _yesterday = _load();
      }),
    );
  }

  @override
  void didUpdateWidget(RepeatMealCard old) {
    super.didUpdateWidget(old);
    if (!DateUtils.isSameDay(old.day, widget.day)) _yesterday = _load();
  }

  @override
  void dispose() {
    _homeLoads.cancel();
    super.dispose();
  }

  Future<void> _repeat(List<IntakeEntity> foods, IntakeTypeEntity meal) async {
    setState(() => _busy = true);
    try {
      await placeWithUndo(
        context,
        foods,
        CopyAt(DateTime.now()),
        meal: meal,
        copier: _copier,
        verb: 'Logged',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: _yesterday,
    builder: (context, snapshot) {
      final loaded = snapshot.data;
      if (loaded == null) return const SizedBox.shrink();
      final (shares, yesterday) = loaded;
      final meal = MealTypeSuggester.suggestFromTime(
        DateTime.now(),
        mealSharesPct: shares,
      );
      final foods = [
        for (final intake in yesterday)
          if (intake.type == meal && !isImportedHistory(intake)) intake,
      ];
      if (foods.isEmpty || widget.today.any((i) => i.type == meal)) {
        return const SizedBox.shrink();
      }
      final kcal = foods.fold<double>(0, (sum, f) => sum + f.totalKcal);
      final count = foods.length == 1 ? '1 food' : '${foods.length} foods';
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: AppCard(
          child: ListTile(
            leading: const Icon(Icons.replay_rounded),
            title: Text(
              'Same ${mealLabel(context, meal).toLowerCase()} as yesterday',
            ),
            subtitle: Text('$count · ${energyText(context, kcal)}'),
            trailing: Semantics(
              identifier: 'home-repeat-meal-log',
              child: FilledButton.tonal(
                key: const ValueKey('home-repeat-meal-log'),
                onPressed: _busy ? null : () => _repeat(foods, meal),
                child: const Text('Log it'),
              ),
            ),
          ),
        ),
      );
    },
  );
}
