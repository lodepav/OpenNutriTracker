import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:logging/logging.dart';
import 'package:opennutritracker/core/domain/usecase/get_user_usecase.dart';
import 'package:opennutritracker/core/utils/hive_db_provider.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/core/utils/tracked_day_lock.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_service.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_store.dart';
import 'package:opennutritracker/fork/adaptive/goal_plan.dart';
import 'package:opennutritracker/fork/adaptive/goal_plan_card.dart';
import 'package:opennutritracker/fork/goal/goal_actions.dart';

enum PhaseKind {
  cut('Cut'),
  maintain('Maintenance'),
  bulk('Bulk');

  final String label;

  const PhaseKind(this.label);
}

/// One phase of a diet plan: [weeks] long at [kgPerWeek] (negative while
/// cutting, 0 at maintenance, which a diet break is). A phase set to end
/// at a weight keeps it in [untilKg]; its [weeks] are worked out from it
/// ([weeksTo]) as it is edited, and run as any phase's.
class DietPhase {
  final PhaseKind kind;
  final double kgPerWeek;
  final int weeks;
  final double? untilKg;

  const DietPhase({
    required this.kind,
    required this.kgPerWeek,
    required this.weeks,
    this.untilKg,
  });

  /// Whole weeks from [fromKg] to [untilKg] at [kgPerWeek], 1 to 52: a
  /// rough estimate, as the weight never follows a pace exactly.
  static int weeksTo(double fromKg, double untilKg, double kgPerWeek) =>
      kgPerWeek == 0 ? 1 : ((untilKg - fromKg) / kgPerWeek).ceil().clamp(1, 52);

  Map<String, Object> toJson() => {
    'kind': kind.name,
    'kgPerWeek': kgPerWeek,
    'weeks': weeks,
    'untilKg': ?untilKg,
  };

  static DietPhase fromJson(Map<dynamic, dynamic> json) {
    final weeks = json['weeks'] as int;
    if (weeks < 1) throw FormatException('A phase needs a week', '$weeks');
    return DietPhase(
      kind: PhaseKind.values.byName(json['kind'] as String),
      kgPerWeek: (json['kgPerWeek'] as num).toDouble(),
      weeks: weeks,
      untilKg: (json['untilKg'] as num?)?.toDouble(),
    );
  }
}

/// MacroFactor's diet phases: cut, maintenance and bulk one after another
/// from [start]; maintenance once the last ends. A plan made by the goal
/// planner is the goal: it keeps the [targetKg] it was planned to and how
/// often it was [extensions] extended.
class PhasePlan {
  final DateTime start;
  final List<DietPhase> phases;

  /// The trend weight when the plan was made; null in a plan from before
  /// weights were kept, which estimates none.
  final double? startKg;

  /// The weight the goal ends at; null for a maintenance goal, or a plan
  /// from before the goal planner.
  final double? targetKg;
  final int extensions;

  const PhasePlan({
    required this.start,
    required this.phases,
    this.startKg,
    this.targetKg,
    this.extensions = 0,
  });

  /// The goal's kind: the first phase that is not maintenance, as diet
  /// breaks are; maintenance when every one is.
  PhaseKind get kind => phases
      .map((p) => p.kind)
      .firstWhere(
        (k) => k != PhaseKind.maintain,
        orElse: () => PhaseKind.maintain,
      );

  /// The rough weight phase [index] starts at, the end weight for
  /// `phases.length`: [startKg] moved by each phase's pace and weeks, a
  /// phase to a weight stopping there.
  double? weightAt(int index) {
    final from = startKg;
    if (from == null) return null;
    var kg = from;
    for (final p in phases.take(index)) {
      final moved = kg + p.kgPerWeek * p.weeks;
      final until = p.untilKg;
      kg = until == null || (until - kg) * p.kgPerWeek <= 0
          ? moved
          : p.kgPerWeek < 0
          ? (moved < until ? until : moved)
          : (moved > until ? until : moved);
    }
    return kg;
  }

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
    'startKg': ?startKg,
    'targetKg': ?targetKg,
    if (extensions > 0) 'extensions': extensions,
  };

  static PhasePlan fromJson(Map<dynamic, dynamic> json) => PhasePlan(
    start: DateTime.parse(json['start'] as String),
    startKg: (json['startKg'] as num?)?.toDouble(),
    targetKg: (json['targetKg'] as num?)?.toDouble(),
    extensions: json['extensions'] as int? ?? 0,
    phases: [
      for (final p in json['phases'] as List) DietPhase.fromJson(p as Map),
    ],
  );
}

/// The plan, per profile in the fork's box beside the adaptive state, and
/// which phase was last put into the profile.
class PhaseStore {
  static const planKey = 'phasePlan';

  /// The goals completed, oldest first ([GoalRecord]).
  static const historyKey = 'goalHistory';
  static const _appliedKey = 'phaseApplied';

  /// The goals planned to follow the running one, in order ([PhasePlan]).
  static const upcomingKey = 'goalsUpcoming';

  /// The goal planner's milestone step: its place in the unit's list
  /// (`milestoneStepsKg`, `milestoneStepsLb`) from 1, 0 for none.
  static const milestoneKey = 'milestoneStep';

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

  /// The goals after the running one, in the order they run.
  Future<List<PhasePlan>> upcoming() async => [
    for (final json
        in (await _box()).get(upcomingKey, defaultValue: []) as List)
      PhasePlan.fromJson(json as Map),
  ];

  Future<void> saveUpcoming(List<PhasePlan> plans) async {
    final box = await _box();
    if (plans.isEmpty) {
      await box.delete(upcomingKey);
    } else {
      await box.put(upcomingKey, [for (final p in plans) p.toJson()]);
    }
    changes.value++;
  }

