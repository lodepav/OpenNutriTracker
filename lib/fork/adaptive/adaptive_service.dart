import 'dart:math';

import 'package:logging/logging.dart';
import 'package:opennutritracker/core/utils/calc/calendar_day_calc.dart';
import 'package:opennutritracker/core/domain/entity/config_entity.dart';
import 'package:opennutritracker/core/domain/entity/calories_profile_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_gender_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_weight_goal_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_tracked_day_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_user_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_weight_log_usecase.dart';
import 'package:opennutritracker/core/utils/calc/calorie_goal_calc.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/core/utils/calc/day_boundary_calc.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/fork/adaptive/activity.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_store.dart';
import 'package:opennutritracker/fork/adaptive/check_in.dart';
import 'package:opennutritracker/fork/adaptive/energy.dart';
import 'package:opennutritracker/fork/adaptive/expenditure.dart';
import 'package:opennutritracker/fork/adaptive/goal_plan.dart';
import 'package:opennutritracker/fork/adaptive/trend.dart';
import 'package:opennutritracker/fork/body/measurement_store.dart';

final _log = Logger('AdaptiveService');

/// How far back a check-in reads: long enough for the estimate to settle
/// from the prior (fork/research/phase3-simulation.md).
const _historyDays = 120;

/// Days between check-ins.
const checkInEveryDays = 7;

/// Whether a check-in is due [today], the last made on [last] (null for
/// none): a week after it, or on [weekday] (Monday 1) when one is chosen,
/// once the last falls before that weekday's latest date. A missed
/// weekday stays due until done.
bool checkInDueOn(DateTime today, DateTime? last, int? weekday) {
  if (last == null) return true;
  final lastDay = DateTime(last.year, last.month, last.day);
  if (weekday == null) {
    // Calendar days: a week across a spring-forward is 6 days 23 hours.
    return CalendarDayCalc.daysBetween(lastDay, today) >= checkInEveryDays;
  }
  final back = (today.weekday - weekday) % 7;
  final latest = DateTime(today.year, today.month, today.day - back);
  return lastDay.isBefore(latest);
}

/// Reads upstream's profile, weight log and tracked days into a check-in,
/// and gives seam S12 the target while the adaptive switch is on.
class AdaptiveService {
  final GetUserUsecase _user;
  final GetWeightLogUsecase _weights;
  final GetTrackedDayUsecase _trackedDays;
  final AdaptiveStore _store;
  final DateTime Function() _now;

  /// A measured body fat % replaces Deurenberg's estimate; null uses the
  /// estimate only.
  final MeasurementStore? _measurements;

  /// The activity the expenditure settings count (D17); null counts none.
  final ActivityCounter? _activity;

  AdaptiveService(
    this._user,
    this._weights,
    this._trackedDays,
    this._store, [
    DateTime Function()? now,
    this._measurements,
    this._activity,
  ]) : _now = now ?? DateTime.now;

  factory AdaptiveService.fromLocator() => AdaptiveService(
    locator(),
    locator(),
    locator(),
    AdaptiveStore(),
    null,
    MeasurementStore(),
    ActivityCounter.fromLocator(),
  );

  /// The latest measured body fat % of the past 90 days, else the
  /// profile's estimate.
  Future<double> _bodyFat(UserEntity user) async =>
      await _measurements?.recentBodyFat(_now()) ?? bodyFatPercent(user);

  /// True when the switch is on and a check-in is due ([checkInDueOn]),
  /// or the goal (D18) or the settings the target is built under (D20)
  /// changed since the last one.
  Future<bool> checkInDue() async {
    final settings = AdaptiveStore.settings.value;
    if (!settings.adaptiveTarget || settings.fixedTarget) return false;
    final last = await _store.lastCheckIn();
    return checkInDueOn(_today(), last?.date, settings.checkInWeekday) ||
        await goalChanged() ||
        await basisChanged();
  }

  /// The record a check-in is capped against: the last one built under
  /// [settings], looking back from the last no more than a week. A
  /// setting switched and back meets its own record again, not the one
  /// the switch made; one changed for good has none.
  static CheckInRecord? capMark(
    List<CheckInRecord> history,
    AdaptiveSettings settings,
  ) {
    if (history.isEmpty) return null;
    final last = history.last.date;
    for (final r in history.reversed) {
      if (CalendarDayCalc.daysBetween(r.date, last) > checkInEveryDays) break;
      if (!r.basisChanged(settings)) return r;
    }
    return null;
  }

