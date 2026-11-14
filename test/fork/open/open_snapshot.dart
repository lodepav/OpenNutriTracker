import 'dart:convert';
import 'dart:math';

import 'package:collection/collection.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/domain/entity/recipe_entity.dart';
import 'package:opennutritracker/core/domain/entity/tracked_day_entity.dart';
import 'package:opennutritracker/core/domain/entity/config_entity.dart';
import 'package:opennutritracker/core/utils/calc/calendar_day_calc.dart';
import 'package:opennutritracker/core/utils/calc/calorie_goal_calc.dart';
import 'package:opennutritracker/core/utils/calc/day_boundary_calc.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/meal_detail/util/meal_quantity_converter.dart';
import 'package:opennutritracker/fork/adaptive/activity_credit.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_service.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_store.dart';
import 'package:opennutritracker/fork/adaptive/check_in.dart';
import 'package:opennutritracker/fork/adaptive/macro_program.dart';
import 'package:opennutritracker/fork/amounts/amount_units.dart';
import 'package:opennutritracker/fork/amounts/own_portions.dart';
import 'package:opennutritracker/fork/amounts/remembered_amounts.dart';
import 'package:opennutritracker/fork/body/measurement_store.dart';
import 'package:opennutritracker/fork/display/display_prefs.dart';
import 'package:opennutritracker/fork/fasting/fasting_view.dart';
import 'package:opennutritracker/fork/goal/goal_planner.dart';
import 'package:opennutritracker/fork/goal/goal_progress.dart';
import 'package:opennutritracker/fork/meal_detail/unit_change.dart';
import 'package:opennutritracker/fork/phase/shared_phase.dart';
import 'package:opennutritracker/fork/phases/phase_report.dart';
import 'package:opennutritracker/fork/phases/phases.dart';
import 'package:opennutritracker/fork/recipe/recipe_page.dart';
import 'package:opennutritracker/fork/reminders/reminders.dart';
import 'package:opennutritracker/fork/report/weekly_report.dart';
import 'package:opennutritracker/fork/trends/detail_stats.dart';
import 'package:opennutritracker/fork/trends/trend_stats.dart';

import 'open_fixture.dart';

/// The settings variants the goals are read under: each gate the fork puts
/// on upstream's numbers, one at a time over [openBaseSettings].
final openVariants = <String, AdaptiveSettings>{
  'formula': openBaseSettings,
  'adaptive': openBaseSettings.copyWith(adaptiveTarget: true),
  'adaptiveFlat': openBaseSettings.copyWith(
    adaptiveTarget: true,
    flatEnergy: true,
  ),
  'activityWeekly': openBaseSettings.copyWith(
    adaptiveTarget: true,
    activityMode: ActivityMode.weekly,
  ),
  'activityDaily': openBaseSettings.copyWith(
    adaptiveTarget: true,
    activityMode: ActivityMode.daily,
  ),
  'fixed': openBaseSettings.copyWith(fixedTarget: true, fixedKcal: 2100),
  'fixedGrams': openBaseSettings.copyWith(
    fixedTarget: true,
    fixedMacros: () =>
        const FixedMacros(proteinG: 160, carbsG: 220, fatG: 70),
  ),
  // On the formula's cut: the 20% fat floor holds fat up.
  'programCut': openBaseSettings.copyWith(
    macroProgram: () => const MacroProgram(proteinGPerKg: 2.2),
  ),
  // A small target: protein is held to 60% of it.
  'programLow': openBaseSettings.copyWith(
    fixedTarget: true,
    fixedKcal: 1100,
    macroProgram: () => const MacroProgram(proteinGPerKg: 2.2),
  ),
};

/// The weekday the shifted goals are read for: a Wednesday, three days
/// before the snapshot's Saturday.
const openShiftedDay = -3;

/// The past day the diary section opens: a Thursday with a workout.
const openDiaryDay = -2;

/// What the user sees when they open the app over [f], as plain JSON:
/// doubles to two decimals, days relative to today (`d0`, `d-3`), no
/// absolute date and no generated id.
Future<Map<String, dynamic>> openSnapshot(OpenFixture f) async {
  final locale = Intl.defaultLocale;
  // checkInMessage formats numbers in the default locale.
  Intl.defaultLocale = 'en_US';
  try {
    return _plain(await _Snapshot(f).take()) as Map<String, dynamic>;
  } finally {
    Intl.defaultLocale = locale;
    DayBoundaryCalc.clock = () => f.now;
  }
}

class _Snapshot {
  final OpenFixture f;

  _Snapshot(this.f);

