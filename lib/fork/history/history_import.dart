import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:opennutritracker/core/data/repository/intake_repository.dart';
import 'package:opennutritracker/core/data/repository/tracked_day_repository.dart';
import 'package:opennutritracker/core/data/repository/weight_log_repository.dart';
import 'package:opennutritracker/core/domain/entity/body_weight_unit_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/domain/entity/weight_log_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/core/utils/calc/day_boundary_calc.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/core/utils/tracked_day_lock.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/fork/basket/basket_ui.dart';
import 'package:opennutritracker/fork/copy/copy_entries.dart';
import 'package:opennutritracker/fork/health/weight_import_ui.dart';
import 'package:opennutritracker/fork/history/history_file.dart';
import 'package:opennutritracker/fork/history/table_reader.dart';

/// What an import writes, and what it keeps of the app's own.
class HistoryPlan {
  /// The new entries by logical day: one per meal of a day, or one for the
  /// day's total where the file has no meals.
  final Map<DateTime, List<IntakeEntity>> intakes;
  final List<WeightLogEntity> weights;

  /// Days of the file already logged here, and weigh-ins already here:
  /// the app's own are never replaced or added to.
  final int keptDays;
  final int keptWeighIns;

  const HistoryPlan({
    required this.intakes,
    required this.weights,
    required this.keptDays,
    required this.keptWeighIns,
  });

  bool get isEmpty => intakes.isEmpty && weights.isEmpty;
}

/// The plan for [file]: its days not logged here ([loggedDays]) and its
/// weigh-ins on days with none ([weighedDays]), up to [today]. Entries are
/// quick-add style (the totals as per 100 g of a 100 g entry), date-only so
/// any day start keeps them on their day, under ids made from the day and
/// meal, so a second import of the same file adds nothing.
HistoryPlan planImport(
  HistoryFile file, {
  required Set<DateTime> loggedDays,
  required Set<DateTime> weighedDays,
  required DateTime today,
  required String source,
}) {
  final intakes = <DateTime, List<IntakeEntity>>{};
  var keptDays = 0;
  for (final MapEntry(key: day, value: meals) in file.food.entries) {
    if (day.isAfter(today)) continue;
    if (loggedDays.contains(day)) {
      keptDays++;
      continue;
    }
    intakes[day] = [
      for (final MapEntry(key: type, value: totals) in meals.entries)
        _intake(day, type, totals, source),
    ];
  }
  var keptWeighIns = 0;
  final weights = <WeightLogEntity>[];
  for (final MapEntry(key: day, value: kg) in file.weightsKg.entries) {
    if (day.isAfter(today)) continue;
    if (weighedDays.contains(day)) {
      keptWeighIns++;
      continue;
    }
    weights.add(WeightLogEntity(date: day, weightKg: kg));
  }
  return HistoryPlan(
    intakes: intakes,
    weights: weights,
    keptDays: keptDays,
    keptWeighIns: keptWeighIns,
  );
}

IntakeEntity _intake(
  DateTime day,
  IntakeTypeEntity? type,
  FoodTotals totals,
  String source,
) {
  final key = '${DateFormat('yyyy-MM-dd').format(day)}-${type?.name ?? 'day'}';
  return IntakeEntity(
    id: '$historyCodePrefix$key',
    unit: 'g',
    amount: 100,
    type: type ?? IntakeTypeEntity.snack,
    meal: MealEntity(
      code: '$historyCodePrefix$key',
      name: type == null ? 'Day logged in $source' : 'Logged in $source',
      url: null,
      mealQuantity: '100',
      mealUnit: 'gml',
      servingQuantity: null,
      servingUnit: 'gml',
      servingSize: '',
      nutriments: MealNutrimentsEntity(
        energyKcal100: totals.kcal,
        carbohydrates100: totals.carbs,
        fat100: totals.fat,
        proteins100: totals.protein,
        sugars100: null,
        saturatedFat100: null,
        fiber100: null,
      ),
      // Not custom: Settings' custom meals would list every day, and their
      // merge and edit would rewrite the history.
      source: MealSourceEntity.unknown,
    ),
    // Date-only, as an import's entry is: its day under any day start.
    dateTime: DateTime(day.year, day.month, day.day),
  );
}

