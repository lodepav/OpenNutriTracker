import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:opennutritracker/core/domain/entity/weight_log_entity.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_service.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_store.dart';
import 'package:opennutritracker/fork/goal/goal_progress.dart';
import 'package:opennutritracker/fork/health/steps.dart';
import 'package:opennutritracker/fork/history/history_file.dart';
import 'package:opennutritracker/fork/history/history_import.dart';
import 'package:opennutritracker/fork/history/table_reader.dart';

/// A full MacroFactor import: steps, the program's targets and check-ins,
/// the profile's weight and the days said whole (D69). Every number is
/// made up.

Uint8List _bytes(String text) => Uint8List.fromList(utf8.encode(text));

Uint8List _zip(Map<String, String> files) {
  final archive = Archive();
  for (final MapEntry(:key, :value) in files.entries) {
    archive.add(ArchiveFile.bytes(key, _bytes(value)));
  }
  return Uint8List.fromList(ZipEncoder().encodeBytes(archive));
}

const _days = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

/// Seven rows of one update: [kcal] a day, [saturday] on Saturdays.
String _update(
  String date,
  int kcal,
  int saturday,
  int expenditure,
  int average,
  double kg,
) => [
  for (final day in _days)
    '$date,$day,${day == 'Saturday' ? saturday : kcal}.0,70.0,180.0,200.0,'
        '$expenditure.0,$average.0,$kg,Dynamic\n',
].join();

final _today = DateTime(2025, 6, 20);

HistoryFile _export() => readHistory(
  readTables(
    'MacroFactor.zip',
    _zip({
      'Quick Export.csv':
          'Date,Calories (kcal),Protein (g),Fat (g),Carbs (g),Weight (kg)\n'
          '01/06/2025,2050,170,60,210,88.4\n'
          '03/06/2025,2080,175,65,200,88.1\n'
          '07/06/2025,2390,160,80,250,\n'
          '17/06/2025,1990,180,60,190,87.3\n'
          '20/06/2025,1500,100,50,150,\n',
      'Steps.csv':
          'Date,Steps\n'
          '45762.0,0.0\n'
          '45764.0,8123.0\n'
          '45765.0,10456.4\n'
          '45819.0,9000.0\n',
      'Nutrition Program Settings.csv':
          'Program Update Date,Program Weekday,Calories (kcal),Fat (g),'
          'Protein (g),Carbs (g),Expenditure (kcal),Daily Average (kcal),'
          'Weight (kg),Expenditure Calculation Mode\n'
          '${_update('02/06/2025', 2100, 2400, 2650, 2143, 88.0)}'
          '${_update('16/06/2025', 2000, 2300, 2600, 2043, 87.5)}',
      'Weight Goals.csv':
          'Goal,Status,Start Date,End Date,Goal Weight (kg),'
          'Goal Rate per Week (%),Starting Scale Weight (kg)\n'
          'Weight Loss,Completed,01/06/2025,14/06/2025,80.0,0.5,88.4\n'
          'Weight Loss,In Progress,14/06/2025,,79.0,0.75,88.0\n',
      'Partial Logging.csv':
          'Date,Partial Logging\n'
          '01/06/2025,No\n03/06/2025,Yes\n07/06/2025,No\n17/06/2025,No\n',
    }),
  ),
);

HistoryPlan _plan(HistoryFile file, [HistoryExisting? existing]) => planImport(
  file,
  existing: existing ?? const HistoryExisting(),
  today: _today,
  source: 'MacroFactor',
);

const _basis = 'activity=off;flat=false';

