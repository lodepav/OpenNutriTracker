import 'package:opennutritracker/fork/phase/shared_phase.dart';
import 'package:opennutritracker/fork/strength/strength_signal.dart';

/// A report older than this says nothing about now.
const strengthMaxAge = Duration(days: 21);

/// An answered suggestion stays quiet this long unless the signal changes.
const strengthQuietFor = Duration(days: 14);

/// The most a suggestion takes a pace to: a cut stays a deficit, maintaining
/// stays maintaining (see [phaseOfRate]), and a bulk stops at the fastest
/// pace the profile offers.
const _cutSlowest = -0.1;
const _maintainHighest = 0.05;
const _bulkFastest = 1.0;

/// Upstream's calories per kg/week a day (`CalorieGoalCalc`), so what a fixed
/// target moves matches what the same pace would.
const _kcalPerRate = 1100.0;

/// A calorie change to offer. Nothing changes until the user applies it.
class StrengthSuggestion {
  final StrengthSignal signal;
  final String phase;
  final double fromRate;
  final double toRate;

  const StrengthSuggestion({
    required this.signal,
    required this.phase,
    required this.fromRate,
    required this.toRate,
  });

  int get kcalPerDay => ((toRate - fromRate) * _kcalPerRate).round();

  /// "Chest strength is falling. That's a warning: you may want a smaller
  /// deficit."
  String get message {
    final names = signal.muscles;
    final subject = names.length < 2
        ? names.join()
        : '${names.sublist(0, names.length - 1).join(', ')} and '
              '${names.last.toLowerCase()}';
    final state = signal.trend == 'not_rising'
        ? (names.length < 2
              ? "hasn't risen in weeks"
              : "haven't risen in weeks")
        : (names.length < 2 ? 'is falling' : 'are falling');
    final change = switch (phase) {
      'cutting' => 'a smaller deficit',
      'bulking' => 'more calories',
      _ => 'a small calorie increase',
    };
    final advice = signal.level == 'clear'
        ? "That's a clear sign to consider $change."
        : "That's a warning: you may want $change.";
    return '$subject strength $state. $advice';
  }

  /// A note when training dropped too, as a drop after training less may not
  /// be about food; null otherwise.
  String? get trainedLess {
    bool below(int? week, double? average) =>
        week != null && average != null && week < average * 0.7;
    if (below(signal.sets7d, signal.setsWeekAvg)) {
      return 'You did ${signal.sets7d} sets in the last 7 days, against about '
          '${signal.setsWeekAvg!.round()} a week in this phase, so this may '
          'not be about food.';
    }
    if (below(signal.sessions7d, signal.sessionsWeekAvg)) {
      return 'You trained ${signal.sessions7d} ${signal.sessions7d == 1 ? 'time' : 'times'} in the last 7 days, '
          'against about ${signal.sessionsWeekAvg!.round()} a week in this '
          'phase, so this may not be about food.';
    }
    return null;
  }
}

/// The suggestion [signal] calls for at pace [rate] (D29), or null: nothing to
/// act on, the report old or from another phase, no room left in the phase, or
/// answered in the last [strengthQuietFor] with the signal unchanged.
StrengthSuggestion? suggestFromStrength(
  StrengthSignal? signal, {
  required double rate,
  required DateTime now,
  StrengthAnswered? answered,
}) {
  if (signal == null || signal.muscles.isEmpty) return null;
  final phase = phaseOfRate(rate);
  final asked =
      signal.trend == 'falling' ||
      signal.trend == 'not_rising' && phase == 'bulking';
  if (!asked || signal.phase != phase) return null;
  if (now.difference(signal.lastWorkoutAt) > strengthMaxAge) return null;
  if (answered != null &&
      answered.key == signal.key &&
      now.difference(answered.at) < strengthQuietFor) {
    return null;
  }
  final step = signal.level == 'clear' ? 0.1 : 0.05;
  final limit = switch (phase) {
    'cutting' => _cutSlowest,
    'bulking' => _bulkFastest,
    _ => _maintainHighest,
  };
  if (rate >= limit) return null;
  final raised = rate + step;
  final to = raised > limit ? limit : (raised * 100).round() / 100;
  return StrengthSuggestion(
    signal: signal,
    phase: phase,
    fromRate: rate,
    toRate: to,
  );
}