  String day(DateTime d) {
    final n = CalendarDayCalc.daysBetween(
      f.today,
      DateTime(d.year, d.month, d.day),
    );
    return n == 0 ? 'd0' : (n > 0 ? 'd+$n' : 'd$n');
  }

  String moment(DateTime t) =>
      '${day(t)} ${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}';

  List<DateTime> get window => windowDates(f.today, 30);

  /// Runs [body] under [settings], then puts the base ones back.
  Future<T> under<T>(AdaptiveSettings settings, Future<T> Function() body) async {
    await AdaptiveStore().save(settings);
    try {
      return await body();
    } finally {
      await AdaptiveStore().save(openBaseSettings);
      DayBoundaryCalc.clock = () => f.now;
    }
  }

  Future<Map<String, dynamic>> take() async => {
    'settings': await settings(),
    'goals': await goals(),
    'home': await home(),
    'diary': await diary(),
    'mealEntry': await mealEntry(),
    'recipes': {
      'Chili': await recipe(f.chili),
      'Pasta bake': await recipe(f.pastaBake),
    },
    'customFood': await customFood(),
    'trends': await trends(),
    'stats': await stats(),
    'adaptive': await adaptive(),
    'phases': await phases(),
    'goal': await goal(),
    'fasting': await fasting(),
    'reminders': await reminders(),
  };

  Future<Map<String, dynamic>> settings() async {
    final user = await f.user.getUserData();
    final config = await f.config.getConfig();
    Map<String, dynamic> display() => {
      'macroOrder': [for (final m in DisplayPrefs.macroOrder.value) m.name],
      'diaryByHour': DisplayPrefs.diaryByHour.value,
      'homeShowsEaten': DisplayPrefs.homeShowsEaten.value,
      'showWater': DisplayPrefs.showWater.value,
      'showFasting': DisplayPrefs.showFasting.value,
    };
    final shown = display();
    await DisplayPrefs.setShowWater(false);
    await DisplayPrefs.setShowFasting(false);
    await DisplayPrefs.reload();
    final hidden = display();
    await DisplayPrefs.setShowWater(true);
    await DisplayPrefs.setShowFasting(true);
    return {
      'adaptive': AdaptiveStore.settings.value.toJson(),
      'display': shown,
      'displayWaterFastingOff': hidden,
      'profile': {
        'age': user.age,
        'heightCm': user.heightCM,
        'weightKg': user.weightKG,
        'gender': user.gender.name,
        'goal': user.goal.name,
        'pal': user.pal.name,
        'weeklyWeightGoalKg': user.weeklyWeightGoalKg,
        'targetWeightKg': user.targetWeightKg,
        'taper': user.caloriesTaperEnabled,
        'formulaTdee': CalorieGoalCalc.getTdee(user),
        'bodyFatMeasured': await MeasurementStore().recentBodyFat(f.now),
        'bodyFatEstimate': bodyFatPercent(user),
      },
      'config': {
        'carbPct': config.userCarbGoalPct,
        'fatPct': config.userFatGoalPct,
        'proteinPct': config.userProteinGoalPct,
        'kcalAdjustment': config.userKcalAdjustment,
        'dayStartMinutes': config.dayStartOffsetTotalMinutes,
      },
    };
  }

  /// Upstream's goals as Home asks for them at [at]; the clock is back at
  /// [OpenFixture.now] after.
  Future<Map<String, dynamic>> goalsAt(DateTime at) async {
    DayBoundaryCalc.clock = () => at;
    try {
      final user = await f.user.getUserData();
      final kcal = await f.kcalGoal.getKcalGoal(userEntity: user);
      return {
        'kcal': kcal,
        'carbs': await f.macroGoal.getCarbsGoal(kcal),
        'fat': await f.macroGoal.getFatsGoal(kcal),
        'protein': await f.macroGoal.getProteinsGoal(kcal),
      };
    } finally {
      DayBoundaryCalc.clock = () => f.now;
    }
  }

  /// How much logging an activity of 300 kcal moves today's stored goal,
  /// through upstream's path and seam S62; put back after.
  Future<double> storedGoalMove() async {
    final d0 = f.day(0);
    final before = (await f.trackedDays.getTrackedDay(d0))!.calorieGoal;
    await f.addTrackedDay.increaseDayCalorieGoal(d0, 300);
    final after = (await f.trackedDays.getTrackedDay(d0))!.calorieGoal;
    await f.addTrackedDay.reduceDayCalorieGoal(d0, 300);
    return after - before;
  }

