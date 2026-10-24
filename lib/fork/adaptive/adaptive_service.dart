import 'package:logging/logging.dart';
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

  AdaptiveService(
    this._user,
    this._weights,
    this._trackedDays,
    this._store, [
    DateTime Function()? now,
    this._measurements,
  ]) : _now = now ?? DateTime.now;

  factory AdaptiveService.fromLocator() => AdaptiveService(
    locator(),
    locator(),
    locator(),
    AdaptiveStore(),
    null,
    MeasurementStore(),
  );

  /// The latest measured body fat % of the past 90 days, else the
  /// profile's estimate.
  Future<double> _bodyFat(UserEntity user) async =>
      await _measurements?.recentBodyFat(_now()) ?? bodyFatPercent(user);

  /// True when the switch is on and a week has passed since the last
  /// check-in, or there has been none.
  Future<bool> checkInDue() async {
    final settings = AdaptiveStore.settings.value;
    if (!settings.adaptiveTarget || settings.fixedTarget) return false;
    final last = await _store.lastCheckIn();
    return last == null ||
        _today().difference(_day(last.date)).inDays >= checkInEveryDays;
  }

  Future<CheckIn> checkIn() async {
    final user = await _user.getUserData();
    final days = (await _history()).days;
    final rate = goalRateKgPerWeek(user);
    final previous = await _store.lastCheckIn();
    return computeCheckIn(
      CheckInInputs(
        days: days,
        priorKcal: _priorKcal(user),
        goalRateKgPerWeek: rate,
        bodyFatPercent: await _bodyFat(user),
        targetWeightKg: user.targetWeightKg,
        previousTargetKcal:
            previous?.acceptedKcal ??
            CalorieGoalCalc.getTotalKcalGoal(
              user,
              0,
              caloriesTaperEnabled: user.caloriesTaperEnabled,
            ),
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

  /// Expenditure as estimated on each day since the first weigh-in in
  /// the check-in's history, with what was logged; empty with no
  /// weigh-in. The Trends card draws it whether or not the adaptive
  /// target is on.
  Future<List<ExpenditureDay>> expenditureHistory() async {
    final user = await _user.getUserData();
    final history = await _history();
    if (history.days.every((d) => d.weightKg == null)) return const [];
    final settings = _settings();
    final estimates = estimateExpenditure(
      history.days,
      priorKcal: _priorKcal(user),
      bodyFatPercent: await _bodyFat(user),
      settings: settings,
    );
    return [
      for (final (i, day) in history.days.indexed)
        ExpenditureDay(
          date: DateTime(
            history.first.year,
            history.first.month,
            history.first.day + i,
          ),
          expenditureKcal: estimates[i],
          intakeKcal: (day.intakeKcal ?? 0) >= minLoggedKcal
              ? day.intakeKcal
              : null,
          settled: i >= settings.warmupDays,
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
      expenditureKcal: estimateExpenditure(
        days,
        priorKcal: _priorKcal(user),
        bodyFatPercent: await _bodyFat(user),
        settings: settings,
      ).last,
      bodyFatPercent: await _bodyFat(user),
      targetWeightKg: user.targetWeightKg,
      paceKgPerWeek: goalRateKgPerWeek(user),
    );
  }

  /// Upstream's formula expenditure × (1 + 4 × goal rate), MacroFactor's
  /// prior.
  static double _priorKcal(UserEntity user) =>
      CalorieGoalCalc.getTdee(user) *
      (1 + 4 * goalRateKgPerWeek(user) / user.weightKG);

  static ExpenditureSettings _settings() => ExpenditureSettings(
    window: AdaptiveStore.settings.value.cycleWindow ? 28 : 20,
  );

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
    final intakes = {
      for (final day in await _trackedDays.getTrackedDaysByRange(start, today))
        _day(day.day): day.caloriesTracked,
    };
    // Start at the first weigh-in in range, so a new user's prior is not
    // pulled by empty months.
    final first = weighIns.keys
        .where((d) => !d.isBefore(start))
        .fold(today, (a, b) => b.isBefore(a) ? b : a);
    final days = [
      for (
        var d = first;
        !d.isAfter(today);
        d = DateTime(d.year, d.month, d.day + 1)
      )
        AdaptiveDay(intakeKcal: intakes[d], weightKg: weighIns[d]),
    ];
    return (first: first, days: days);
  }

  Future<void> accept(CheckIn checkIn, double targetKcal) => _store.addCheckIn(
    CheckInRecord(
      date: _now(),
      expenditureKcal: checkIn.expenditureKcal,
      proposedKcal: checkIn.proposedTargetKcal,
      acceptedKcal: targetKcal,
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

  /// False in the first two weeks, while the estimate is still the
  /// formula's prior.
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

  const ForkKcalGoal({this.target, this.weekdayOffsetKcal = 0});
}

/// Seam S12: the fixed target, or the last accepted check-in's while the
/// adaptive switch is on, shifted for [logicalToday]'s weekday; null
/// target leaves upstream's formula. Logged activities are not added to
/// either, since measured expenditure already holds them and a fixed
/// target is meant fixed, nor the kcal adjustment, since the user sets
/// the target itself. [store] is another profile's, read from its box;
/// the active profile's is [AdaptiveStore.settings].
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
    return ForkKcalGoal(
      target: base == null ? null : base + offset,
      weekdayOffsetKcal: offset,
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

/// Seam S68: whether the target of [store]'s profile (the active one's by
/// default) leaves activities out, read from its box: the settings in
/// memory may not be loaded yet (start-up) or be another profile's. False
/// when unreadable.
Future<bool> forkTargetIgnoresActivities([AdaptiveStore? store]) async =>
    (await forkKcalGoal(DateTime.now(), store ?? AdaptiveStore())).target !=
    null;

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
