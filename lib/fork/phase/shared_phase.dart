import 'dart:convert';
import 'dart:io';

import 'package:home_widget/home_widget.dart';
import 'package:logging/logging.dart';
import 'package:opennutritracker/core/domain/entity/user_entity.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_service.dart';

/// `cutting`, `maintaining` or `bulking`: a pace under 0.1 kg/week either way
/// is maintaining, so a small increase while maintaining keeps the phase (D29).
String phaseOfRate(double rateKgPerWeek) => rateKgPerWeek <= -0.1
    ? 'cutting'
    : rateKgPerWeek >= 0.1
    ? 'bulking'
    : 'maintaining';

/// Whether the user is cutting, maintaining or bulking, for Go Hevier to read
/// through `PhaseProvider` (`android/app/src/fork/kotlin`). Saved beside the
/// widgets' figures each time Home loads, so it can be read with the app shut;
/// the provider answers nothing once upstream's calorie snapshot is cleared (a
/// profile wiped or switched away).
class SharedPhase {
  static const storageKey = 'openbite_shared_phase';

  /// `cutting`, `maintaining` or `bulking`.
  final String phase;

  /// Negative to lose. It decides [phase], as it decides the calories.
  final double rateKgPerWeek;

  /// The day's target before activity, always in kcal.
  final int targetKcal;

  /// When Home last saved this, in milliseconds since the epoch.
  final int updatedAt;

  const SharedPhase({
    required this.phase,
    required this.rateKgPerWeek,
    required this.targetKcal,
    required this.updatedAt,
  });

  factory SharedPhase.of(
    UserEntity user, {
    required double targetKcal,
    required DateTime now,
  }) {
    final rate = goalRateKgPerWeek(user);
    return SharedPhase(
      phase: phaseOfRate(rate),
      rateKgPerWeek: rate,
      targetKcal: targetKcal.round(),
      updatedAt: now.millisecondsSinceEpoch,
    );
  }

  String encode() => jsonEncode({
    'phase': phase,
    'rateKgPerWeek': rateKgPerWeek,
    'targetKcal': targetKcal,
    'updatedAt': updatedAt,
  });
}

final _log = Logger('SharedPhase');

/// Seam S182: saves [phase]; a failure is logged, never in Home's way.
/// [stillCurrent] false (a clear ran since Home read it) drops it, as the
/// widgets' writes do.
Future<void> publishSharedPhase(
  SharedPhase phase, {
  bool Function()? stillCurrent,
}) async {
  if (!Platform.isAndroid) return;
  try {
    if (stillCurrent != null && !stillCurrent()) return;
    await HomeWidget.saveWidgetData<String>(
      SharedPhase.storageKey,
      phase.encode(),
    );
  } catch (error, stack) {
    _log.fine('Could not save the shared phase', error, stack);
  }
}
