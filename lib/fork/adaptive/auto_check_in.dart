import 'package:flutter/foundation.dart';
import 'package:opennutritracker/core/data/repository/user_repository.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_service.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_store.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_ui.dart'
    show refreshGoals;
import 'package:opennutritracker/fork/adaptive/check_in.dart';

/// Why a check-in is due: the first, the week is up, or the goal (D18)
/// or the target's settings (D20) changed.
enum CheckInReason { first, weekly, goal, settings }

/// Why [service]'s check-in is due, taken as due.
Future<CheckInReason> checkInReason(AdaptiveService service) async =>
    await service.firstCheckIn()
    ? CheckInReason.first
    : await service.goalChanged()
    ? CheckInReason.goal
    : await service.basisChanged()
    ? CheckInReason.settings
    : CheckInReason.weekly;

/// Automatic check-ins (D17), run by Home's card, the main screen's start
/// and each resume, so a target is set with the card hidden too; one that
/// waits on a day that looks partly logged (D65) is said in [waiting].
abstract final class AutoCheckIn {
  /// The check-in last accepted on its own and why; null once dismissed.
  static final accepted =
      ValueNotifier<({CheckIn checkIn, CheckInReason reason})?>(null);

  /// A check-in the last [run] held back for an answer on a day
  /// that looks partly logged, by the date of the check-in before it; null
  /// when none waits.
  static final waiting =
      ValueNotifier<({AdaptiveService service, DateTime since})?>(null);

  /// True while [run] runs: two callers must not accept the same check-in
  /// twice.
  static bool _running = false;

  /// Accepts a due check-in when the setting says so, then refreshes the
  /// goals and publishes it in [accepted]. [service] is the locator's when
  /// null.
  static Future<void> run([AdaptiveService? service]) async {
    if (_running) return;
    _running = true;
    try {
      await _runOnce(service);
    } finally {
      _running = false;
    }
  }

  static Future<void> _runOnce(AdaptiveService? service) async {
    if (!AdaptiveStore.settings.value.autoAcceptCheckIn) {
      waiting.value = null;
      return;
    }
    final AdaptiveService adaptive;
    final CheckIn? checkIn;
    final CheckInReason reason;
    try {
      // Before onboarding there is no profile to set a target for.
      if (locator.isRegistered<UserRepository>() &&
          !await locator<UserRepository>().hasUserData()) {
        return;
      }
      adaptive = service ?? AdaptiveService.fromLocator();
      reason = await checkInReason(adaptive);
      checkIn = await adaptive.autoAcceptIfDue();
    } catch (_) {
      return; // Home's card stays, to be done by hand.
    }
    if (checkIn == null) {
      waiting.value = await _waitingOnPartial(adaptive);
      return;
    }
    waiting.value = null;
    try {
      await refreshGoals();
    } finally {
      accepted.value = (checkIn: checkIn, reason: reason);
    }
  }

  /// [waiting]'s value after a run that accepted nothing.
  static Future<({AdaptiveService service, DateTime since})?> _waitingOnPartial(
    AdaptiveService adaptive,
  ) async {
    try {
      // a first check-in has none before it
      final since = (await adaptive.lastCheckIn())?.date ?? DateTime(0);
      return await adaptive.checkInDue() &&
              (await adaptive.partialDays()).isNotEmpty
          ? (service: adaptive, since: since)
          : null;
    } catch (_) {
      return null; // Home's card, when shown, still says it.
    }
  }
}