  /// Whether no check-in has been accepted yet.
  Future<bool> firstCheckIn() async => await _store.lastCheckIn() == null;

  /// Whether the last check-in's target was accepted under other settings
  /// than these (D20).
  Future<bool> basisChanged() async =>
      (await _store.lastCheckIn())?.basisChanged(
        AdaptiveStore.settings.value,
      ) ??
      false;

  /// Whether the profile's pace or target weight differs from the one the
  /// last check-in set the target for (D18).
  Future<bool> goalChanged() async {
    final last = await _store.lastCheckIn();
    if (last == null) return false;
    final user = await _user.getUserData();
    return last.goalChanged(goalRateKgPerWeek(user), user.targetWeightKg);
  }

  Future<CheckIn> checkIn() async {
    final user = await _user.getUserData();
    final days = (await _history()).days;
    final rate = goalRateKgPerWeek(user);
    final history = await _store.history();
    final previous = history.lastOrNull;
    final settings = AdaptiveStore.settings.value;
    return computeCheckIn(
      CheckInInputs(
        days: days,
        priorKcal: _priorKcal(user),
        formulaKcal: previous == null ? CalorieGoalCalc.getTdee(user) : null,
        goalRateKgPerWeek: rate,
        bodyFatPercent: await _bodyFat(user),
        targetWeightKg: user.targetWeightKg,
        // A base built under other settings (one holding activity, say)
        // is no mark to cap against (D20).
        previousBaseKcal: capMark(history, settings)?.baseKcal,
        // Only a record of the same settings says what its activity was.
        previousActivityKcal: previous?.basis == settings.targetBasis
            ? previous!.activityKcal
            : null,
        maxChangeKcal: settings.maxCheckInChangeKcal,
        activityMode: settings.activityMode,
        taper: (adjustment, weight) => CalorieGoalCalc.applyTargetWeightTaper(
          baseAdjustment: adjustment,
          currentWeightKg: weight,
          targetWeightKg: user.targetWeightKg,
          goal: user.goal,
          taperEnabled: user.caloriesTaperEnabled,
        ),
        settings: _settings(),
      ),
    );
  }

  /// Accepts a due check-in as proposed when the settings say so; the
  /// check-in accepted, or null when none was due or it is asked.
  Future<CheckIn?> autoAcceptIfDue() async {
    if (!AdaptiveStore.settings.value.autoAcceptCheckIn) return null;
    if (!await checkInDue()) return null;
    final due = await checkIn();
    await accept(due, due.proposedTargetKcal);
    return due;
  }

  /// Expenditure as estimated on each day since the first weigh-in in
  /// the check-in's history, with what was logged; empty with no
  /// weigh-in. The Trends card draws it whether or not the adaptive
  /// target is on.
  Future<List<ExpenditureDay>> expenditureHistory() async {
    final user = await _user.getUserData();
    final history = await _history();
    if (history.days.every((d) => d.weightKg == null)) return const [];
    final settings = _settings();
    final run = estimateExpenditureRun(
      history.days,
      priorKcal: _priorKcal(user),
      bodyFatPercent: await _bodyFat(user),
      settings: settings,
    );
    final estimates = run.estimates;
    final days = history.days;
    return [
      for (final (i, day) in days.indexed)
        ExpenditureDay(
          date: DateTime(
            history.first.year,
            history.first.month,
            history.first.day + i,
          ),
          expenditureKcal:
              estimates[i] +
              (meanActivity(days.sublist((i - 6).clamp(0, i), i + 1)) ?? 0),
          intakeKcal: (day.intakeKcal ?? 0) >= minLoggedKcal
              ? day.intakeKcal
              : null,
          settled: run.firstUpdate != null && i >= run.firstUpdate!,
        ),
    ];
  }

  /// What the goal planner needs; null with no weigh-in yet. The past
  /// trend covers at most [pastDays].
  Future<GoalPlanInputs?> goalPlan({int pastDays = 60}) async {
    final user = await _user.getUserData();
    final days = (await _history()).days;
    final settings = _settings();
    final trend = smoothedTrend(
      dailyWeights({
        for (final (i, d) in days.indexed)
          if (d.weightKg != null) i: d.weightKg!,
      }, days.length),
      alpha: settings.alpha,
    ).whereType<double>().toList();
    if (trend.isEmpty) return null;
    return GoalPlanInputs(
      pastTrendKg: trend.length > pastDays
          ? trend.sublist(trend.length - pastDays)
          : trend,
      trendKgPerDay: trend.length > 20
          ? (trend.last - trend[trend.length - 21]) / 20
          : null,
      expenditureKcal:
          estimateExpenditure(
            days,
            priorKcal: _priorKcal(user),
            bodyFatPercent: await _bodyFat(user),
            settings: settings,
          ).last +
          (meanActivity(
                days.sublist((days.length - 7).clamp(0, days.length)),
              ) ??
              0),
      bodyFatPercent: await _bodyFat(user),
      targetWeightKg: user.targetWeightKg,
      paceKgPerWeek: goalRateKgPerWeek(user),
      kcalPerKg: settings.kcalPerKg,
    );
  }

