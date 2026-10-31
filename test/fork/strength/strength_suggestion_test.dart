import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/fork/strength/strength_signal.dart';
import 'package:opennutritracker/fork/strength/strength_suggestion.dart';

void main() {
  final now = DateTime(2026, 10, 31);

  StrengthSignal signal({
    String trend = 'falling',
    String? level = 'warning',
    List<String> muscles = const ['Chest'],
    String? phase = 'cutting',
    Duration age = const Duration(days: 2),
    int? sets,
    double? setsAvg,
    int? sessions,
    double? sessionsAvg,
  }) => StrengthSignal(
    trend: trend,
    level: level,
    muscles: muscles,
    phase: phase,
    lastWorkoutAt: now.subtract(age),
    sets7d: sets,
    setsWeekAvg: setsAvg,
    sessions7d: sessions,
    sessionsWeekAvg: sessionsAvg,
  );

  StrengthSuggestion? suggest(
    StrengthSignal? s, {
    double rate = -0.4,
    StrengthAnswered? answered,
  }) => suggestFromStrength(s, rate: rate, now: now, answered: answered);

  group('what calls for a suggestion', () {
    test('cutting and falling: a smaller deficit', () {
      final it = suggest(signal())!;
      expect(it.toRate, -0.35);
      expect(it.kcalPerDay, 55);
      expect(it.message, contains('a smaller deficit'));
    });

    test('bulking: falling, or not rising', () {
      for (final trend in ['falling', 'not_rising']) {
        final it = suggest(signal(trend: trend, phase: 'bulking'), rate: 0.25)!;
        expect(it.toRate, 0.3);
        expect(it.message, contains('more calories'));
      }
    });

    test('maintaining: falling only, a small increase', () {
      final it = suggest(signal(phase: 'maintaining'), rate: 0)!;
      expect(it.toRate, 0.05);
      expect(it.message, contains('a small calorie increase'));
      expect(
        suggest(signal(trend: 'not_rising', phase: 'maintaining'), rate: 0),
        isNull,
      );
    });

    test('not rising says nothing in a cut', () {
      expect(suggest(signal(trend: 'not_rising')), isNull);
    });

    test('rising and holding say nothing, nor does no report', () {
      for (final trend in ['rising', 'holding']) {
        expect(suggest(signal(trend: trend, level: null)), isNull);
      }
      expect(suggest(null), isNull);
    });

    test('a report from another phase says nothing', () {
      expect(suggest(signal(phase: 'bulking')), isNull);
      expect(suggest(signal(phase: null)), isNull);
    });

    test('a last workout over 21 days old says nothing', () {
      expect(suggest(signal(age: const Duration(days: 22))), isNull);
      expect(suggest(signal(age: const Duration(days: 21))), isNotNull);
    });
  });

  group('how far it goes', () {
    test('a clear sign moves twice as far, and says so', () {
      final it = suggest(signal(level: 'clear', muscles: ['Chest', 'Back']))!;
      expect(it.toRate, -0.3);
      expect(it.kcalPerDay, 110);
      expect(
        it.message,
        "Chest and back strength are falling. That's a clear sign to consider "
        'a smaller deficit.',
      );
    });

    test('one muscle reads as a warning', () {
      expect(
        suggest(signal())!.message,
        "Chest strength is falling. That's a warning: you may want a smaller "
        'deficit.',
      );
    });

    test('a cut stays a deficit, and at its slowest says nothing', () {
      expect(suggest(signal(level: 'clear'), rate: -0.15)!.toRate, -0.1);
      expect(suggest(signal(), rate: -0.1), isNull);
    });

    test('maintaining stays maintaining, whatever the level', () {
      final it = suggest(
        signal(level: 'clear', phase: 'maintaining'),
        rate: 0,
      )!;
      expect(it.toRate, 0.05);
      expect(suggest(signal(phase: 'maintaining'), rate: 0.05), isNull);
    });

    test('a bulk stops at the fastest pace', () {
      expect(
        suggest(signal(level: 'clear', phase: 'bulking'), rate: 0.95)!.toRate,
        1,
      );
      expect(suggest(signal(phase: 'bulking'), rate: 1), isNull);
    });
  });

  group('after it was answered', () {
    final key = signal().key;

    test('stays quiet for 14 days', () {
      final at = now.subtract(const Duration(days: 13));
      expect(suggest(signal(), answered: StrengthAnswered(key, at)), isNull);
    });

    test('asks again after 14 days', () {
      final at = now.subtract(const Duration(days: 14));
      expect(suggest(signal(), answered: StrengthAnswered(key, at)), isNotNull);
    });

    test('asks again when the muscles or the trend change', () {
      final answered = StrengthAnswered(key, now);
      expect(
        suggest(
          signal(muscles: ['Chest', 'Back'], level: 'clear'),
          answered: answered,
        ),
        isNotNull,
      );
      final bulk = signal(phase: 'bulking');
      expect(
        suggest(
          signal(trend: 'not_rising', phase: 'bulking'),
          rate: 0.25,
          answered: StrengthAnswered(bulk.key, now),
        ),
        isNotNull,
      );
    });

    test('the order of the muscles is not a change', () {
      expect(
        signal(muscles: ['Back', 'Chest']).key,
        signal(muscles: ['Chest', 'Back']).key,
      );
    });

    test('a stored answer reads back, and junk reads as none', () {
      final read = StrengthAnswered.decode(StrengthAnswered('k', now).encode());
      expect(read?.key, 'k');
      expect(read?.at, now);
      expect(StrengthAnswered.decode('junk'), isNull);
      expect(StrengthAnswered.decode(null), isNull);
    });
  });

  group('training less', () {
    test('well below the usual sets is mentioned', () {
      final it = suggest(signal(sets: 6, setsAvg: 14))!;
      expect(it.trainedLess, contains('6 sets'));
      expect(it.trainedLess, contains('about 14 a week'));
    });

    test('else the sessions', () {
      final it = suggest(
        signal(sets: 14, setsAvg: 14, sessions: 1, sessionsAvg: 4),
      )!;
      expect(it.trainedLess, contains('trained 1 time '));
    });

    test('near the usual, or with no average yet, is not', () {
      expect(suggest(signal(sets: 12, setsAvg: 14))!.trainedLess, isNull);
      expect(suggest(signal(sets: 1))!.trainedLess, isNull);
    });
  });

  test('a row reads by name, and without its essentials is nothing', () {
    final it = StrengthSignal.fromRow({
      'trend': 'falling',
      'level': 'warning',
      'muscles': 'Chest, Back',
      'phase': 'cutting',
      'sets_7d': 6,
      'sets_week_avg': 14.0,
      'last_workout_at': now.millisecondsSinceEpoch,
      'a_later_column': 'ignored',
    })!;
    expect(it.muscles, ['Chest', 'Back']);
    expect(it.setsWeekAvg, 14);
    expect(it.lastWorkoutAt, now);
    expect(StrengthSignal.fromRow({'trend': 'falling'}), isNull);
    expect(StrengthSignal.fromRow({'last_workout_at': 1}), isNull);
  });
}