  Future<Map<String, dynamic>> goals() async => {
    for (final MapEntry(key: name, value: settings) in openVariants.entries)
      name: await under(settings, () async {
        final d0 = await goalsAt(f.now);
        final fork = await forkKcalGoal(f.today);
        return {
          'd0': {
            ...d0,
            'weekdayShift': fork.weekdayOffsetKcal,
            'activityKcal': fork.activityKcal,
            'activityCredit': (await activityCredit()).name,
            'storedGoalMoveFor300': await storedGoalMove(),
          },
          'd$openShiftedDay': await goalsAt(f.at(openShiftedDay, 14)),
          // S63: a row written today for that day.
          'rowWrittenTodayFor d$openShiftedDay': await forkGoalOnDay(
            d0['kcal'] as double,
            f.day(openShiftedDay),
          ),
        };
      }),
  };

  /// Home's numbers for logical today, as HomeBloc reads them.
  Future<Map<String, dynamic>> homeNow() async {
    final config = await f.config.getConfig();
    final h = config.dayStartOffsetHours, m = config.dayStartOffsetMinutes;
    final meals = {
      ConfigEntity.mealKeyBreakfast: await f.intakes.getTodayBreakfastIntake(
        dayStartOffsetHours: h,
        dayStartOffsetMinutes: m,
      ),
      ConfigEntity.mealKeyLunch: await f.intakes.getTodayLunchIntake(
        dayStartOffsetHours: h,
        dayStartOffsetMinutes: m,
      ),
      ConfigEntity.mealKeyDinner: await f.intakes.getTodayDinnerIntake(
        dayStartOffsetHours: h,
        dayStartOffsetMinutes: m,
      ),
      ConfigEntity.mealKeySnack: await f.intakes.getTodaySnackIntake(
        dayStartOffsetHours: h,
        dayStartOffsetMinutes: m,
      ),
    };
    final all = meals.values.expand((l) => l).toList();
    final eaten = all.map((i) => i.totalKcal).sum;
    final burned = (await f.activities.getTodayUserActivity(
      dayStartOffsetHours: h,
      dayStartOffsetMinutes: m,
    )).map((a) => a.burnedKcal).sum;
    final user = await f.user.getUserData();
    final goal = await f.kcalGoal.getKcalGoal(userEntity: user);
    return {
      'day': day(DayBoundaryCalc.currentLogicalDayMinutes(
        config.dayStartOffsetTotalMinutes,
      )),
      'goal': goal,
      'eaten': eaten,
      'burned': burned,
      'left': CalorieGoalCalc.getDailyKcalLeft(goal, eaten),
      'carbs': {
        'eaten': all.map((i) => i.totalCarbsGram).sum,
        'goal': await f.macroGoal.getCarbsGoal(goal),
      },
      'fat': {
        'eaten': all.map((i) => i.totalFatsGram).sum,
        'goal': await f.macroGoal.getFatsGoal(goal),
      },
      'protein': {
        'eaten': all.map((i) => i.totalProteinsGram).sum,
        'goal': await f.macroGoal.getProteinsGoal(goal),
      },
      'meals': {
        for (final MapEntry(key: meal, value: list) in meals.entries)
          meal: {
            'kcal': list.map((i) => i.totalKcal).sum,
            'target': config.targetKcalForMeal(meal, goal),
          },
      },
    };
  }

  Future<Map<String, dynamic>> home() async => {
    for (final name in ['formula', 'adaptive', 'activityDaily', 'fixed'])
      name: await under(openVariants[name]!, homeNow),
    // Two in the morning after today, before a 04:00 day start: still today.
    'dayStart4h': await () async {
      await f.configSource.setConfigDayStartOffset(4, 0);
      DayBoundaryCalc.clock = () => f.at(1, 2);
      try {
        return await homeNow();
      } finally {
        await f.configSource.setConfigDayStartOffset(0, 0);
        DayBoundaryCalc.clock = () => f.now;
      }
    }(),
  };

  Map<String, dynamic> entry(IntakeEntity i) => {
    'name': i.meal.name,
    'meal': i.type.name,
    'amount': i.amount,
    'unit': i.unit,
    'kcal': i.totalKcal,
    'carbs': i.totalCarbsGram,
    'fat': i.totalFatsGram,
    'protein': i.totalProteinsGram,
  };

  Map<String, dynamic> row(TrackedDayEntity? d) => d == null
      ? {}
      : {
          'calorieGoal': d.calorieGoal,
          'caloriesTracked': d.caloriesTracked,
          'carbsGoal': d.carbsGoal,
          'carbsTracked': d.carbsTracked,
          'fatGoal': d.fatGoal,
          'fatTracked': d.fatTracked,
          'proteinGoal': d.proteinGoal,
          'proteinTracked': d.proteinTracked,
        };