/// Days already logged in the active profile (a tracked day with calories,
/// or an entry) and days already weighed.
Future<({Set<DateTime> logged, Set<DateTime> weighed})> _existing() async {
  DateTime date(DateTime d) => DateTime(d.year, d.month, d.day);
  final offset = (await locator<GetConfigUsecase>().getConfig())
      .dayStartOffsetTotalMinutes;
  return (
    logged: {
      for (final t
          in await locator<TrackedDayRepository>().getAllTrackedDaysDBO())
        if (t.caloriesTracked > 0) date(t.day),
      for (final i in await locator<IntakeRepository>().getAllIntakesDBO())
        date(DayBoundaryCalc.dayLabelOf(i.dateTime, offset)),
    },
    weighed: {
      for (final w in await locator<WeightLogRepository>().getAllEntries())
        date(w.date),
    },
  );
}

/// Writes [plan] under the tracked-day lock: each day's entries and their
/// totals as a logged entry adds them, then the weigh-ins. Only into the
/// profile [startedOn] names, which [plan] was made against: false, and
/// nothing written, after a profile switch.
Future<bool> writeHistory(HistoryPlan plan, ProfileStamp startedOn) async {
  final written = await withTrackedDayLockOnProfile(
    startedOn: startedOn,
    () async {
      final writer = CopyEntries.fromLocator();
      for (final MapEntry(key: day, value: intakes) in plan.intakes.entries) {
        await writer.restoreIntakes(intakes, day);
      }
      final weights = locator<WeightLogRepository>();
      for (final weight in plan.weights) {
        await weights.addEntry(weight);
      }
      return true;
    },
  );
  if (written == null) return false;
  refreshAfterLogging();
  if (plan.weights.isNotEmpty) refreshAfterWeightImport();
  return true;
}

/// "Import history" in Settings' data section (seam S51): food totals and
/// weigh-ins from another app's export, so the trend and the expenditure
/// estimate start from months of history.
class HistoryImportTile extends StatelessWidget {
  const HistoryImportTile({super.key});

  @override
  Widget build(BuildContext context) => ListTile(
    key: const ValueKey('fork-history-import'),
    leading: const Icon(Icons.history_outlined),
    title: const Text('Import history'),
    subtitle: const Text(
      'Daily food and weigh-ins from MacroFactor, MyFitnessPal, Cronometer '
      'or a spreadsheet (CSV, XLSX or ZIP)',
    ),
    onTap: () => _run(context),
  );

  Future<void> _run(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    void say(String text) =>
        messenger.showSnackBar(SnackBar(content: Text(text)));
    final picked = await FilePicker.pickFile(type: FileType.any);
    final path = picked?.path;
    if (path == null) return;
    final List<SheetTable> tables;
    try {
      tables = readTables(picked!.name, await File(path).readAsBytes());
    } catch (_) {
      say('Could not read ${picked!.name}');
      return;
    }
    // What is already here is read from this profile: the plan is written
    // only into it.
    final startedOn = ProfileStamp.now();
    final config = await locator<GetConfigUsecase>().getConfig();
    final existing = await _existing();
    final now = DateTime.now();
    final source = picked.name.replaceFirst(RegExp(r'\.[^.]*$'), '');
    HistoryPlan plan(HistoryFile file) => planImport(
      file,
      loggedDays: existing.logged,
      weighedDays: existing.weighed,
      today: DateTime(now.year, now.month, now.day),
      source: source,
    );
    final unit = config.bodyWeightUnit == BodyWeightUnit.kg
        ? BodyWeightUnit.kg
        : BodyWeightUnit.lb;
    final first = readHistory(tables, unit: unit);
    if (first.isEmpty) {
      say('No days with calories or weight found in ${picked.name}');
      return;
    }
    if (!context.mounted) return;
    final chosen = await showDialog<HistoryPlan>(
      context: context,
      builder: (_) => HistoryImportDialog(
        file: first,
        reread: (unit) => readHistory(tables, unit: unit),
        plan: plan,
      ),
    );
    if (chosen == null) return;
    try {
      if (!await writeHistory(chosen, startedOn)) {
        say('Nothing was imported: the profile changed.');
        return;
      }
      say(
        'Imported ${chosen.intakes.length} days of food and '
        '${chosen.weights.length} weigh-ins.',
      );
    } catch (_) {
      say('The import stopped partway; what was written stays.');
    }
  }
}

