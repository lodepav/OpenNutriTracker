import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:logging/logging.dart';

const _channel = MethodChannel('openbite/strength');

final _log = Logger('StrengthSignal');

/// How strength is going in the current phase, as Go Hevier reports it (D29;
/// Hevier's D95, which holds the rule behind it: it is not worked out again
/// here).
class StrengthSignal {
  /// `falling`, `not_rising`, `rising` or `holding`.
  final String trend;

  /// `warning` for one muscle group, `clear` for more; null while [trend] is
  /// `rising` or `holding`.
  final String? level;
  final List<String> muscles;

  /// The phase Go Hevier saved on the latest workout.
  final String? phase;
  final int? sets7d;
  final double? setsWeekAvg;
  final int? sessions7d;
  final double? sessionsWeekAvg;
  final DateTime lastWorkoutAt;

  const StrengthSignal({
    required this.trend,
    required this.level,
    required this.muscles,
    required this.phase,
    required this.lastWorkoutAt,
    this.sets7d,
    this.setsWeekAvg,
    this.sessions7d,
    this.sessionsWeekAvg,
  });

  /// From the provider's row; null without what a suggestion rests on.
  static StrengthSignal? fromRow(Map<Object?, Object?> row) {
    final trend = row['trend'];
    final lastWorkout = row['last_workout_at'];
    if (trend is! String || lastWorkout is! int) return null;
    return StrengthSignal(
      trend: trend,
      level: row['level'] as String?,
      muscles: [
        for (final muscle in ((row['muscles'] as String?) ?? '').split(','))
          if (muscle.trim().isNotEmpty) muscle.trim(),
      ],
      phase: row['phase'] as String?,
      sets7d: row['sets_7d'] as int?,
      setsWeekAvg: (row['sets_week_avg'] as num?)?.toDouble(),
      sessions7d: row['sessions_7d'] as int?,
      sessionsWeekAvg: (row['sessions_week_avg'] as num?)?.toDouble(),
      lastWorkoutAt: DateTime.fromMillisecondsSinceEpoch(lastWorkout),
    );
  }

  /// What a dismissal holds to: a change in the trend or the muscle groups is
  /// a new signal.
  String get key => '$trend|${([...muscles]..sort()).join(',')}';
}

/// What a dismissed or applied suggestion was about, and when.
class StrengthAnswered {
  final String key;
  final DateTime at;

  const StrengthAnswered(this.key, this.at);

  static StrengthAnswered? decode(Object? stored) {
    if (stored is! String) return null;
    try {
      final json = jsonDecode(stored) as Map<String, dynamic>;
      return StrengthAnswered(
        json['key'] as String,
        DateTime.parse(json['at'] as String),
      );
    } catch (_) {
      return null;
    }
  }

  String encode() => jsonEncode({'key': key, 'at': at.toIso8601String()});
}

/// Go Hevier's report, or null when it has none or can't be trusted; on
/// Android only, and never in the way of Home.
Future<StrengthSignal?> readStrengthSignal() async {
  if (defaultTargetPlatform != TargetPlatform.android) return null;
  try {
    final row = await _channel.invokeMethod<Map<Object?, Object?>>('read');
    return row == null ? null : StrengthSignal.fromRow(row);
  } catch (error, stack) {
    _log.fine('Could not read the strength signal', error, stack);
    return null;
  }
}