  Future<Map<String, dynamic>> diary() async {
    final d = f.day(openDiaryDay);
    final entries = [
      ...await f.intakes.getBreakfastIntakeByDay(d),
      ...await f.intakes.getLunchIntakeByDay(d),
      ...await f.intakes.getDinnerIntakeByDay(d),
      ...await f.intakes.getSnackIntakeByDay(d),
    ];
    // The box keys are random ids, so their order is not the log's.
    entries.sort(
      (a, b) => a.type.index != b.type.index
          ? a.type.index - b.type.index
          : a.meal.name!.compareTo(b.meal.name!),
    );
    return {
      'day': day(d),
      'entries': [for (final i in entries) entry(i)],
      // DayTotalsCard's sum, one layer below it.
      'totals': {
        'kcal': entries.map((i) => i.totalKcal).sum,
        'carbs': entries.map((i) => i.totalCarbsGram).sum,
        'fat': entries.map((i) => i.totalFatsGram).sum,
        'protein': entries.map((i) => i.totalProteinsGram).sum,
      },
      'burned': (await f.activities.getUserActivityByDay(
        d,
      )).map((a) => a.burnedKcal).sum,
      'storedGoal': row(await f.trackedDays.getTrackedDay(d)),
      'dayWithoutActivity': {
        'day': day(f.day(openShiftedDay)),
        ...row(await f.trackedDays.getTrackedDay(f.day(openShiftedDay))),
      },
    };
  }

  List<Map<String, dynamic>> units(MealEntity meal, String selected) => [
    for (final o in amountUnitOptions(meal, selected: selected, imperial: false))
      {
        'name': o.unit,
        'label': o.portionLabel,
        'grams': o.grams,
        'own': o.own,
      },
  ];

  Map<String, dynamic> steps(String unit, double from) {
    final step = amountStep(unit, from);
    return {
      'from': from,
      'step': step,
      'up': steppedAmount(from, step, up: true),
      'down': steppedAmount(from, step, up: false),
    };
  }

  Future<Map<String, dynamic>> remembered(MealEntity meal) async {
    final stored = await RememberedAmounts().of(meal);
    return stored == null
        ? {}
        : {
            'unit': stored.unit,
            'quantity': stored.quantity,
            'opensAt': unitFromRemembered(meal, stored.unit),
          };
  }

  Future<Map<String, dynamic>> mealEntry() async {
    final bread = f.bread;
    final breadUnits = amountUnitOptions(bread, selected: 'serving', imperial: false);
    final fits = portionThatFits(bread, breadUnits, 'g', 64);
    final apple = withOwnPortions(f.apple, await OwnPortions().of(f.apple));
    final chili = f.chili.toMealEntity();
    return {
      'bread': {
        'units': units(bread, 'serving'),
        'remembered': await remembered(bread),
        '180 g as serving': amountInUnit('180', 'g', 'serving', bread),
        '2 servings as g': amountInUnit('2', 'serving', 'g', bread),
        'kcal for 2 servings': kcalForQuantity(2, 'serving', bread),
        'stepServing': steps('serving', 2),
        'stepGrams': steps('g', 64),
        '64 g fits': fits == null
            ? null
            : {'unit': fits.option.unit, 'count': fits.count},
      },
      'apple': {
        'units': units(apple, 'serving'),
        'remembered': await remembered(apple),
        '360 g as own portion': amountInUnit('360', 'g', 'serving', apple),
        'kcal for 1 own portion': kcalForQuantity(1, 'serving', apple),
        'stepHalf': steps('serving', 0.5),
        'stepOne': steps('serving', 1),
      },
      'milk': {
        'units': units(f.milk, 'ml'),
        'remembered': await remembered(f.milk),
        'kcal for 250 ml': kcalForQuantity(250, 'ml', f.milk),
        'stepMl': steps('ml', 250),
      },
      'chili': {
        'units': units(chili, 'serving'),
        'remembered': await remembered(chili),
        '180 g as serving': amountInUnit('180', 'g', 'serving', chili),
        'kcal for 1 serving': kcalForQuantity(1, 'serving', chili),
        'portions': [
          for (final count in [0.5, 1.0, 1.5, 2.0])
            {
              'name': RecipePortion(f.chili, count).label,
              'grams': RecipePortion(f.chili, count).grams,
            },
        ],
        'pastaBakePortion': {
          'name': RecipePortion(f.pastaBake, 1).label,
          'grams': RecipePortion(f.pastaBake, 1).grams,
        },
      },
    };
  }