  /// Upstream's formula expenditure × (1 + 4 × goal rate), MacroFactor's
  /// prior. Its activity level holds activity already: the estimator
  /// takes counted activity off when it starts (D17).
  static double _priorKcal(UserEntity user) =>
      CalorieGoalCalc.getTdee(user) *
      (1 + 4 * goalRateKgPerWeek(user) / user.weightKG);

  static ExpenditureSettings _settings() =>
      AdaptiveStore.settings.value.expenditure;

  /// The days a check-in reads, from the first weigh-in in the last
  /// [_historyDays] (today when there is none) to today.
  Future<({DateTime first, List<AdaptiveDay> days})> _history() async {
    final today = _today();
    final start = DateTime(
      today.year,
      today.month,
      today.day - (_historyDays - 1),
    );
    final weighIns = {
      for (final entry in await _weights.getAllEntries())
        _day(entry.date): entry.weightKg,
    };
    final skipped = AdaptiveStore.skipped.value;
    final intakes = {
      for (final day in await _trackedDays.getTrackedDaysByRange(start, today))
        if (!skipped.contains(_day(day.day)))
          _day(day.day): day.caloriesTracked,
    };
    // Start at the first weigh-in in range, so a new user's prior is not
    // pulled by empty months.
    final first = weighIns.keys
        .where((d) => !d.isBefore(start))
        .fold(today, (a, b) => b.isBefore(a) ? b : a);
    final activity = await _countedActivity(first, today);
    final days = [
      for (
        var d = first;
        !d.isAfter(today);
        d = DateTime(d.year, d.month, d.day + 1)
      )
        AdaptiveDay(
          intakeKcal: intakes[d],
          weightKg: weighIns[d],
          // Today's steps are still coming in; on a first day alone they
          // are all there is to take off the prior's activity (D19).
          activityKcal: d == today && d != first ? null : activity?[d],
        ),
    ];
    return (first: first, days: days);
  }

  /// Counted activity per day, or null when none is counted (D17). A
  /// health store that will not answer counts none rather than failing the
  /// check-in.
  Future<Map<DateTime, double>?> _countedActivity(
    DateTime first,
    DateTime today,
  ) async {
    final settings = AdaptiveStore.settings.value;
    final counter = _activity;
    if (counter == null || settings.activityMode == ActivityMode.off) {
      return null;
    }
    try {
      final user = await _user.getUserData();
      final days = await counter.daily(
        first: first,
        today: today,
        settings: settings,
        user: user,
        bodyFatPercent: await _measurements?.recentBodyFat(_now()),
      );
      // The daily target adds a day's activity up to the limit, so the
      // base takes off no more: the excess stays in it (D21).
      return settings.activityMode == ActivityMode.daily
          ? days.map((d, kcal) => MapEntry(d, min(kcal, maxDailyActivityKcal)))
          : days;
    } catch (e) {
      _log.warning('Activity unreadable, none counted: $e');
      return null;
    }
  }

  /// The counted activity of [day] alone, from the steps already read;
  /// 0 when none is counted. For the daily mode's goal.
  Future<double> activityOn(DateTime day, {bool readHealth = false}) async {
    final counter = _activity;
    if (counter == null) return 0;
    final user = await _user.getUserData();
    final d = _day(day);
    return (await counter.daily(
          first: d,
          today: d,
          settings: AdaptiveStore.settings.value,
          user: user,
          bodyFatPercent: await _measurements?.recentBodyFat(_now()),
          readHealth: readHealth,
        ))[d] ??
        0;
  }

  Future<void> accept(CheckIn checkIn, double targetKcal) => _store.addCheckIn(
    CheckInRecord(
      date: _now(),
      expenditureKcal: checkIn.expenditureKcal,
      proposedKcal: checkIn.proposedTargetKcal,
      acceptedKcal: targetKcal,
      activityKcal: checkIn.activityInTarget(
        AdaptiveStore.settings.value.activityMode,
      ),
      baseKcal: checkIn.baseKcal,
      goalRateKgPerWeek: checkIn.goalRateKgPerWeek,
      targetWeightKg: checkIn.targetWeightKg,
      basis: AdaptiveStore.settings.value.targetBasis,
    ),
  );

