import 'package:flutter/foundation.dart';
import 'package:health/health.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:opennutritracker/core/utils/extensions.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_store.dart';
import 'package:opennutritracker/fork/dev/fake_health.dart';

/// Where step counts come from: Health Connect / Apple Health, or a fake on
/// the emulator.
abstract class StepSource {
  Future<bool> requestPermission();

  /// Steps taken within `[from, to)`, every source merged without double
  /// counting; throws when the read is refused.
  Future<int> stepsBetween(DateTime from, DateTime to);
}

class HealthStoreSteps implements StepSource {
  static const _types = [HealthDataType.STEPS];
  static const _read = [HealthDataAccess.READ];

  const HealthStoreSteps();

  @override
  Future<bool> requestPermission() async =>
      await Health().requestAuthorization(_types, permissions: _read) &&
      await Health().hasPermissions(_types, permissions: _read) != false;

  @override
  Future<int> stepsBetween(DateTime from, DateTime to) async {
    // A revoked grant would read as a day of no steps and be kept.
    if (await Health().hasPermissions(_types, permissions: _read) == false) {
      throw StateError('No permission to read steps');
    }
    return await Health().getTotalStepsInInterval(from, to) ?? 0;
  }
}

/// Daily steps from the health store, shown on Trends (MacroFactor shows
/// them beside the weight). Read only: they change no target, since the
/// adaptive expenditure already measures what walking burns.
///
/// Per profile, in the fork's box: whether it is on, the daily goal, and
/// the days read so far, kept so the history outlives the health store's
/// own (Health Connect lets an app read only 30 days back).
class StepCounts {
  static const defaultGoal = 8000;

  /// Days read back: what Health Connect lets a new app read.
  static const backfill = 30;
  static const _on = 'stepsOn';
  static const _goal = 'stepGoal';
  static const _days = 'steps';

  /// Bumped when the switch or the goal changes, so the card reloads.
  static final changes = ValueNotifier(0);

  final StepSource _source;
  final Future<Box<dynamic>> Function() _box;

  StepCounts([StepSource? source, Future<Box<dynamic>> Function()? box])
    : _source =
          source ?? (forkFakeHealth ? FakeSteps() : const HealthStoreSteps()),
      _box = box ?? AdaptiveStore.openActiveBox;

  Future<bool> isOn() async =>
      (await _box()).get(_on, defaultValue: false) as bool;

  Future<int> goal() async =>
      (await _box()).get(_goal, defaultValue: defaultGoal) as int;

  Future<void> setGoal(int steps) async {
    await (await _box()).put(_goal, steps);
    changes.value++;
  }

  /// Asks for the permission and turns the reading on; false when refused.
  Future<bool> turnOn() async {
    if (!await _source.requestPermission()) return false;
    await (await _box()).put(_on, true);
    changes.value++;
    return true;
  }

  Future<void> turnOff() async {
    await (await _box()).put(_on, false);
    changes.value++;
  }

  /// Steps of the [days] days to [today], oldest first; a day without a
  /// count is missing. Reads the days of the last [backfill] the cache
  /// lacks, and always the last two (today is still going, and a phone
  /// syncs a watch late); older days come from the cache only.
  Future<Map<DateTime, int>> daily(DateTime today, int days) async {
    final box = await _box();
    final cached = {
      for (final MapEntry(:key, :value)
          in (box.get(_days, defaultValue: {}) as Map).entries)
        key as String: value as int,
    };
    final last = DateTime(today.year, today.month, today.day);
    DateTime dayAt(int ago) => DateTime(last.year, last.month, last.day - ago);

    for (var ago = backfill - 1; ago >= 0; ago--) {
      final day = dayAt(ago);
      final key = day.toParsedDay();
      if (ago > 1 && cached.containsKey(key)) continue;
      final end = ago == 0 ? today : DateTime(day.year, day.month, day.day + 1);
      cached[key] = await _source.stepsBetween(day, end);
    }
    await box.put(_days, cached);
    return {
      for (var ago = days - 1; ago >= 0; ago--)
        dayAt(ago): ?cached[dayAt(ago).toParsedDay()],
    };
  }
}