  /// [grams] of [meal] as the diary would hold it.
  Map<String, dynamic> logged(MealEntity meal, String unit, double grams) {
    final i = IntakeEntity(
      id: 'open',
      unit: unit,
      amount: grams,
      type: IntakeTypeEntity.dinner,
      meal: meal,
      dateTime: f.now,
    );
    return {
      'grams': grams,
      'kcal': i.totalKcal,
      'carbs': i.totalCarbsGram,
      'fat': i.totalFatsGram,
      'protein': i.totalProteinsGram,
    };
  }

  Map<String, dynamic> per100(MealEntity meal) => {
    'kcal': meal.nutriments.energyKcal100,
    'carbs': meal.nutriments.carbohydrates100,
    'fat': meal.nutriments.fat100,
    'protein': meal.nutriments.proteins100,
  };

  Future<Map<String, dynamic>> recipe(RecipeEntity r) async {
    final meal = r.toMealEntity();
    return {
      'servings': r.servingsCount,
      'totalWeightG': r.totalWeightG,
      'per100': per100(meal),
      'perServing': logged(
        meal,
        'serving',
        convertQuantityToBaseUnit(1, 'serving', meal),
      ),
      'asMeal': {
        'mealQuantity': meal.mealQuantity,
        'mealUnit': meal.mealUnit,
        'servingQuantity': meal.servingQuantity,
        'servingUnit': meal.servingUnit,
        'servingSize': meal.servingSize,
        'source': meal.source.name,
      },
    };
  }

  Future<Map<String, dynamic>> customFood() async {
    final meal = MealEntity.fromMealDBO(f.customMeals.getAllCustomMeals().single);
    return {
      'name': meal.name,
      'per100': per100(meal),
      'servingSize': meal.servingSize,
      'perServing': logged(
        meal,
        'serving',
        convertQuantityToBaseUnit(1, 'serving', meal),
      ),
    };
  }

  List<double?> tail(List<double?> series, [int n = 5]) =>
      series.sublist(max(0, series.length - n));

  Future<Map<String, dynamic>> trends() async {
    final dates = window;
    final days = await f.trackedDays.getTrackedDaysByRange(dates.first, f.today);
    final history = await f.service().expenditureHistory();
    final weight = WeightTrendStats.of(await f.weights.getAllEntries(), dates);
    final balance = balanceSeries(history, dates);
    double? mean(double? Function(TrackedDayEntity) of) =>
        meanOf(nutritionSeries(days, dates, of));
    double? goal(double? Function(TrackedDayEntity) of) =>
        goalOf(days, dates, of);
    return {
      'weight': {
        'nowKg': weight.nowKg,
        'changeKg': weight.changeKg,
        'perWeekKg': weight.perWeekKg,
        'trendTail': tail(weight.trend),
      },
      'eaten': {
        'kcal': mean((d) => d.caloriesTracked),
        'carbs': mean((d) => d.carbsTracked),
        'fat': mean((d) => d.fatTracked),
        'protein': mean((d) => d.proteinTracked),
        'loggedDays': nutritionSeries(
          days,
          dates,
          (d) => d.caloriesTracked,
        ).nonNulls.length,
      },
      'goal': {
        'kcal': goal((d) => d.calorieGoal),
        'carbs': goal((d) => d.carbsGoal),
        'fat': goal((d) => d.fatGoal),
        'protein': goal((d) => d.proteinGoal),
      },
      // What goalOf must not be: every stored row, logged or not.
      'goalKcalOverAllRows': meanOf([for (final d in days) d.calorieGoal]),
      'expenditureTail': tail(expenditureSeries(history, dates)),
      'balance': {'mean': meanOf(balance), 'days': balance.nonNulls.length},
    };
  }

  Map<String, dynamic>? dayValue(DayValue? v) =>
      v == null ? null : {'value': v.value, 'day': day(v.date)};

  Map<String, dynamic>? versus(Versus? v) =>
      v == null ? null : {'eaten': v.eaten, 'goal': v.goal};

