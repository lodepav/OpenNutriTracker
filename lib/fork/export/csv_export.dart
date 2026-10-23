import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:opennutritracker/core/data/repository/intake_repository.dart';
import 'package:opennutritracker/core/data/repository/tracked_day_repository.dart';
import 'package:opennutritracker/core/data/repository/weight_log_repository.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/tracked_day_entity.dart';
import 'package:opennutritracker/core/domain/entity/weight_log_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/core/utils/calc/day_boundary_calc.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_service.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// One CSV field: quoted when it holds a comma, a quote or a line break.
String csvField(Object? value) {
  final text = switch (value) {
    null => '',
    double v => v.toStringAsFixed(v == v.roundToDouble() ? 0 : 1),
    _ => '$value',
  };
  return text.contains(RegExp('[",\r\n]'))
      ? '"${text.replaceAll('"', '""')}"'
      : text;
}

String _csv(List<List<Object?>> rows) =>
    '${rows.map((row) => row.map(csvField).join(',')).join('\r\n')}\r\n';

final _date = DateFormat('yyyy-MM-dd');
final _time = DateFormat('HH:mm');

/// Every diary entry, oldest first, on its logical day (the day start
/// offset applied), with energy in kcal and the rest in grams, sodium in mg.
String foodsCsv(List<IntakeEntity> intakes, int offsetMinutes) {
  final sorted = [...intakes]..sort((a, b) => a.dateTime.compareTo(b.dateTime));
  return _csv([
    [
      'date',
      'time',
      'meal',
      'food',
      'amount',
      'unit',
      'kcal',
      'protein_g',
      'carbs_g',
      'fat_g',
      'fibre_g',
      'sugar_g',
      'saturated_fat_g',
      'sodium_mg',
    ],
    for (final i in sorted)
      () {
        final n = i.meal.nutriments;
        double? total(double? per100) =>
            per100 == null ? null : i.amount * per100 / 100;
        final at = i.dateTime;
        final noTime = at.hour == 0 && at.minute == 0 && at.second == 0;
        return [
          _date.format(DayBoundaryCalc.logicalDayOfMinutes(at, offsetMinutes)),
          noTime ? null : _time.format(at),
          i.type.name,
          i.meal.name,
          i.amount,
          i.unit,
          i.totalKcal,
          i.totalProteinsGram,
          i.totalCarbsGram,
          i.totalFatsGram,
          total(n.fiber100),
          total(n.sugars100),
          total(n.saturatedFat100),
          total(n.sodium100),
        ];
      }(),
  ]);
}

/// One row per day that has a tracked day, a weigh-in or an expenditure
/// estimate, oldest first: what was eaten against the goals, the weight
/// logged, and the estimated expenditure.
String daysCsv({
  required List<TrackedDayEntity> trackedDays,
  required List<WeightLogEntity> weights,
  required List<ExpenditureDay> expenditure,
}) {
  String key(DateTime d) => _date.format(d);
  final tracked = {for (final t in trackedDays) key(t.day): t};
  final weight = {for (final w in weights) key(w.date): w.weightKg};
  final spent = {for (final e in expenditure) key(e.date): e.expenditureKcal};
  final days = {...tracked.keys, ...weight.keys, ...spent.keys}.toList()
    ..sort();
  return _csv([
    [
      'date',
      'kcal',
      'kcal_goal',
      'protein_g',
      'protein_goal_g',
      'carbs_g',
      'carbs_goal_g',
      'fat_g',
      'fat_goal_g',
      'weight_kg',
      'expenditure_kcal',
    ],
    for (final day in days)
      [
        day,
        tracked[day]?.caloriesTracked,
        tracked[day]?.calorieGoal,
        tracked[day]?.proteinTracked,
        tracked[day]?.proteinGoal,
        tracked[day]?.carbsTracked,
        tracked[day]?.carbsGoal,
        tracked[day]?.fatTracked,
        tracked[day]?.fatGoal,
        weight[day],
        spent[day],
      ],
  ]);
}

/// Writes both files for the active profile into the temporary folder and
/// opens the share sheet with them.
Future<void> shareDiaryCsv() async {
  final config = await locator<GetConfigUsecase>().getConfig();
  final intakes = [
    for (final dbo in await locator<IntakeRepository>().getAllIntakesDBO())
      IntakeEntity.fromIntakeDBO(dbo),
  ];
  final tracked = [
    for (final dbo
        in await locator<TrackedDayRepository>().getAllTrackedDaysDBO())
      TrackedDayEntity.fromTrackedDayDBO(dbo),
  ];
  List<ExpenditureDay> expenditure;
  try {
    expenditure = await AdaptiveService.fromLocator().expenditureHistory();
  } catch (_) {
    expenditure = const []; // No profile yet: no estimate.
  }
  final dir = await getTemporaryDirectory();
  final stamp = _date.format(DateTime.now());
  final foods = File('${dir.path}/openbite-foods-$stamp.csv');
  final days = File('${dir.path}/openbite-days-$stamp.csv');
  await foods.writeAsString(
    foodsCsv(intakes, config.dayStartOffsetTotalMinutes),
  );
  await days.writeAsString(
    daysCsv(
      trackedDays: tracked,
      weights: await locator<WeightLogRepository>().getAllEntries(),
      expenditure: expenditure,
    ),
  );
  await SharePlus.instance.share(
    ShareParams(
      files: [XFile(foods.path), XFile(days.path)],
      subject: 'OpenBite diary',
    ),
  );
}

/// "Export diary as CSV" in Settings' data section (seam S51).
class CsvExportTile extends StatelessWidget {
  final Future<void> Function() share;

  const CsvExportTile({super.key, this.share = shareDiaryCsv});

  @override
  Widget build(BuildContext context) => ListTile(
    key: const ValueKey('fork-csv-export'),
    leading: const Icon(Icons.table_chart_outlined),
    title: const Text('Export diary as CSV'),
    subtitle: const Text(
      'Foods and days, with weight and expenditure, for a spreadsheet',
    ),
    onTap: () async {
      try {
        await share();
      } catch (_) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not export the diary')),
        );
      }
    },
  );
}