void main() {
  group('steps', () {
    test('the days with a count; 0 is no count', () {
      expect(_export().steps, {
        DateTime(2025, 4, 17): 8123,
        DateTime(2025, 4, 18): 10456,
        DateTime(2025, 6, 11): 9000,
      });
    });

    test('planned for days with none kept', () {
      final plan = _plan(
        _export(),
        HistoryExisting(stepDays: {DateTime(2025, 4, 17)}),
      );
      expect(plan.steps, {
        DateTime(2025, 4, 18): 10456,
        DateTime(2025, 6, 11): 9000,
      });
    });

    test('a workout log\'s steps are no day\'s steps', () {
      final file = readHistory(
        readTables(
          'exercises.csv',
          _bytes(
            'Date,Exercise,Steps,Calories Burned\n'
            '2025-04-17,Walk,4000,200\n'
            '2025-04-17,Run,6000,500\n',
          ),
        ),
      );
      expect(file.steps, isEmpty);
    });

    test('stored beside the health store\'s, which stay', () async {
      final dir = await Directory.systemTemp.createTemp('history_steps');
      Hive.init(dir.path);
      addTearDown(() async {
        await Hive.close();
        await dir.delete(recursive: true);
      });
      final box = await Hive.openBox<dynamic>('steps');
      await box.put('steps', {'2025-04-17': 5000});
      final steps = StepCounts(null, () async => box);
      await steps.addImported({
        DateTime(2025, 4, 17): 8123,
        DateTime(2025, 4, 18): 10456,
      });
      expect(await steps.cached(), {
        DateTime(2025, 4, 17): 5000,
        DateTime(2025, 4, 18): 10456,
      });
    });
  });

  group('past targets', () {
    test('each day has its weekday\'s target of the program then; none '
        'before the first update, nor today', () {
      final file = _export();
      expect(file.programs.map((p) => p.date), [
        DateTime(2025, 6, 2),
        DateTime(2025, 6, 16),
      ]);
      final plan = _plan(file);
      expect(plan.dayGoals, {
        DateTime(2025, 6, 3): (
          kcal: 2100.0,
          carbs: 200.0,
          fat: 70.0,
          protein: 180.0,
        ),
        DateTime(2025, 6, 7): (
          kcal: 2400.0,
          carbs: 200.0,
          fat: 70.0,
          protein: 180.0,
        ),
        DateTime(2025, 6, 17): (
          kcal: 2000.0,
          carbs: 200.0,
          fat: 70.0,
          protein: 180.0,
        ),
      });
    });

    test('days an earlier import wrote get them too; not the app\'s own', () {
      final file = _export();
      final first = _plan(file);
      final again = _plan(
        file,
        HistoryExisting(
          importedDays: {
            for (final MapEntry(:key, :value) in first.intakes.entries)
              if (key != DateTime(2025, 6, 17)) key: value,
          },
          loggedDays: {DateTime(2025, 6, 17)},
          importedDayGoals: {
            DateTime(2025, 6, 3): first.dayGoals[DateTime(2025, 6, 3)]!,
          },
        ),
      );
      expect(again.intakes, isEmpty);
      expect(again.dayGoals.keys, [DateTime(2025, 6, 7)]);
    });
  });

  group('check-ins', () {
    test('one an update, as accepted then, for the goal running then', () {
      final file = _export();
      final plan = _plan(file, const HistoryExisting(targetBasis: _basis));
      final [first, second] = plan.checkIns;
      expect(first.date, DateTime(2025, 6, 2));
      expect(first.expenditureKcal, 2650);
      expect(first.proposedKcal, 2143);
      expect(first.acceptedKcal, 2143);
      expect(first.baseKcal, 2650);
      expect(first.activityKcal, 0);
      expect(first.goalRateKgPerWeek, closeTo(-0.44, 1e-9));
      expect(first.targetWeightKg, 80);
      expect(first.basis, _basis);
      // The goal in progress, at the update's weight.
      expect(second.goalRateKgPerWeek, closeTo(-0.65625, 1e-9));
      expect(second.targetWeightKg, 79);

      // The next check-in is weighed against the last as if made here.
      const settings = AdaptiveSettings(adaptiveTarget: true);
      expect(settings.targetBasis, _basis);
      expect(AdaptiveService.capMark(plan.checkIns, settings), same(second));
      expect(second.basisChanged(settings), isFalse);
      expect(second.goalChanged(-0.65625, 79), isFalse);
      expect(second.goalChanged(-0.5, 79), isTrue);
      expect(checkInDueOn(_today, second.date, null), isFalse);
      expect(checkInDueOn(DateTime(2025, 6, 23), second.date, null), isTrue);

      // Goal progress: the app's own run at the profile's pace now starts
      // at its first check-in, after the imported ones at another pace.
      final own = [
        for (final day in [23, 30])
          CheckInRecord(
            date: DateTime(2025, 6, day, 10),
            expenditureKcal: 2600,
            proposedKcal: 2100,
            acceptedKcal: 2100,
            goalRateKgPerWeek: -0.5,
          ),
      ];
      expect(paceSetOn(own, -0.5), isNull);
      expect(
        paceSetOn([...plan.checkIns, ...own], -0.5),
        DateTime(2025, 6, 23, 10),
      );
    });

    test('none from the app\'s own first on, nor on a day with one', () {
      final file = _export();
      final own = CheckInRecord(
        date: DateTime(2025, 6, 16, 14, 30),
        expenditureKcal: 2700,
        proposedKcal: 2200,
        acceptedKcal: 2200,
      );
      expect(
        _plan(
          file,
          HistoryExisting(checkIns: [own]),
        ).checkIns.map((c) => c.date),
        [DateTime(2025, 6, 2)],
      );
      final imported = _plan(file).checkIns;
      expect(
        _plan(file, HistoryExisting(checkIns: imported)).checkIns,
        isEmpty,
      );
    });
  });

  group('profile weight', () {
    final made = DateTime(2025, 5, 1, 9);

    test('the newest weigh-in when newer than the profile and every '
        'weigh-in here', () {
      expect(
        _plan(
          _export(),
          HistoryExisting(profileWeightKg: 90, profileCreatedAt: made),
        ).profileWeightKg,
        87.3,
      );
    });

    test('kept when a weigh-in here is newer, or the profile was made that '
        'day, or there is no profile', () {
      final file = _export();
      expect(
        _plan(
          file,
          HistoryExisting(
            profileWeightKg: 90,
            profileCreatedAt: made,
            weighIns: [
              WeightLogEntity(date: DateTime(2025, 6, 18), weightKg: 86.9),
            ],
          ),
        ).profileWeightKg,
        isNull,
      );
      expect(
        _plan(
          file,
          HistoryExisting(
            profileWeightKg: 90,
            profileCreatedAt: DateTime(2025, 6, 17, 15),
          ),
        ).profileWeightKg,
        isNull,
      );
      expect(_plan(file).profileWeightKg, isNull);
    });

    test('set on a second import, the weigh-in already written', () {
      final plan = _plan(
        _export(),
        HistoryExisting(
          profileWeightKg: 90,
          profileCreatedAt: made,
          weighIns: [
            WeightLogEntity(date: DateTime(2025, 6, 17), weightKg: 87.3),
          ],
        ),
      );
      expect(
        plan.weights.map((w) => w.date),
        isNot(contains(DateTime(2025, 6, 17))),
      );
      expect(plan.profileWeightKg, 87.3);
    });
  });

  group('whole days', () {
    test('the days marked No, but not one answered here', () {
      final file = _export();
      expect(file.wholeDays, {
        DateTime(2025, 6, 1),
        DateTime(2025, 6, 7),
        DateTime(2025, 6, 17),
      });
      expect(file.partialDays, {DateTime(2025, 6, 3)});
      final plan = _plan(
        file,
        HistoryExisting(
          partialDays: {DateTime(2025, 6, 7)},
          wholeDays: {DateTime(2025, 6, 17)},
        ),
      );
      expect(plan.wholeDays, {DateTime(2025, 6, 1)});
    });

    test('merged into the store, not over a day left out there', () async {
      final dir = await Directory.systemTemp.createTemp('history_whole');
      Hive.init(dir.path);
      addTearDown(() async {
        await Hive.close();
        await dir.delete(recursive: true);
      });
      final box = await Hive.openBox<dynamic>('whole');
      final store = AdaptiveStore(() async => box);
      await store.setSkipped(DateTime(2025, 6, 7), true);
      await store.setWhole(DateTime(2025, 6, 17), true);
      await store.mergeWholeDays([DateTime(2025, 6, 1), DateTime(2025, 6, 7)]);
      expect(await store.wholeDays(), {
        DateTime(2025, 6, 1),
        DateTime(2025, 6, 17),
      });
      expect(AdaptiveStore.whole.value, await store.wholeDays());
      expect(await store.skippedDays(), {DateTime(2025, 6, 7)});
    });
  });

  test('a second import of the same export adds nothing', () {
    final file = _export();
    final first = _plan(
      file,
      HistoryExisting(
        targetBasis: _basis,
        profileWeightKg: 90,
        profileCreatedAt: DateTime(2025, 5, 1),
      ),
    );
    final again = _plan(
      file,
      HistoryExisting(
        importedDays: first.intakes,
        importedDayGoals: first.dayGoals,
        weighIns: first.weights,
        partialDays: first.partialDays,
        wholeDays: first.wholeDays,
        stepDays: {...first.steps.keys, DateTime(2025, 4, 17)},
        checkIns: first.checkIns,
        goals: first.goals,
        targetBasis: _basis,
        profileWeightKg: first.profileWeightKg,
        profileCreatedAt: DateTime(2025, 5, 1),
      ),
    );
    expect(again.isEmpty, isTrue);
  });

  test('other apps\' exports come in as before: none of these', () {
    final file = readHistory([
      ...readTables(
        'Nutrition-Summary.csv',
        _bytes(
          'Date,Meal,Calories,Fat (g),Carbohydrates (g),Protein (g)\n'
          '01/05/2024,Breakfast,400,10,50,20\n',
        ),
      ),
      ...readTables(
        'cronometer.zip',
        _zip({
          'dailysummary.csv':
              'Date,Energy (kcal),Protein (g),Carbs (g),Fat (g)\n'
              '2024-03-02,1900.5,120,210,60\n',
          'biometrics.csv':
              'Day,Group,Metric,Unit,Amount\n'
              '2024-03-02,Weight,Weight,kg,79.5\n',
        }),
      ),
    ]);
    expect(file.steps, isEmpty);
    expect(file.programs, isEmpty);
    expect(file.paces, isEmpty);
    expect(file.wholeDays, isEmpty);
    final plan = planImport(
      file,
      existing: HistoryExisting(
        targetBasis: _basis,
        profileWeightKg: 80,
        profileCreatedAt: DateTime(2024, 1, 1),
      ),
      today: DateTime(2024, 3, 2),
      source: 'MyFitnessPal',
    );
    expect(plan.intakes, isNotEmpty);
    expect(plan.steps, isEmpty);
    expect(plan.dayGoals, isEmpty);
    expect(plan.checkIns, isEmpty);
    expect(plan.wholeDays, isEmpty);
    expect(plan.profileWeightKg, isNull);
  });
}