  Future<Map<String, dynamic>> stats() async {
    final dates = window;
    final days = await f.trackedDays.getTrackedDaysByRange(dates.first, f.today);
    final history = await f.service().expenditureHistory();
    final outcomes = dayOutcomes(days, dates, today: f.today);
    final shares = macroShares(days, dates);
    final balance = balanceSummary(history, dates, today: f.today);
    final logging = loggingCompleteness(
      days,
      history,
      dates,
      AdaptiveStore.skipped.value,
    );
    final breakdown = expenditureBreakdown(history);
    return {
      'dayOutcomes': {
        'onTarget': outcomes.onTarget,
        'under': outcomes.under,
        'over': outcomes.over,
        'logged': outcomes.logged,
        'highest': dayValue(outcomes.highest),
        'lowest': dayValue(outcomes.lowest),
      },
      'macroShares': shares == null
          ? null
          : {
              'eaten': {
                'carbs': shares.eaten.carbs,
                'fat': shares.eaten.fat,
                'protein': shares.eaten.protein,
              },
              'goal': shares.goal == null
                  ? null
                  : {
                      'carbs': shares.goal!.carbs,
                      'fat': shares.goal!.fat,
                      'protein': shares.goal!.protein,
                    },
            },
      'balanceSummary': balance == null
          ? null
          : {
              'eaten': balance.eaten,
              'burnt': balance.burnt,
              'total': balance.total,
              'deficit': balance.deficit,
              'surplus': balance.surplus,
              'finished': balance.finished,
              'logged': balance.logged,
            },
      'loggingCompleteness': {
        'of': logging.of,
        'logged': logging.logged,
        'counted': logging.counted,
        'skipped': logging.skipped,
        'partial': logging.partial,
      },
      'expenditureBreakdown': breakdown == null
          ? null
          : {
              'eaten': breakdown.eaten,
              'fromWeight': breakdown.fromWeight,
              'burnt': breakdown.burnt,
              'logged': breakdown.logged,
              'of': breakdown.of,
            },
      'weeklyReports': [
        for (final w in weeklyReports(days, dates.first, f.today))
          {
            'name': 'week of ${day(w.monday)}',
            'daysLogged': w.daysLogged,
            'daysShown': w.daysShown,
            'marks': [for (final m in w.marks) m.name].join(' '),
            'kcal': versus(w.kcal),
            'standing': energyStanding(w.kcal).name,
            'protein': versus(w.protein),
            'carbs': versus(w.carbs),
            'fat': versus(w.fat),
          },
      ],
    };
  }

  Map<String, dynamic> checkIn(CheckIn c) => {
    'averageIntakeKcal': c.averageIntakeKcal,
    'loggedDays': c.loggedDays,
    'weighIns': c.weighIns,
    'trendKg': c.trendKg,
    'weekChangeKg': c.weekChangeKg,
    'expenditureKcal': c.expenditureKcal,
    'activityKcal': c.activityKcal,
    'baseKcal': c.baseKcal,
    'uncappedTargetKcal': c.uncappedTargetKcal,
    'proposedTargetKcal': c.proposedTargetKcal,
    'daysToTargetAtGoal': c.daysToTargetAtGoal,
    'daysToTargetAtTrend': c.daysToTargetAtTrend,
    'kcalPerKg': c.kcalPerKg,
    'activityChangeKcal': c.activityChangeKcal,
    'capCalibrating': c.capCalibrating,
    'movedWithinCap': c.movedWithinCap,
    'enoughData': c.enoughData,
    'belowRecommendedFloor': c.belowRecommendedFloor,
    'fromProfile': c.fromProfile,
    'breakHold': c.breakHold == null
        ? null
        : {
            'daysBack': c.breakHold!.daysBack,
            'resumesIn': c.breakHold!.resumesIn,
          },
  };

  Future<Map<String, dynamic>> adaptive() async {
    final history = await AdaptiveStore().history();
    final mark = AdaptiveService.capMark(history, openBaseSettings);
    final run = await f.service().expenditureHistory();
    // On a day just back from the break, with no check-in yet to hold to.
    final noCheckIns = AdaptiveStore.otherProfile(
      () => Hive.openBox<dynamic>('OpenNoCheckIns'),
    );
    return {
      'checkIns': [
        for (final r in history)
          {
            'name': day(r.date),
            'expenditureKcal': r.expenditureKcal,
            'proposedKcal': r.proposedKcal,
            'acceptedKcal': r.acceptedKcal,
            'baseKcal': r.baseKcal,
            'basis': r.basis,
          },
      ],
      'capMark': mark == null ? null : day(mark.date),
      'dueToday': checkInDueOn(f.today, history.lastOrNull?.date, null),
      'checkIn': checkIn(await f.service().checkIn()),
      'checkInFlat': await under(
        openVariants['adaptiveFlat']!,
        () async => checkIn(await f.service().checkIn()),
      ),
      'checkInWeekly': await under(
        openVariants['activityWeekly']!,
        () async => checkIn(await f.service().checkIn()),
      ),
      'checkInDaily': await under(
        openVariants['activityDaily']!,
        () async => checkIn(await f.service().checkIn()),
      ),
      'afterBreak d-20': checkIn(
        await f
            .service(moment: f.at(-20, 14), store: noCheckIns)
            .checkIn(),
      ),
      'estimate': {
        'days': run.length,
        'settledDays': run.where((d) => d.settled).length,
        'first': run.first.expenditureKcal,
        'last': run.last.expenditureKcal,
        'formulaKcal': await f.service().formulaKcal(),
      },
    };
  }