  Future<List<GoalRecord>> history() async => [
    for (final json in (await _box()).get(historyKey, defaultValue: []) as List)
      GoalRecord.fromJson(json as Map),
  ];

  /// Keeps [records] among the completed goals, replacing one that started
  /// and ended the same days (a backup restored twice), oldest first.
  Future<void> addToHistory(List<GoalRecord> records) async {
    final byDays = {
      for (final r in [...await history(), ...records]) (r.start, r.end): r,
    };
    final all = byDays.values.toList()
      ..sort((a, b) => a.start.compareTo(b.start));
    await (await _box()).put(historyKey, [for (final r in all) r.toJson()]);
    changes.value++;
  }

  /// 0 for anything but a step's place, as a hand-edited backup may hold.
  Future<int> milestoneStep() async {
    final step = (await _box()).get(milestoneKey, defaultValue: 0);
    return step is int && step >= 0 && step <= milestoneStepsKg.length
        ? step
        : 0;
  }

  Future<void> saveMilestoneStep(int step) async =>
      (await _box()).put(milestoneKey, step);

  Future<String?> applied() async => (await _box()).get(_appliedKey) as String?;

  Future<void> markApplied(String key) async =>
      (await _box()).put(_appliedKey, key);
}

/// A goal once completed: its kind, its days and the trend weight on the
/// first and last; [targetKg] null for maintenance.
class GoalRecord {
  final PhaseKind kind;
  final DateTime start;
  final DateTime end;
  final double? startKg;
  final double? endKg;
  final double? targetKg;
  final int extensions;

  const GoalRecord({
    required this.kind,
    required this.start,
    required this.end,
    required this.startKg,
    required this.endKg,
    this.targetKg,
    this.extensions = 0,
  });

  /// Whole weeks, at least one.
  int get weeks {
    final days = DateTime.utc(
      end.year,
      end.month,
      end.day,
    ).difference(DateTime.utc(start.year, start.month, start.day)).inDays;
    return (days / 7).round().clamp(1, 1 << 20);
  }

  Map<String, Object> toJson() => {
    'kind': kind.name,
    'start': start.toIso8601String(),
    'end': end.toIso8601String(),
    'startKg': ?startKg,
    'endKg': ?endKg,
    'targetKg': ?targetKg,
    if (extensions > 0) 'extensions': extensions,
  };

  static GoalRecord fromJson(Map<dynamic, dynamic> json) => GoalRecord(
    kind: PhaseKind.values.byName(json['kind'] as String),
    start: DateTime.parse(json['start'] as String),
    end: DateTime.parse(json['end'] as String),
    startKg: (json['startKg'] as num?)?.toDouble(),
    endKg: (json['endKg'] as num?)?.toDouble(),
    targetKg: (json['targetKg'] as num?)?.toDouble(),
    extensions: json['extensions'] as int? ?? 0,
  );
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

  /// Starts the first queued goal, keeping the running one as completed;
  /// false when it was not.
  final Future<bool> Function(PhaseStore store, ProfileStamp startedOn)
  _startNext;

  PhaseRunner({
    PhaseStore? store,
    Future<bool> Function(double kgPerWeek, ProfileStamp startedOn)? setPace,
    DateTime Function()? clock,
    Future<bool> Function(PhaseStore store, ProfileStamp startedOn)? startNext,
  }) : _store = store ?? PhaseStore(),
       _setPace = setPace ?? _savePaceIfProfile,
       _clock = clock ?? DateTime.now,
       _startNext = startNext ?? _startNextIfProfile;

  static Future<bool> _startNextIfProfile(
    PhaseStore store,
    ProfileStamp startedOn,
  ) async {
    if (!await locator<GetUserUsecase>().hasUserData()) return false;
    final inputs = await AdaptiveService.fromLocator().goalPlan(pastDays: 1);
    return GoalActions(
      store: store,
      startedOn: startedOn,
    ).startNextIfDue(inputs?.pastTrendKg.lastOrNull);
  }

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
      final now = _clock();
      await _startDue(now, startedOn);
      final plan = await _store.plan();
      if (plan == null) return false;
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

  /// The queued goals whose day has come started in turn, each keeping
  /// the one before as completed.
  Future<void> _startDue(DateTime now, ProfileStamp startedOn) async {
    final day = DateTime(now.year, now.month, now.day);
    for (var queue = await _store.upcoming(); queue.isNotEmpty;) {
      final plan = await _store.plan();
      if (plan != null && day.isBefore(queue.first.start)) return;
      if (!await _startNext(_store, startedOn)) return;
      queue = await _store.upcoming();
    }
  }

  /// Run at start-up (seam S6): now, on every resume, on a profile switch
  /// and when the plan changes.
  static Future<void> start() async {
    final runner = PhaseRunner();
    void run() => unawaited(runner.run());
    run();
    PhaseStore.changes.addListener(run);
    locator<HiveDBProvider>().addListener(() => afterSwitch(run));
    WidgetsBinding.instance.addObserver(_Lifecycle(run));
  }

  /// A switch notifies while it holds the lock, where a stamp names no
  /// profile: [run] once it is through (from outside its zone, so the lock
  /// waits for it rather than letting this in).
  @visibleForTesting
  static void afterSwitch(void Function() run) => Zone.root.run(
    () => unawaited(withTrackedDayLock(() async {}).then((_) => run())),
  );
}

class _Lifecycle extends WidgetsBindingObserver {
  final void Function() _run;

  _Lifecycle(this._run);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _run();
  }
}
