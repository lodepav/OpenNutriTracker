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
    if (!AdaptiveStore.settings.value.adaptiveTarget) return false;
    final last = await _store.lastCheckIn();
    return last == null ||
        _today().difference(_day(last.date)).inDays >= checkInEveryDays;
  }

  Future<CheckIn> checkIn() async {
    final user = await _user.getUserData();
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

    final rate = goalRateKgPerWeek(user);
    final previous = await _store.lastCheckIn();
    return computeCheckIn(
      CheckInInputs(
        days: days,
        priorKcal:
            CalorieGoalCalc.getTdee(user) * (1 + 4 * rate / user.weightKG),
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
        settings: ExpenditureSettings(
          window: AdaptiveStore.settings.value.cycleWindow ? 28 : 20,
        ),
      ),
    );
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

/// Seam S12: the last accepted target while the switch is on, else null
/// and upstream's formula applies. Logged activities are not added to it,
/// since measured expenditure already holds them, nor the kcal adjustment,
/// since the user sets the target itself at each check-in. [store] is
/// another profile's, whose switch is read from its box; the active
/// profile's is [AdaptiveStore.settings].
Future<double?> adaptiveTargetKcal([AdaptiveStore? store]) async {
  if (store == null) {
    if (!AdaptiveStore.settings.value.adaptiveTarget) return null;
    return (await AdaptiveStore().lastCheckIn())?.acceptedKcal;
  }
  try {
    if (!(await store.read()).adaptiveTarget) return null;
    return (await store.lastCheckIn())?.acceptedKcal;
  } catch (e) {
    // Another profile's box: the formula is a safe goal for a copied meal.
    _log.warning('Adaptive target unreadable, using the formula: $e');
    return null;
  } finally {
    await store.release();
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