  Future<Map<String, dynamic>> phases() async {
    final store = PhaseStore();
    final plan = (await store.plan())!;
    final user = await f.user.getUserData();
    final data = await loadPhaseReportData(plan, f.today, f.service());
    final reports = phaseReports(
      plan,
      today: f.today,
      trendByDay: data.trendByDay,
      trackedDays: data.trackedDays,
      burnByDay: data.burnByDay,
    );
    final nowKg = data.trendByDay[f.today]!;
    return {
      'start': day(plan.start),
      'end': day(plan.end),
      'kind': plan.kind.name,
      'phases': [
        for (final (i, p) in plan.phases.indexed)
          {
            'name': '$i ${p.kind.name}',
            'kgPerWeek': p.kgPerWeek,
            'weeks': p.weeks,
            'untilKg': p.untilKg,
            'startOf': day(plan.startOf(i)),
            'weightAt': plan.weightAt(i),
          },
      ],
      'endWeight': plan.weightAt(plan.phases.length),
      'on': {
        for (final offset in [-29, -28, -8, -7, -1, 0, 30, 200])
          day(f.day(offset)): {
            'index': plan.indexOn(f.day(offset)),
            'pace': plan.paceOn(f.day(offset)),
          },
      },
      'reports': [
        for (final r in reports)
          {
            'name': '${day(r.first)} ${r.phase.kind.name}',
            'last': day(r.last),
            'running': r.running,
            'length': r.length,
            'startKg': r.startKg,
            'endKg': r.endKg,
            'changeKg': r.changeKg,
            'kgPerWeek': r.kgPerWeek,
            'plannedKg': r.plannedKg,
            'eatenKcal': r.eatenKcal,
            'days': {
              'onTarget': r.days.onTarget,
              'under': r.days.under,
              'over': r.days.over,
              'logged': r.days.logged,
            },
            'startBurnKcal': r.startBurnKcal,
            'endBurnKcal': r.endBurnKcal,
          },
      ],
      'phaseOfRate': {
        'profile': phaseOfRate(goalRateKgPerWeek(user)),
        'plan': phaseOfRate(plan.paceOn(f.today)!),
      },
      'goalStatus': goalStatus(plan, nowKg, f.today).name,
      'upcoming': [
        for (final p in await store.upcoming())
          {
            'start': day(p.start),
            'kind': p.kind.name,
            'weeks': [for (final x in p.phases) x.weeks],
          },
      ],
      'history': [
        for (final r in await store.history())
          {
            'kind': r.kind.name,
            'start': day(r.start),
            'end': day(r.end),
            'weeks': r.weeks,
            'startKg': r.startKg,
            'endKg': r.endKg,
          },
      ],
    };
  }

  Future<Map<String, dynamic>> goal() async {
    final state = await GoalStartStore().load(service: f.service(), now: f.now);
    final p = state.progress!;
    final pace = p.recentPace();
    final retargeted = resolveGoalStart(
      stored: p.start,
      targetKg: 76,
      paceKgPerWeek: p.paceKgPerWeek,
      trend: p.trend,
      today: f.today,
    );
    return {
      'start': {
        'day': day(p.start.date),
        'kg': p.start.kg,
        'targetKg': p.start.targetKg,
        'paceKgPerWeek': p.start.paceKgPerWeek,
        'planDay': day(p.start.planDate),
      },
      'nowKg': p.nowKg,
      'totalKg': p.totalKg,
      'toGoKg': p.toGoKg,
      'fraction': p.fraction,
      'daysIn': p.daysIn,
      'planKgToday': p.planKgToday,
      'planFraction': p.planFraction,
      'behindKg': p.behindKg,
      'recentPace': pace == null
          ? null
          : {'kgPerWeek': pace.kgPerWeek, 'days': pace.days},
      'sinceStartKgPerWeek': p.sinceStartKgPerWeek,
      'arrivalAtPace': switch (p.arrivalAt(p.paceKgPerWeek)) {
        final d? => day(d),
        null => null,
      },
      'expenditureKcal': state.inputs!.expenditureKcal,
      'leftKg': goalLeftKg(p.targetKg, p.nowKg, p),
      'retargetedTo76': {
        'day': day(retargeted.date),
        'kg': retargeted.kg,
        'planDay': day(retargeted.planDate),
      },
    };
  }

