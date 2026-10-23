import 'package:logging/logging.dart';
import 'package:opennutritracker/core/domain/entity/calories_profile_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_gender_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_weight_goal_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_tracked_day_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_user_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_weight_log_usecase.dart';
import 'package:opennutritracker/core/utils/calc/calorie_goal_calc.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_store.dart';
import 'package:opennutritracker/fork/adaptive/check_in.dart';
import 'package:opennutritracker/fork/adaptive/energy.dart';
import 'package:opennutritracker/fork/adaptive/expenditure.dart';

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

  AdaptiveService(
    this._user,
    this._weights,
    this._trackedDays,
    this._store, [
    DateTime Function()? now,
  ]) : _now = now ?? DateTime.now;

  factory AdaptiveService.fromLocator() =>
      AdaptiveService(locator(), locator(), locator(), AdaptiveStore());

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
        bodyFatPercent: bodyFatPercent(user),
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
      bodyFatPercent: bodyFatPercent(user),
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
    final start = today.subtract(const Duration(days: _historyDays - 1));
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

/// Seam S41: the fixed macros, scaled to [kcalGoal] (a weekday's shift
/// moves the grams with it), while the fixed target has them; else null
/// and upstream's percentages apply.
Future<FixedMacros?> forkMacroGoal(
  double kcalGoal, [
  AdaptiveStore? store,
]) async {
  try {
    final settings = store == null
        ? AdaptiveStore.settings.value
        : await store.read();
    final macros = settings.fixedMacros;
    if (!settings.fixedTarget || macros == null || macros.kcal <= 0) {
      return null;
    }
    final scale = kcalGoal / macros.kcal;
    return FixedMacros(
      proteinG: macros.proteinG * scale,
      carbsG: macros.carbsG * scale,
      fatG: macros.fatG * scale,
    );
  } catch (e) {
    if (store == null) rethrow;
    _log.warning('Fixed macros unreadable, using percentages: $e');
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