  DateTime _today() => _day(_now());

  static DateTime _day(DateTime t) => DateTime(t.year, t.month, t.day);
}

/// One day of [AdaptiveService.expenditureHistory].
class ExpenditureDay {
  final DateTime date;
  final double expenditureKcal;

  /// Null when the day was not logged (under [minLoggedKcal]).
  final double? intakeKcal;

  /// False until the estimate first updates, while it is the formula's
  /// prior.
  final bool settled;

  const ExpenditureDay({
    required this.date,
    required this.expenditureKcal,
    this.intakeKcal,
    required this.settled,
  });
}

/// What seam S12 makes of the kcal goal: [target] replaces upstream's
/// formula when set; otherwise the formula applies, plus
/// [weekdayOffsetKcal].
class ForkKcalGoal {
  final double? target;
  final double weekdayOffsetKcal;

  /// The daily mode's activity in [target], at most
  /// [maxDailyActivityKcal].
  final double activityKcal;

  const ForkKcalGoal({
    this.target,
    this.weekdayOffsetKcal = 0,
    this.activityKcal = 0,
  });
}

/// Seam S12: the fixed target, or the last accepted check-in's while the
/// adaptive switch is on, shifted for [logicalToday]'s weekday; null
/// target leaves upstream's formula. Logged activities are not added to
/// either through upstream's path, since measured expenditure already
/// holds them and a fixed target is meant fixed, nor the kcal adjustment,
/// since the user sets the target itself; in D17's daily mode the
/// adaptive one adds the day's counted activity itself, up to
/// [maxDailyActivityKcal]. [store] is another profile's, read from its
/// box; the active profile's is [AdaptiveStore.settings].
Future<ForkKcalGoal> forkKcalGoal(
  DateTime logicalToday, [
  AdaptiveStore? store,
]) async {
  try {
    final settings = store == null
        ? AdaptiveStore.settings.value
        : await store.read();
    final offset = settings.weekdayOffsets[logicalToday.weekday - 1];
    final base = settings.fixedTarget
        ? settings.fixedTargetKcal
        : settings.adaptiveTarget
        ? (await (store ?? AdaptiveStore()).lastCheckIn())?.acceptedKcal
        : null;
    final activity =
        base != null &&
            store == null &&
            !settings.fixedTarget &&
            settings.activityMode == ActivityMode.daily
        ? min(await _todayActivity(logicalToday), maxDailyActivityKcal)
        : 0.0;
    return ForkKcalGoal(
      target: base == null ? null : base + offset + activity,
      weekdayOffsetKcal: offset,
      activityKcal: activity,
    );
  } catch (e) {
    if (store == null) rethrow;
    // Another profile's box: the formula is a safe goal for a copied meal.
    _log.warning('Adaptive target unreadable, using the formula: $e');
    return const ForkKcalGoal();
  } finally {
    await store?.release();
  }
}

/// The daily mode's activity for the active profile's [day] (D17), from
/// the steps already read; 0 when it cannot be read, so the goal is the
/// check-in's alone rather than none.
Future<double> _todayActivity(DateTime day) async {
  try {
    return await AdaptiveService.fromLocator().activityOn(day);
  } catch (e) {
    _log.warning('Activity unreadable, none added to the goal: $e');
    return 0;
  }
}

/// Seams S63–S67 and S69: [goal], which carries logical today's weekday
/// shift, moved to [day]'s, for a row made for another day (a copy, a past
/// day's log). [store] and [config] are another profile's (S69); its
/// settings, unreadable, leave [goal] as it is.
Future<double> forkGoalOnDay(
  double goal,
  DateTime day, {
  AdaptiveStore? store,
  Future<ConfigEntity> Function()? config,
}) async {
  final List<double> offsets;
  try {
    offsets =
        (store == null ? AdaptiveStore.settings.value : await store.read())
            .weekdayOffsets;
  } catch (e) {
    _log.warning('Adaptive settings unreadable, no weekday shift: $e');
    return goal;
  } finally {
    await store?.release();
  }
  if (offsets.every((o) => o == 0)) return goal;
  final read = await (config ?? locator<GetConfigUsecase>().getConfig)();
  final offset = read.dayStartOffsetTotalMinutes;
  final today = DayBoundaryCalc.currentLogicalDayMinutes(offset);
  final label = DayBoundaryCalc.dayLabelOf(day, offset);
  return goal - offsets[today.weekday - 1] + offsets[label.weekday - 1];
}