  Future<List<Map<String, dynamic>>> fasting() async => [
    for (final fast in recentFasts(await f.fasting.allSessions(), f.now))
      {
        'start': moment(fast.start),
        'lengthMinutes': fast.length.inMinutes,
        'targetMinutes': fast.target.inMinutes,
        'ongoing': fast.ongoing,
      },
  ];

  Future<Map<String, dynamic>> reminders() async =>
      under(openVariants['adaptive']!, () async {
        final last = await AdaptiveStore().lastCheckIn();
        final message = checkInMessage(
          await f.service().checkIn(),
          previousKcal: last?.acceptedKcal,
        );
        final scheduler = _Recorded();
        final reminders = Reminders(
          scheduler: scheduler,
          clock: () => f.now,
          checkInResult: () async => message,
        );
        await reminders.replan();
        return {
          'weighInTime': _time(await reminders.timeOf(ReminderKind.weighIn)),
          'checkInTime': _time(await reminders.timeOf(ReminderKind.checkIn)),
          'checkInMessage': message,
          'planned': [
            for (final (r, body) in scheduler.planned)
              {
                'name': r.kind.name,
                'at': moment(r.at),
                'repeatsDaily': r.repeatsDaily,
                'body': body,
              },
          ],
        };
      });

  static String? _time(ReminderTime? t) => t == null
      ? null
      : '${t.hour.toString().padLeft(2, '0')}:'
            '${t.minute.toString().padLeft(2, '0')}';
}

/// What a replan would put in the OS.
class _Recorded implements ReminderScheduler {
  final planned = <(PlannedReminder, String?)>[];

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<void> schedule(PlannedReminder reminder, {String? body}) async =>
      planned.add((reminder, body));

  @override
  Future<void> cancel(ReminderKind kind) async {}
}

/// [value] as JSON keeps it: maps with string keys, doubles to two
/// decimals so float noise cannot fail the comparison.
Object? _plain(Object? value) => switch (value) {
  final Map<dynamic, dynamic> m => <String, dynamic>{
    for (final MapEntry(:key, :value) in m.entries) '$key': _plain(value),
  },
  final Iterable<dynamic> l => [for (final v in l) _plain(v)],
  final double d when d.isFinite => (d * 100).round() / 100 + 0.0,
  final double d => '$d',
  _ => value,
};

/// The lines that tell [before] from [after], one per value changed,
/// added or removed: `path: before → after`. Lists of maps that each have
/// a distinct `id` or `name` are matched by it, so the path names the
/// thing; other lists by index.
List<String> diffSnapshots(Map<dynamic, dynamic> before, Map<dynamic, dynamic> after) {
  final out = <String>[];
  _diff('', before, after, out);
  return out;
}

void _diff(String path, Object? a, Object? b, List<String> out) {
  String at(Object key) => path.isEmpty ? '$key' : '$path.$key';
  if (a is Map && b is Map) {
    for (final key in {...a.keys, ...b.keys}) {
      if (!b.containsKey(key)) {
        out.add('${at(key)}: ${_text(a[key])} → (none)');
      } else if (!a.containsKey(key)) {
        out.add('${at(key)}: (none) → ${_text(b[key])}');
      } else {
        _diff(at(key), a[key], b[key], out);
      }
    }
  } else if (a is List && b is List) {
    final byA = _byName(a), byB = _byName(b);
    if (byA != null && byB != null) {
      _diff(path, byA, byB, out);
      return;
    }
    for (var i = 0; i < max(a.length, b.length); i++) {
      final p = '$path[$i]';
      if (i >= b.length) {
        out.add('$p: ${_text(a[i])} → (none)');
      } else if (i >= a.length) {
        out.add('$p: (none) → ${_text(b[i])}');
      } else {
        _diff(p, a[i], b[i], out);
      }
    }
  } else if (a != b) {
    out.add('$path: ${_text(a)} → ${_text(b)}');
  }
}

/// [list]'s items by their `id` or `name`; null unless each has a distinct
/// one.
Map<String, Object?>? _byName(List<dynamic> list) {
  if (list.isEmpty) return null;
  final out = <String, Object?>{};
  for (final item in list) {
    final key = item is Map ? item['id'] ?? item['name'] : null;
    if (key == null || out.containsKey('$key')) return null;
    out['$key'] = item;
  }
  return out;
}

String _text(Object? value) => jsonEncode(value);
