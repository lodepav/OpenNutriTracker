import 'package:opennutritracker/core/data/repository/user_activity_repository.dart';
import 'package:opennutritracker/core/domain/entity/user_activity_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/core/utils/calc/day_boundary_calc.dart';
import 'package:opennutritracker/core/utils/calc/workout_compensation_calc.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_store.dart';
import 'package:opennutritracker/fork/health/steps.dart';

/// Net energy of walking: 0.1 mL O₂ per kg per metre (ACSM's walking
/// equation, horizontal term) at about 5 kcal per litre of O₂, so
/// 0.5 kcal per kg per km; resting energy is already in the estimate.
const _walkingKcalPerKgPerKm = 0.5;

/// Step length as a share of height (Hatano 1993's 0.413–0.415).
const _stepLengthPerHeight = 0.414;

/// kcal a step costs above rest, for [weightKg] and [heightCm].
double kcalPerStep(double weightKg, double heightCm) =>
    _walkingKcalPerKgPerKm *
    weightKg *
    _stepLengthPerHeight *
    heightCm /
    100 /
    1000;

/// The share of a workout's calories counted (D17): the one set, else the
/// one upstream's Health sync suggests from body composition (Careau 2021's
/// compensation), to the slider's 5% step so the share counted is the one
/// shown; [bodyFatPercent] is the measured one, if any.
double workoutShare(
  AdaptiveSettings settings,
  UserEntity user,
  double? bodyFatPercent,
) => settings.workoutSharePct == null
    ? toShareStep(
        WorkoutCompensationCalc.suggestedMultiplier(
          bodyFatPercent: bodyFatPercent,
          user: user,
        ),
      )
    : settings.workoutSharePct! / 100;

/// The most a day's counted activity adds to the daily mode's target: a
/// device's reading of one long workout can be off by hundreds, and the
/// estimate measures what the rest was worth anyway.
const maxDailyActivityKcal = 800.0;

/// [share] to the nearest 5%.
double toShareStep(double share) => (share * 20).round() / 20;

/// The activity counted on each day (D17): logged workouts, imported ones
/// at the calories the device reported, times [workoutShare]; and steps at
/// [kcalPerStep], less those taken within an imported workout, whose own
/// calories hold them.
class ActivityCounter {
  final Future<List<UserActivityEntity>> Function() _activities;
  final StepCounts _steps;
  final Future<int> Function() _dayStartOffsetMinutes;

  ActivityCounter({
    required Future<List<UserActivityEntity>> Function() activities,
    required StepCounts steps,
    required Future<int> Function() dayStartOffsetMinutes,
  }) : _activities = activities,
       _steps = steps,
       _dayStartOffsetMinutes = dayStartOffsetMinutes;

  factory ActivityCounter.fromLocator() => ActivityCounter(
    activities: () async => [
      for (final dbo
          in await locator<UserActivityRepository>().getAllUserActivityDBO())
        UserActivityEntity.fromUserActivityDBO(dbo),
    ],
    steps: StepCounts(),
    dayStartOffsetMinutes: () async =>
        (await locator<GetConfigUsecase>().getConfig())
            .dayStartOffsetTotalMinutes,
  );

  /// Counted kcal of each day from [first] to [today]. A day is missing
  /// when steps are counted and it has no count. [readHealth] false reads
  /// only the steps already kept, for the day's goal.
  Future<Map<DateTime, double>> daily({
    required DateTime first,
    required DateTime today,
    required AdaptiveSettings settings,
    required UserEntity user,
    double? bodyFatPercent,
    bool readHealth = true,
  }) async {
    final days = [
      for (
        var d = first;
        !d.isAfter(today);
        d = DateTime(d.year, d.month, d.day + 1)
      )
        d,
    ];
    final steps = settings.countSteps && await _steps.isOn()
        ? readHealth
              ? await _steps.daily(today, days.length)
              : await _steps.cached()
        : null;
    final offset = await _dayStartOffsetMinutes();
    final share = workoutShare(settings, user, bodyFatPercent);
    final workouts = <DateTime, double>{};
    final workoutSteps = <DateTime, int>{};
    for (final a in await _activities()) {
      final day = DayBoundaryCalc.dayLabelOf(a.date, offset);
      final label = DateTime(day.year, day.month, day.day);
      if (label.isBefore(first) || label.isAfter(today)) continue;
      if (settings.countWorkouts) {
        workouts[label] =
            (workouts[label] ?? 0) +
            (a.sourceReportedKcal ?? a.burnedKcal) * share;
      }
      final id = a.externalId;
      if (steps != null && id != null && a.duration > 0) {
        final end = a.date.add(Duration(seconds: (a.duration * 60).round()));
        workoutSteps[label] =
            (workoutSteps[label] ?? 0) +
            await _steps.duringWorkout(id, a.date, end, ask: readHealth);
      }
    }
    final perStep = kcalPerStep(user.weightKG, user.heightCM);
    return {
      for (final day in days)
        if (steps == null || steps[day] != null)
          day:
              (workouts[day] ?? 0) +
              (steps == null
                  ? 0
                  : (steps[day]! - (workoutSteps[day] ?? 0)).clamp(0, 1 << 30) *
                        perStep),
    };
  }
}
