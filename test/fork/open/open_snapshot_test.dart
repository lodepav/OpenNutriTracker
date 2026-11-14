import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'open_fixture.dart';
import 'open_snapshot.dart';

const _write = 'OPEN_SNAPSHOT_WRITE';
final _kept = File('test/fork/open/open_snapshot.json');

void main() {
  group('diffSnapshots', () {
    test('a changed value', () {
      expect(diffSnapshots({'a': 1}, {'a': 2}), ['a: 1 → 2']);
    });

    test('an added and a removed key', () {
      expect(diffSnapshots({'a': 1}, {'b': 'x'}), [
        'a: 1 → (none)',
        'b: (none) → "x"',
      ]);
    });

    test('a nested change names the path', () {
      expect(
        diffSnapshots(
          {
            'goals': {
              'd0': {'kcal': 2000.0, 'fat': 60.0},
            },
          },
          {
            'goals': {
              'd0': {'kcal': 2100.0, 'fat': 60.0},
            },
          },
        ),
        ['goals.d0.kcal: 2000.0 → 2100.0'],
      );
    });

    test('list items are matched by name, not place', () {
      expect(
        diffSnapshots(
          {
            'l': [
              {'name': 'a', 'v': 1},
              {'name': 'b', 'v': 2},
            ],
          },
          {
            'l': [
              {'name': 'b', 'v': 3},
              {'name': 'a', 'v': 1},
            ],
          },
        ),
        ['l.b.v: 2 → 3'],
      );
    });

    test('other lists by index', () {
      expect(diffSnapshots({'l': [1, 2]}, {'l': [1, 3, 4]}), [
        'l[1]: 2 → 3',
        'l[2]: (none) → 4',
      ]);
    });

    test('equal snapshots give no lines', () {
      expect(
        diffSnapshots(
          {
            'a': [
              {'id': 'x', 'v': null},
            ],
          },
          {
            'a': [
              {'id': 'x', 'v': null},
            ],
          },
        ),
        isEmpty,
      );
    });
  });

  // A week behind the clock, so a read of the real now lands on other data.
  test('the snapshot does not depend on the run date', () async {
    final dir = await Directory.systemTemp.createTemp('open_snapshot_week');
    OpenFixture? shifted, normal;
    try {
      final today = openToday();
      shifted = await fillOpenFixture(
        dir,
        DateTime(today.year, today.month, today.day - 7),
      );
      final early = await openSnapshot(shifted);
      await disposeOpenFixture(shifted);
      shifted = null;
      normal = await fillOpenFixture(dir, today);
      final lines = diffSnapshots(await openSnapshot(normal), early);
      expect(lines, isEmpty, reason: lines.join('\n'));
    } finally {
      await disposeOpenFixture(shifted);
      await disposeOpenFixture(normal);
      await dir.delete(recursive: true);
    }
  });

  group('open snapshot', () {
    late Directory dir;
    OpenFixture? fixture;
    late Map<String, dynamic> snap;

    setUpAll(() async {
      dir = await Directory.systemTemp.createTemp('open_snapshot');
      fixture = await fillOpenFixture(dir, openToday());
      snap = await openSnapshot(fixture!);
    });

    tearDownAll(() async {
      await disposeOpenFixture(fixture);
      await dir.delete(recursive: true);
    });

    test('matches the kept snapshot', () async {
      final text = '${const JsonEncoder.withIndent('  ').convert(snap)}\n';
      if (Platform.environment[_write] == '1') {
        await _kept.writeAsString(text);
        return;
      }
      expect(
        _kept.existsSync(),
        isTrue,
        reason: 'no ${_kept.path}; write it with $_write=1',
      );
      final kept = jsonDecode(await _kept.readAsString()) as Map;
      final lines = diffSnapshots(kept, jsonDecode(text) as Map);
      if (lines.isNotEmpty) {
        fail(
          [
            ...lines,
            'a line no decision in fork/DECISIONS.md explains is a bug; '
                'accept a meant change with '
                '`$_write=1 flutter test test/fork/open/open_snapshot_test.dart`',
          ].join('\n'),
        );
      }
    });

    Map<String, dynamic> goal(String variant, [String day = 'd0']) =>
        (snap['goals'][variant] as Map)[day] as Map<String, dynamic>;

    test('adaptive and fixed targets differ from the formula', () {
      final formula = goal('formula')['kcal'];
      expect(goal('adaptive')['kcal'], isNot(formula));
      // Saturday's weekday shift rides on the fixed target too.
      expect(goal('fixed')['kcal'], 2100 + goal('fixed')['weekdayShift']);
    });

    test('a day with an activity holds a higher stored goal on the formula',
        () {
      final diary = snap['diary'] as Map;
      expect(diary['burned'], greaterThan(0));
      expect(
        diary['storedGoal']['calorieGoal'],
        greaterThan(diary['dayWithoutActivity']['calorieGoal']),
      );
    });

    test('the daily activity credit is capped at 800', () {
      expect(goal('activityDaily')['activityKcal'], 800);
      expect(goal('activityDaily')['activityCredit'], 'dailyCapped');
    });

    test('program macros differ from percent macros', () {
      expect(goal('programCut')['protein'], isNot(goal('formula')['protein']));
      expect(goal('programCut')['fat'], isNot(goal('formula')['fat']));
      // On Wednesday's smaller target the 60% protein cap holds protein
      // under 2.2 g/kg.
      final low = goal('programLow', 'd-3');
      expect(
        (low['protein'] as num) * 4,
        closeTo((low['kcal'] as num) * 0.6, 0.1),
      );
      expect(low['protein'], lessThan(goal('programLow')['protein']));
      // And the 20% fat floor holds fat where the cut would scale it lower.
      final cut = goal('programCut', 'd-3');
      expect((cut['fat'] as num) * 9, closeTo((cut['kcal'] as num) * 0.2, 0.1));
      expect(cut['fat'], lessThan(goal('programCut')['fat']));
    });

    test('a row written today for another day takes that day\'s goal', () {
      const row = 'rowWrittenTodayFor d-3';
      final adaptive = snap['goals']['adaptive'] as Map;
      expect(adaptive[row], goal('adaptive', 'd-3')['kcal']);
      expect(adaptive[row], isNot(goal('adaptive')['kcal']));
      // Today's 800 of activity stays on today; d-3 had none.
      final daily = snap['goals']['activityDaily'] as Map;
      expect(daily[row], goal('activityDaily', 'd-3')['kcal']);
      expect(
        daily[row],
        (goal('activityDaily')['kcal'] as num) -
            (goal('activityDaily')['activityKcal'] as num) -
            (goal('activityDaily')['weekdayShift'] as num) +
            openWeekdayOffsets[DateTime.wednesday - 1],
      );
    });

    test('the break hold is present after a break', () {
      expect(snap['adaptive']['afterBreak d-20']['breakHold'], isNotNull);
    });

    test('the trends goal is not a mean over every day', () {
      final trends = snap['trends'] as Map;
      expect(trends['goal']['kcal'], isNotNull);
      expect(trends['goal']['kcal'], isNot(trends['goalKcalOverAllRows']));
    });

    test('a unit change gives an amount that is not grams', () {
      final bread = snap['mealEntry']['bread'] as Map;
      expect(bread['180 g as serving'], isNot('180'));
      expect(bread['180 g as serving'], isNotNull);
    });
  });
}
