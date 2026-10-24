import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:logging/logging.dart';
import 'package:opennutritracker/core/domain/usecase/get_user_usecase.dart';
import 'package:opennutritracker/core/utils/hive_db_provider.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/core/utils/tracked_day_lock.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_store.dart';
import 'package:opennutritracker/fork/adaptive/goal_plan_card.dart';

enum PhaseKind {
  cut('Cut'),
  maintain('Maintenance'),
  bulk('Bulk');

  final String label;

  const PhaseKind(this.label);
}

/// One phase of a diet plan: [weeks] long at [kgPerWeek] (negative while
/// cutting, 0 at maintenance, which a diet break is).
class DietPhase {
  final PhaseKind kind;
  final double kgPerWeek;
  final int weeks;

  const DietPhase({
    required this.kind,
    required this.kgPerWeek,
    required this.weeks,
  });

  Map<String, Object> toJson() => {
    'kind': kind.name,
    'kgPerWeek': kgPerWeek,
    'weeks': weeks,
  };

  static DietPhase fromJson(Map<dynamic, dynamic> json) {
    final weeks = json['weeks'] as int;
    if (weeks < 1) throw FormatException('A phase needs a week', '$weeks');
    return DietPhase(
      kind: PhaseKind.values.byName(json['kind'] as String),
      kgPerWeek: (json['kgPerWeek'] as num).toDouble(),
      weeks: weeks,
    );
  }
}

/// MacroFactor's diet phases: cut, maintenance and bulk one after another
/// from [start]; maintenance once the last ends.
class PhasePlan {
  final DateTime start;
  final List<DietPhase> phases;

  const PhasePlan({required this.start, required this.phases});

  /// The day phase [index] starts, the day after the last for
  /// `phases.length`.
  DateTime startOf(int index) {
    var days = 0;
    for (final p in phases.take(index)) {
      days += p.weeks * 7;
    }
    return DateTime(start.year, start.month, start.day + days);
  }

  DateTime get end => startOf(phases.length);

  /// The phase running on [day]'s date: its index, or -1 before the
  /// start and `phases.length` after the end.
  int indexOn(DateTime day) {
    final date = DateTime(day.year, day.month, day.day);
    if (date.isBefore(startOf(0))) return -1;
    for (var i = 0; i < phases.length; i++) {
      if (date.isBefore(startOf(i + 1))) return i;
    }
    return phases.length;
  }

  /// The pace on [day]: the running phase's, or maintenance after the end;
  /// null before the start, when the profile's own pace stands.
  double? paceOn(DateTime day) {
    final i = indexOn(day);
    if (i < 0) return null;
    return i < phases.length ? phases[i].kgPerWeek : 0;
  }

  Map<String, Object> toJson() => {
    'start': start.toIso8601String(),
    'phases': [for (final p in phases) p.toJson()],
  };

  static PhasePlan fromJson(Map<dynamic, dynamic> json) => PhasePlan(
    start: DateTime.parse(json['start'] as String),
    phases: [
      for (final p in json['phases'] as List) DietPhase.fromJson(p as Map),
    ],
  );
}

/// The plan, per profile in the fork's box beside the adaptive state, and
/// which phase was last put into the profile.
class PhaseStore {
  static const planKey = 'phasePlan';
  static const _appliedKey = 'phaseApplied';

  /// Bumped when the plan changes, so the Trends card reloads.
  static final changes = ValueNotifier(0);

  final Future<Box<dynamic>> Function() _box;

  PhaseStore([Future<Box<dynamic>> Function()? box])
    : _box = box ?? AdaptiveStore.openActiveBox;

  Future<PhasePlan?> plan() async {
    final json = (await _box()).get(planKey);
    return json is Map ? PhasePlan.fromJson(json) : null;
  }

  /// Saves [plan], or removes it with null; the phase it is in will be
  /// applied afresh.
  Future<void> save(PhasePlan? plan) async {
    final box = await _box();
    if (plan == null) {
      await box.delete(planKey);
    } else {
      await box.put(planKey, plan.toJson());
    }
    await box.delete(_appliedKey);
    changes.value++;
  }

  Future<String?> applied() async => (await _box()).get(_appliedKey) as String?;

  Future<void> markApplied(String key) async =>
      (await _box()).put(_appliedKey, key);
}

/// Puts the running phase's pace into the profile when a phase begins
/// (and when the plan is saved), through upstream's profile update, so
/// the formula, the check-in and the goal planner all follow it. A pace
/// changed by hand stands until the next phase.
class PhaseRunner {
  static final _log = Logger('PhaseRunner');

  final PhaseStore _store;

  /// False when the pace was not saved, or not for the profile current at
  /// the stamp.
  final Future<bool> Function(double kgPerWeek, ProfileStamp startedOn)
  _setPace;
  final DateTime Function() _clock;

  PhaseRunner({
    PhaseStore? store,
    Future<bool> Function(double kgPerWeek, ProfileStamp startedOn)? setPace,
    DateTime Function()? clock,
  }) : _store = store ?? PhaseStore(),
       _setPace = setPace ?? _savePaceIfProfile,
       _clock = clock ?? DateTime.now;

  static Future<bool> _savePaceIfProfile(
    double kgPerWeek,
    ProfileStamp startedOn,
  ) async =>
      await locator<GetUserUsecase>().hasUserData() &&
      await savePace(kgPerWeek, startedOn);

  /// Returns whether a pace was set; failures are logged.
  Future<bool> run() async {
    // The plan and the pace of one profile.
    final startedOn = ProfileStamp.now();
    try {
      final plan = await _store.plan();
      if (plan == null) return false;
      final now = _clock();
      final pace = plan.paceOn(now);
      if (pace == null) return false;
      final key = '${plan.start.toIso8601String()}#${plan.indexOn(now)}';
      if (await _store.applied() == key) return false;
      // Unsaved (no profile yet, or a profile switch dropped it), it is
      // tried again on the next resume.
      if (!await _setPace(pace, startedOn)) return false;
      await _store.markApplied(key);
      return true;
    } catch (error, stack) {
      _log.warning('Could not apply the diet phase', error, stack);
      return false;
    }
  }

  /// Run at start-up (seam S6): now, on every resume, on a profile switch
  /// and when the plan changes.
  static Future<void> start() async {
    final runner = PhaseRunner();
    void run() => unawaited(runner.run());
    run();
    PhaseStore.changes.addListener(run);
    // A switch notifies while it holds the lock, where a stamp names no
    // profile: run once it is through (from outside its zone, so the lock
    // waits for it rather than letting this in).
    locator<HiveDBProvider>().addListener(
      () => Zone.root.run(
        () => unawaited(withTrackedDayLock(() async {}).then((_) => run())),
      ),
    );
    WidgetsBinding.instance.addObserver(_Lifecycle(run));
  }
}

class _Lifecycle extends WidgetsBindingObserver {
  final void Function() _run;

  _Lifecycle(this._run);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _run();
  }
}