/// The preview: what was found where, what is kept, and the weight unit
/// when the file does not say it.
class HistoryImportDialog extends StatefulWidget {
  final HistoryFile file;
  final HistoryFile Function(BodyWeightUnit unit) reread;
  final HistoryPlan Function(HistoryFile file) plan;

  const HistoryImportDialog({
    super.key,
    required this.file,
    required this.reread,
    required this.plan,
  });

  @override
  State<HistoryImportDialog> createState() => _HistoryImportDialogState();
}

class _HistoryImportDialogState extends State<HistoryImportDialog> {
  late var _file = widget.file;
  late var _plan = widget.plan(_file);

  static final _date = DateFormat.yMMMd();

  String _span(Iterable<DateTime> days) {
    final sorted = days.toList()..sort();
    return '${_date.format(sorted.first)} – ${_date.format(sorted.last)}';
  }

  @override
  Widget build(BuildContext context) {
    final file = _file;
    final plan = _plan;
    return AlertDialog(
      title: const Text('Import history'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (file.food.isEmpty)
              const Text('No food found.')
            else
              Text(
                'Food from "${file.foodTable}": ${plan.intakes.length} days '
                'to add${plan.intakes.isEmpty ? '' : ', ${_span(plan.intakes.keys)}'}.',
                key: const ValueKey('history-food'),
              ),
            const SizedBox(height: 8),
            if (file.weightsKg.isEmpty)
              const Text('No weigh-ins found.')
            else
              Text(
                'Weigh-ins from "${file.weightTable}": '
                '${plan.weights.length} to add'
                '${plan.weights.isEmpty ? '' : ', ${_span(plan.weights.map((w) => w.date))}'}.',
                key: const ValueKey('history-weights'),
              ),
            if (file.weightsKg.isNotEmpty && !file.weightUnitStated) ...[
              const SizedBox(height: 8),
              const Text('The file does not say the weight unit:'),
              const SizedBox(height: 4),
              SegmentedButton<BodyWeightUnit>(
                key: const ValueKey('history-unit'),
                segments: const [
                  ButtonSegment(value: BodyWeightUnit.kg, label: Text('kg')),
                  ButtonSegment(value: BodyWeightUnit.lb, label: Text('lb')),
                ],
                selected: {file.weightUnit},
                onSelectionChanged: (s) {
                  final file = widget.reread(s.single);
                  setState(() {
                    _file = file;
                    _plan = widget.plan(file);
                  });
                },
              ),
            ],
            if (plan.keptDays > 0 || plan.keptWeighIns > 0) ...[
              const SizedBox(height: 8),
              Text(
                'Kept as they are here: ${plan.keptDays} days already '
                'logged, ${plan.keptWeighIns} weigh-ins already entered.',
              ),
            ],
            const SizedBox(height: 8),
            const Text(
              'Each day comes in as its totals (one entry a meal, or one for '
              'the day), not food by food.',
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('history-import'),
          onPressed: plan.isEmpty
              ? null
              : () => Navigator.of(context).pop(plan),
          child: const Text('Import'),
        ),
      ],
    );
  }
}