/// Seam S62: whether [day]'s goal leaves logged activities out (a fixed
/// target, or an accepted adaptive one), so logging, editing or deleting
/// an activity does not move the goal stored for that day either.
Future<bool> forkGoalIgnoresActivities(DateTime day) async =>
    (await forkKcalGoal(day)).target != null;

/// Seam S68: what the reconciler needs of the target of [store]'s profile
/// (the active one's by default), read from its box: the settings in
/// memory may not be loaded yet (start-up) or be another profile's.
/// Whether it leaves activities out (false when unreadable), the weekday
/// shifts its rows carry (none when unreadable), and whether their macro
/// goals follow the energy: not under a macro program, whose protein
/// follows the body ([forkMacroGoal]).
Future<({bool ignoreBurned, List<double> offsets, bool scaleMacros})>
forkReconcileTarget([AdaptiveStore? store]) async {
  store ??= AdaptiveStore();
  final ignoreBurned =
      (await forkKcalGoal(DateTime.now(), store)).target != null;
  try {
    final settings = await store.read();
    final fixedMacros = settings.fixedMacros;
    return (
      ignoreBurned: ignoreBurned,
      offsets: settings.weekdayOffsets,
      scaleMacros:
          settings.macroProgram == null ||
          (settings.fixedTarget && fixedMacros != null && fixedMacros.kcal > 0),
    );
  } catch (e) {
    _log.warning('Adaptive settings unreadable, no weekday shift: $e');
    return (
      ignoreBurned: ignoreBurned,
      offsets: const <double>[],
      scaleMacros: true,
    );
  } finally {
    await store.release();
  }
}

/// Seam S41: the macro goals for a day's [kcalGoal], or null for
/// upstream's percentages. The fixed target's grams, scaled to the goal (a
/// weekday's shift moves them with it), while it has them; else the macro
/// program's, from [user]'s weight and body fat (the measured one of the
/// past 90 days for the active profile, Deurenberg's estimate for another
/// or without one).
Future<FixedMacros?> forkMacroGoal(
  double kcalGoal, [
  AdaptiveStore? store,
  Future<UserEntity> Function()? user,
]) async {
  try {
    final settings = store == null
        ? AdaptiveStore.settings.value
        : await store.read();
    final macros = settings.fixedMacros;
    if (settings.fixedTarget && macros != null && macros.kcal > 0) {
      final scale = kcalGoal / macros.kcal;
      return FixedMacros(
        proteinG: macros.proteinG * scale,
        carbsG: macros.carbsG * scale,
        fatG: macros.fatG * scale,
      );
    }
    final program = settings.macroProgram;
    if (program == null) return null;
    final profile = await (user ?? locator<GetUserUsecase>().getUserData)();
    final measured = store == null
        ? await MeasurementStore().recentBodyFat(DateTime.now())
        : null;
    return program.macrosFor(
      kcal: kcalGoal,
      weightKg: profile.weightKG,
      bodyFatPercent: measured ?? bodyFatPercent(profile),
    );
  } catch (e) {
    if (store == null) rethrow;
    _log.warning('Macro goals unreadable, using percentages: $e');
    return null;
  } finally {
    await store?.release();
  }
}

/// The chosen pace in kg/week, negative to lose; upstream's ±500 kcal
/// goal read as 0.5 kg/week when no pace was set.
double goalRateKgPerWeek(UserEntity user) =>
    user.weeklyWeightGoalKg ??
    switch (user.goal) {
      UserWeightGoalEntity.loseWeight => -0.5,
      UserWeightGoalEntity.maintainWeight => 0,
      UserWeightGoalEntity.gainWeight => 0.5,
    };

/// Deurenberg's estimate for the profile; the sex term follows the
/// calories profile for non-binary users, as upstream's TDEE does.
double bodyFatPercent(UserEntity user) {
  final heightM = user.heightCM / 100;
  return deurenbergBodyFatPercent(
    bmi: user.weightKG / (heightM * heightM),
    age: user.age.toDouble(),
    sex: switch (user.gender) {
      UserGenderEntity.male => 1,
      UserGenderEntity.female => 0,
      UserGenderEntity.nonBinary => switch (user.caloriesProfile) {
        CaloriesProfileEntity.testosteroneTypical => 1,
        CaloriesProfileEntity.estrogenTypical => 0,
        CaloriesProfileEntity.averaged || null => 0.5,
      },
    },
  );
}
