import 'dart:convert';
import 'dart:io';

import 'package:home_widget/home_widget.dart';
import 'package:logging/logging.dart';
import 'package:opennutritracker/core/domain/entity/body_weight_unit_entity.dart';
import 'package:opennutritracker/core/utils/calc/unit_calc.dart';
import 'package:opennutritracker/core/utils/widget/calorie_widget_snapshot.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_service.dart';
import 'package:opennutritracker/fork/adaptive/goal_plan.dart';
import 'package:opennutritracker/fork/units/weight_text.dart';

/// Today's energy and macros for OpenBite's Android home-screen widget
/// (`MacroWidgetProvider`, `android/app/src/fork/kotlin`), which upstream
/// has no Android counterpart of. Written beside upstream's calorie
/// snapshot each time Home loads; the widget shows nothing once upstream's
/// is cleared (a profile wiped or switched away), and zero eaten once the
/// logical [dayId] is over.
class MacroWidgetFigures {
  static const storageKey = 'openbite_macro_widget';
  static const androidProvider =
      'com.opennutritracker.ont.opennutritracker.fork.MacroWidgetProvider';

  final String dayId;
  final int offsetMinutes;

  /// In the user's energy unit: [energyUnit] is 'kcal' or 'kJ'.
  final int energy;
  final int energyGoal;
  final String energyUnit;
  final int protein;
  final int proteinGoal;
  final int carbs;
  final int carbsGoal;
  final int fat;
  final int fatGoal;

  const MacroWidgetFigures({
    required this.dayId,
    required this.offsetMinutes,
    required this.energy,
    required this.energyGoal,
    required this.energyUnit,
    required this.protein,
    required this.proteinGoal,
    required this.carbs,
    required this.carbsGoal,
    required this.fat,
    required this.fatGoal,
  });

  factory MacroWidgetFigures.fromHome({
    required DateTime logicalDay,
    required int offsetMinutes,
    required bool kilojoules,
    required double kcal,
    required double kcalGoal,
    required double protein,
    required double proteinGoal,
    required double carbs,
    required double carbsGoal,
    required double fat,
    required double fatGoal,
  }) {
    int energy(double kcal) =>
        (kilojoules ? UnitCalc.kcalToKj(kcal) : kcal).round();
    return MacroWidgetFigures(
      dayId: CalorieWidgetSnapshot.formatDayId(logicalDay),
      offsetMinutes: CalorieWidgetSnapshot.sanitiseOffsetMinutes(offsetMinutes),
      energy: energy(kcal),
      energyGoal: energy(kcalGoal),
      energyUnit: kilojoules ? 'kJ' : 'kcal',
      protein: protein.round(),
      proteinGoal: proteinGoal.round(),
      carbs: carbs.round(),
      carbsGoal: carbsGoal.round(),
      fat: fat.round(),
      fatGoal: fatGoal.round(),
    );
  }

  Map<String, Object> toJson() => {
    'day': dayId,
    'offsetMinutes': offsetMinutes,
    'energy': [energy, energyGoal],
    'energyUnit': energyUnit,
    'protein': [protein, proteinGoal],
    'carbs': [carbs, carbsGoal],
    'fat': [fat, fatGoal],
  };

  String encode() => jsonEncode(toJson());
}

final _log = Logger('MacroWidget');

/// Seam S50: saves [figures] and redraws the Android widget; a failure is
/// logged, never in Home's way. [stillCurrent] false (a clear ran since
/// Home read them) drops them, as upstream's write does.
Future<void> publishMacroWidget(
  MacroWidgetFigures figures, {
  bool Function()? stillCurrent,
}) async {
  if (!Platform.isAndroid) return;
  try {
    if (stillCurrent != null && !stillCurrent()) return;
    await HomeWidget.saveWidgetData<String>(
      MacroWidgetFigures.storageKey,
      figures.encode(),
    );
    await HomeWidget.updateWidget(
      qualifiedAndroidName: MacroWidgetFigures.androidProvider,
    );
  } catch (error, stack) {
    _log.fine('Could not update the macro widget', error, stack);
  }
}

/// The trend weight for the second Android widget (`WeightWidgetProvider`):
/// MacroFactor's smoothed weight and how far it moved in a week, already
/// in the user's unit.
class WeightWidgetFigures {
  static const storageKey = 'openbite_weight_widget';
  static const androidProvider =
      'com.opennutritracker.ont.opennutritracker.fork.WeightWidgetProvider';

  final String trend;

  /// "-0.4 kg in 7 days"; null with under a week of trend.
  final String? change;

  const WeightWidgetFigures({required this.trend, required this.change});

  /// From the goal planner's trend, null before the first weigh-in.
  static WeightWidgetFigures? fromTrend(
    List<double> pastTrendKg,
    BodyWeightUnit unit,
  ) {
    if (pastTrendKg.isEmpty) return null;
    final week = trendChanges(pastTrendKg)[7];
    return WeightWidgetFigures(
      trend: weightText(pastTrendKg.last, unit),
      change: week == null ? null : '${weightChangeText(week, unit)} in 7 days',
    );
  }

  String encode() => jsonEncode({'trend': trend, 'change': change});
}

/// Seam S50 too: the weight widget's figures, or none (it then asks to log
/// a weigh-in).
Future<void> publishWeightWidget(
  BodyWeightUnit unit, {
  bool Function()? stillCurrent,
}) async {
  if (!Platform.isAndroid) return;
  try {
    final plan = await AdaptiveService.fromLocator().goalPlan();
    final figures = plan == null
        ? null
        : WeightWidgetFigures.fromTrend(plan.pastTrendKg, unit);
    if (stillCurrent != null && !stillCurrent()) return;
    await HomeWidget.saveWidgetData<String>(
      WeightWidgetFigures.storageKey,
      figures?.encode(),
    );
    await HomeWidget.updateWidget(
      qualifiedAndroidName: WeightWidgetFigures.androidProvider,
    );
  } catch (error, stack) {
    _log.fine('Could not update the weight widget', error, stack);
  }
}
